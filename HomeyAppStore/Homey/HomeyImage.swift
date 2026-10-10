import SwiftUI
import UIKit

/// Small memory + disk image cache for remote rasters (product images, app photos).
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20)
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    func cached(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return memory.object(forKey: url as NSURL)
    }

    func image(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let t = tasks[url] { return await t.value }
        let task = Task { @MainActor () -> UIImage? in
            guard let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let img = UIImage(data: data) else { return nil }
            return img
        }
        tasks[url] = task
        let img = await task.value
        tasks[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }
}

/// Remote raster image with a placeholder; scales to fit or fill.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = RemoteImageCache.shared.cached(url) { image = hit; return }
            let img = await RemoteImageCache.shared.image(url)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}

/// Product image of a Homey (black Homey Pro, Homey Cloud house, Self-Hosted
/// Server box, …) — the same images my.homey.app shows, light or dark.
struct HomeyImage: View {
    let homey: HomeyRef
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RemoteImage(url: scheme == .dark ? (homey.imageDark ?? homey.imageLight) : (homey.imageLight ?? homey.imageDark)) {
            Image(systemName: homey.fallbackSymbol)
                .font(.system(size: size * 0.42))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One Homey in a list, styled like the "Mijn Homeys" menu on my.homey.app:
/// product image, name, model and a checkmark for the selected one.
struct HomeyRow: View {
    let homey: HomeyRef
    var selected = false
    var trailing: String? = nil
    var trailingTint: Color = .secondary
    var subtitleOverride: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            HomeyImage(homey: homey, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(homey.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                Text(subtitleOverride ?? homey.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption2.weight(.semibold)).foregroundStyle(trailingTint)
            }
            if selected {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
