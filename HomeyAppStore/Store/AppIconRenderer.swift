import SwiftUI
import UIKit
import WebKit

/// Homey app icons are SVGs. homey.app draws them as a white mask on the app's
/// brand colour; we do the same, App Store–style as a rounded tile.
///
/// SwiftUI can't draw SVG, so one hidden, transparent web page draws each icon on a
/// `<canvas>` and hands back a PNG. Downloads run in parallel; drawing happens one at
/// a time, newest request first (what you just scrolled to). Results are cached in a
/// size-limited memory cache and on disk.
@MainActor
final class AppIconRenderer: NSObject, WKNavigationDelegate {
    static let shared = AppIconRenderer()

    private let size: CGFloat = 180
    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024   // ~60 MB of decoded icons
        return c
    }()
    /// Icons that can't exist (HTTP 4xx). Network trouble is never remembered.
    private var failed: Set<String> = []
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var waiters: [String: Int] = [:]

    // One drawing at a time, last-in-first-out.
    private var drawing = false
    private var slotQueue: [CheckedContinuation<Void, Never>] = []

    private var webView: WKWebView?
    private var pageReady = false

    private lazy var diskDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // Older builds cached broken (nearly transparent) icons; throw those away.
        for old in ["AppIcons", "AppIcons-v2"] { try? FileManager.default.removeItem(at: caches.appendingPathComponent(old)) }
        let dir = caches.appendingPathComponent("AppIcons-v3", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Public

    func cached(_ url: URL?, color: String) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: key(url, color) as NSString)
    }

    func hasFailed(_ url: URL?, color: String) -> Bool {
        guard let url else { return true }
        return failed.contains(key(url, color))
    }

    /// Called when the app becomes active again or the network returns.
    func retryFailures() {
        failed.removeAll()
    }

    func icon(_ url: URL, color: String) async -> UIImage? {
        let k = key(url, color)
        if let img = memory.object(forKey: k as NSString) { return img }
        if failed.contains(k) { return nil }

        let task: Task<UIImage?, Never>
        if let running = inflight[k] {
            task = running
        } else {
            task = Task { @MainActor in await self.produce(url, color: color, key: k) }
            inflight[k] = task
        }
        waiters[k, default: 0] += 1
        let img = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.dropWaiter(k) }
        }
        if !Task.isCancelled { dropWaiter(k) }
        if inflight[k] == task { inflight[k] = nil }
        return img
    }

    // MARK: Pipeline

    private func dropWaiter(_ k: String) {
        guard let n = waiters[k] else { return }
        if n <= 1 {
            waiters[k] = nil
            // Nobody wants this icon any more (scrolled away): stop working on it.
            if let t = inflight[k] { t.cancel(); inflight[k] = nil }
        } else {
            waiters[k] = n - 1
        }
    }

    private func produce(_ url: URL, color: String, key k: String) async -> UIImage? {
        // 1. Disk cache (read off the main thread).
        let file = diskDir.appendingPathComponent(k + ".png")
        let cachedData = await Task.detached(priority: .utility) { try? Data(contentsOf: file) }.value
        if let cachedData, let img = UIImage(data: cachedData, scale: 3) {
            store(img, k)
            return img
        }

        // 2. Download (in parallel with other icons).
        let data: Data
        do {
            let (d, resp) = try await HTTP.session.data(from: url)
            if let http = resp as? HTTPURLResponse, (400..<500).contains(http.statusCode) {
                failed.insert(k)
                return nil
            }
            guard !d.isEmpty else { return nil }
            data = d
        } catch {
            return nil   // offline / cancelled: try again next time
        }
        guard !Task.isCancelled else { return nil }

        // 3. Draw (one at a time, newest first).
        await acquireSlot()
        defer { releaseSlot() }
        guard !Task.isCancelled else { return nil }
        var img = await draw(data, url: url, color: color)
        if img == nil, !Task.isCancelled {
            reloadPage()
            img = await draw(data, url: url, color: color)
        }
        guard let img else { return nil }
        store(img, k)
        if let png = img.pngData() {
            Task.detached(priority: .background) { try? png.write(to: file, options: .atomic) }
        }
        return img
    }

    private func store(_ img: UIImage, _ k: String) {
        let px = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
        memory.setObject(img, forKey: k as NSString, cost: px)
    }

    private func acquireSlot() async {
        if !drawing { drawing = true; return }
        await withCheckedContinuation { slotQueue.append($0) }
    }

    private func releaseSlot() {
        if let next = slotQueue.popLast() { next.resume() } else { drawing = false }
    }

    private func key(_ url: URL, _ color: String) -> String {
        let raw = url.absoluteString + "|" + color
        return String(raw.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }, radix: 16)
    }

    // MARK: Drawing

    private func draw(_ data: Data, url: URL, color: String) async -> UIImage? {
        let bg = Color(hex: color) != nil ? color : "#0A84FF"
        let head = String(decoding: data.prefix(512), as: UTF8.self)
        let isSVG = url.pathExtension.lowercased() == "svg" || head.contains("<svg")
        let mime = isSVG ? "image/svg+xml" : (url.pathExtension.lowercased() == "jpg" ? "image/jpeg" : "image/png")
        guard let wv = await readyWebView() else { return nil }
        let args: [String: Any] = ["bg": bg, "svg": isSVG, "mime": mime, "b64": data.base64EncodedString(), "px": 3 * Int(size)]
        guard let b64 = await evaluate(wv, args: args, timeout: 6),
              let png = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: png, scale: 3)
    }

    /// Runs the drawing script with a hard time-out: whichever comes first wins,
    /// the other is ignored. A hanging page can never block the queue.
    private func evaluate(_ wv: WKWebView, args: [String: Any], timeout: Double) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            var finished = false
            func finish(_ value: String?) {
                guard !finished else { return }
                finished = true
                c.resume(returning: value)
            }
            wv.callAsyncJavaScript(Self.drawJS, arguments: args, in: nil, in: .page) { result in
                finish((try? result.get()) as? String)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if !finished { self.reloadPage() }
                finish(nil)
            }
        }
    }

    private static let drawJS = """
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    let src;
    if (svg) {
      let text = new TextDecoder().decode(bytes);
      try {
        const doc = new DOMParser().parseFromString(text, 'image/svg+xml');
        const el = doc.documentElement;
        if (el && el.nodeName.toLowerCase() === 'svg') {
          const w = parseFloat(el.getAttribute('width')), h = parseFloat(el.getAttribute('height'));
          if (!el.getAttribute('viewBox') && w > 0 && h > 0) el.setAttribute('viewBox', `0 0 ${w} ${h}`);
          // Give the SVG a real size so every browser can draw it to a canvas.
          el.setAttribute('width', '512'); el.setAttribute('height', '512');
          el.setAttribute('preserveAspectRatio', 'xMidYMid meet');
          if (!el.getAttribute('xmlns')) el.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
          text = new XMLSerializer().serializeToString(el);
        }
      } catch (e) {}
      src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(text);
    } else {
      src = 'data:' + mime + ';base64,' + b64;
    }
    const img = new Image();
    img.src = src;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = c.height = px;
    const g = c.getContext('2d');
    g.fillStyle = bg;
    g.fillRect(0, 0, px, px);
    if (svg) {
      const s = px * 0.62, o = (px - s) / 2;
      const m = document.createElement('canvas');
      m.width = m.height = px;
      const mg = m.getContext('2d');
      mg.drawImage(img, o, o, s, s);
      mg.globalCompositeOperation = 'source-in';
      mg.fillStyle = '#ffffff';
      mg.fillRect(0, 0, px, px);
      g.drawImage(m, 0, 0);
    } else {
      const r = Math.max(px / img.naturalWidth, px / img.naturalHeight);
      const w = img.naturalWidth * r, h = img.naturalHeight * r;
      g.drawImage(img, (px - w) / 2, (px - h) / 2, w, h);
    }
    return c.toDataURL('image/png').split(',')[1];
    """

    // MARK: Web view

    /// One persistent, empty, transparent page used only to run the canvas code.
    /// It is parked behind the UI so WebKit keeps it running; it shows nothing.
    private func readyWebView() async -> WKWebView? {
        if let webView, webView.window != nil, pageReady { return webView }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        let wv: WKWebView
        if let webView {
            wv = webView
        } else {
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 4, height: 4), configuration: cfg)
            wv.navigationDelegate = self
            wv.isUserInteractionEnabled = false
            wv.scrollView.isScrollEnabled = false
            wv.isOpaque = false
            wv.backgroundColor = .clear
            wv.scrollView.backgroundColor = .clear
            wv.accessibilityElementsHidden = true
            webView = wv
        }
        if wv.superview !== window { window.insertSubview(wv, at: 0) }
        if !pageReady {
            wv.loadHTMLString("<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head><body><i id=\"i\"></i></body></html>", baseURL: nil)
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(50))
                if (try? await wv.evaluateJavaScript("document.getElementById('i') != null")) as? Bool == true {
                    pageReady = true
                    break
                }
            }
        }
        return pageReady ? wv : nil
    }

    private func reloadPage() {
        pageReady = false
    }

    /// iOS may stop the web content process in the background; start a fresh page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
    }
}

struct StoreAppIcon: View {
    let url: URL?
    let brandColor: String
    var name: String = ""
    var size: CGFloat = 60
    /// The app's raster image (`imageSmall`/`imageLarge`), used if the icon can't be drawn.
    var fallbackURL: URL? = nil

    @State private var image: UIImage?
    @State private var useFallback = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(hex: brandColor) ?? Theme.accent)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if useFallback, let fallbackURL {
                RemoteImage(url: fallbackURL, contentMode: .fill) { initial }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        // Re-runs when the network comes back, so icons that failed offline appear.
        .task(id: "\(url?.absoluteString ?? "")|\(brandColor)|\(NetworkMonitor.shared.reconnects)") {
            image = nil
            useFallback = false
            guard let url else { useFallback = true; return }
            if let hit = AppIconRenderer.shared.cached(url, color: brandColor) { image = hit; return }
            if AppIconRenderer.shared.hasFailed(url, color: brandColor) == false {
                image = await AppIconRenderer.shared.icon(url, color: brandColor)
            }
            if image == nil { useFallback = true }
        }
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }
}
