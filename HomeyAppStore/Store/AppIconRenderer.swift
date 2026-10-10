import SwiftUI
import UIKit
import WebKit

/// Homey app icons are SVGs (one colour, drawn on the app's brand colour, like on
/// homey.app). SwiftUI can't draw SVG, so each icon is rendered once in a hidden
/// web view — white glyph on the brand colour — and cached in memory and on disk.
@MainActor
final class AppIconRenderer: NSObject, WKNavigationDelegate {
    static let shared = AppIconRenderer()

    private let size: CGFloat = 180
    private var memory: [String: UIImage] = [:]
    private var waiting: [String: [CheckedContinuation<UIImage?, Never>]] = [:]
    private var queue: [(key: String, url: URL, color: String)] = []
    private var busy = false
    private var webView: WKWebView?
    private var navDone: CheckedContinuation<Void, Never>?

    private lazy var diskDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func cached(_ url: URL?, color: String) -> UIImage? {
        guard let url else { return nil }
        return memory[key(url, color)]
    }

    func icon(_ url: URL, color: String) async -> UIImage? {
        let k = key(url, color)
        if let img = memory[k] { return img }
        let file = diskDir.appendingPathComponent(k + ".png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
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
            let img = await render(job.url, color: job.color)
            if let img {
                memory[job.key] = img
                if let png = img.pngData() { try? png.write(to: diskDir.appendingPathComponent(job.key + ".png")) }
            }
            waiting.removeValue(forKey: job.key)?.forEach { $0.resume(returning: img) }
            busy = false
            pump()
        }
    }

    private func render(_ url: URL, color: String) async -> UIImage? {
        guard let (data, _) = try? await HTTP.session.data(from: url), !data.isEmpty else { return nil }
        let bg = Color(hex: color) != nil ? color : "#0A84FF"
        let isSVG = url.pathExtension.lowercased() == "svg" || (String(data: data.prefix(256), encoding: .utf8)?.contains("<svg") ?? false)
        let mime = isSVG ? "image/svg+xml" : "image/png"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=\(Int(size)),initial-scale=1">
        <style>html,body{margin:0;padding:0;width:100%;height:100%;background:\(bg);overflow:hidden}
        div{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
        img{width:62%;height:62%;object-fit:contain;\(isSVG ? "filter:brightness(0) invert(1);" : "")}</style></head>
        <body><div><img src="data:\(mime);base64,\(data.base64EncodedString())"></div></body></html>
        """
        guard let wv = ensureWebView() else { return nil }
        // Safety net: never wait more than 4 s for a page that doesn't report back.
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.navDone?.resume(); self?.navDone = nil
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            navDone = c
            wv.loadHTMLString(html, baseURL: nil)
        }
        timeout.cancel()
        try? await Task.sleep(for: .milliseconds(30))
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: 0, y: 0, width: size, height: size)
        cfg.afterScreenUpdates = true
        return try? await wv.takeSnapshot(configuration: cfg)
    }

    /// The web view must sit in a window to paint. It's parked in the top-left
    /// corner, practically invisible (WebKit may skip painting views that are
    /// fully transparent or off-screen) and behind everything else.
    private func ensureWebView() -> WKWebView? {
        if let webView, webView.window != nil { return webView }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        let wv: WKWebView
        if let webView {
            wv = webView
        } else {
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            wv = WKWebView(frame: CGRect(x: 0, y: 0, width: size, height: size), configuration: cfg)
            wv.navigationDelegate = self
            wv.isUserInteractionEnabled = false
            wv.scrollView.isScrollEnabled = false
            wv.alpha = 0.011
            wv.accessibilityElementsHidden = true
        }
        window.insertSubview(wv, at: 0)
        webView = wv
        return wv
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navDone?.resume(); navDone = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navDone?.resume(); navDone = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navDone?.resume(); navDone = nil
    }
}

/// App Store-style rounded app icon.
struct StoreAppIcon: View {
    let url: URL?
    let brandColor: String
    var name: String = ""
    var size: CGFloat = 60

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(hex: brandColor) ?? Theme.accent)
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: "\(url?.absoluteString ?? "")|\(brandColor)") {
            guard let url else { return }
            if let hit = AppIconRenderer.shared.cached(url, color: brandColor) { image = hit; return }
            image = await AppIconRenderer.shared.icon(url, color: brandColor)
        }
        .accessibilityHidden(true)
    }
}
