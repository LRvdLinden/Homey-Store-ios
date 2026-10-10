import SwiftUI
import UIKit
import WebKit

/// Homey app icons are SVGs. homey.app draws them as a white mask on a circle in
/// the app's brand colour; we do the same, App Store–style as a rounded tile.
/// SwiftUI can't draw SVG, so a single hidden web page renders each icon once
/// (white glyph on brand colour), and the result is cached in memory and on disk.
@MainActor
final class AppIconRenderer {
    static let shared = AppIconRenderer()

    private let size: CGFloat = 180
    private var memory: [String: UIImage] = [:]
    private var failed: Set<String> = []
    private var waiting: [String: [CheckedContinuation<UIImage?, Never>]] = [:]
    private var queue: [(key: String, url: URL, color: String)] = []
    private var busy = false
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

    func cached(_ url: URL?, color: String) -> UIImage? {
        guard let url else { return nil }
        return memory[key(url, color)]
    }

    func hasFailed(_ url: URL?, color: String) -> Bool {
        guard let url else { return true }
        return failed.contains(key(url, color))
    }

    func icon(_ url: URL, color: String) async -> UIImage? {
        let k = key(url, color)
        if let img = memory[k] { return img }
        if failed.contains(k) { return nil }
        let file = diskDir.appendingPathComponent(k + ".png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data, scale: 3) {
            memory[k] = img
            return img
        }
        return await withCheckedContinuation { c in
            if waiting[k] != nil { waiting[k]!.append(c); return }
            waiting[k] = [c]
            queue.append((k, url, color))
            pump()
        }
    }

    private func key(_ url: URL, _ color: String) -> String {
        let raw = url.absoluteString + "|" + color
        return String(raw.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }, radix: 16)
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let job = queue.removeFirst()
        Task {
            var img: UIImage?
            for attempt in 0..<2 where img == nil {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(400)) }
                img = await render(job.url, color: job.color)
            }
            if let img {
                memory[job.key] = img
                if let png = img.pngData() { try? png.write(to: diskDir.appendingPathComponent(job.key + ".png")) }
            } else {
                failed.insert(job.key)
            }
            waiting.removeValue(forKey: job.key)?.forEach { $0.resume(returning: img) }
            busy = false
            pump()
        }
    }

    private func render(_ url: URL, color: String) async -> UIImage? {
        guard let (data, resp) = try? await HTTP.session.data(from: url), !data.isEmpty,
              (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        let bg = Color(hex: color) != nil ? color : "#0A84FF"
        let head = String(decoding: data.prefix(512), as: UTF8.self)
        let isSVG = url.pathExtension.lowercased() == "svg" || head.contains("<svg")
        let mime = isSVG ? "image/svg+xml" : (url.pathExtension.lowercased() == "jpg" ? "image/jpeg" : "image/png")
        guard let wv = await readyWebView() else { return nil }

        // Draw on a <canvas> at 3× and hand back a finished PNG: brand colour plus
        // the SVG as a white mask (exactly how homey.app shows it). No view snapshot,
        // so it doesn't matter whether the web view is visible.
        let b64 = await withTimeout(seconds: 6) {
            (try? await wv.callAsyncJavaScript(Self.drawJS,
                                                arguments: ["bg": bg, "svg": isSVG, "mime": mime, "b64": data.base64EncodedString(), "px": 3 * Int(self.size)],
                                                contentWorld: .page)) as? String
        } ?? nil
        guard let b64, let png = Data(base64Encoded: b64), let img = UIImage(data: png, scale: 3) else { return nil }
        return img
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
            wv = WKWebView(frame: CGRect(x: 0, y: 0, width: size, height: size), configuration: cfg)
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
            wv.loadHTMLString("""
            <!doctype html><html><head><meta name="viewport" content="width=\(Int(size)),initial-scale=1">
            <style>html,body{margin:0;background:transparent}</style></head><body><i id="i"></i></body></html>
            """, baseURL: nil)
            // Wait until the page's script context exists.
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

    private func withTimeout<T>(seconds: Double, _ op: @escaping @MainActor () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { @MainActor in await op() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// App Store-style rounded app icon: the app's SVG icon in white on its brand
/// colour. Falls back to the app's photo, then to its initial.
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
        .task(id: "\(url?.absoluteString ?? "")|\(brandColor)") {
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
