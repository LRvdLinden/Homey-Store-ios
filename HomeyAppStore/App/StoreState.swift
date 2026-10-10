import Foundation
import Observation

/// Shared store state: which store (Homey Pro / Homey Cloud) you're browsing,
/// the store front per platform, and a cache of app details.
@MainActor
@Observable
final class StoreState {
    var platform: StorePlatform {
        didSet { UserDefaults.standard.set(platform.rawValue, forKey: "store.platform") }
    }

    private(set) var highlights: [StorePlatform: StoreHighlights] = [:]
    private(set) var highlightsError: [StorePlatform: String] = [:]
    /// True from launch until the first store front request has finished.
    private(set) var highlightsLoading = true

    private(set) var details: [String: StoreAppDetail] = [:]
    @ObservationIgnored private var detailTasks: [String: Task<StoreAppDetail?, Never>] = [:]

    init() {
        platform = StorePlatform(rawValue: UserDefaults.standard.string(forKey: "store.platform") ?? "") ?? .local
    }

    var current: StoreHighlights { highlights[platform] ?? StoreHighlights() }

    func loadHighlights(auth: AuthManager, force: Bool = false) async {
        let p = platform
        if !force, highlights[p] != nil { highlightsLoading = false; return }
        defer { highlightsLoading = false }
        do {
            highlights[p] = try await StoreAPI(auth: auth).highlights(platform: p)
            highlightsError[p] = nil
        } catch {
            highlightsError[p] = error.localizedDescription
        }
    }

    /// App detail, cached; concurrent callers share one request.
    @discardableResult
    func detail(_ id: String, auth: AuthManager, force: Bool = false) async -> StoreAppDetail? {
        if !force, let d = details[id] { return d }
        if !force, let t = detailTasks[id] { return await t.value }
        let task = Task { @MainActor () -> StoreAppDetail? in
            try? await StoreAPI(auth: auth).app(id)
        }
        detailTasks[id] = task
        let d = await task.value
        detailTasks[id] = nil
        if let d { details[id] = d }
        return d
    }

    func dropCache() {
        highlights.removeAll()
        details.removeAll()
    }
}
