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
    @ObservationIgnored private var detailLoadedAt: [String: Date] = [:]
    @ObservationIgnored private var generation = 0

    init() {
        platform = StorePlatform(rawValue: UserDefaults.standard.string(forKey: "store.platform") ?? "") ?? .local
    }

    var current: StoreHighlights { highlights[platform] ?? StoreHighlights() }

    func loadHighlights(auth: AuthManager, force: Bool = false) async {
        let p = platform
        let gen = generation
        if !force, highlights[p] != nil { highlightsLoading = false; return }
        defer { highlightsLoading = false }
        do {
            let h = try await StoreAPI(auth: auth).highlights(platform: p)
            guard gen == generation else { return }
            highlights[p] = h
            highlightsError[p] = nil
        } catch {
            guard gen == generation, let msg = ErrorText.message(error) else { return }
            highlightsError[p] = msg
        }
    }

    /// App detail, cached; concurrent callers share one request.
    @discardableResult
    func detail(_ id: String, auth: AuthManager, force: Bool = false) async -> StoreAppDetail? {
        if !force, let d = details[id] { return d }
        if !force, let t = detailTasks[id] { return await t.value }
        let gen = generation
        let task = Task { @MainActor () -> StoreAppDetail? in
            try? await StoreAPI(auth: auth).app(id)
        }
        detailTasks[id] = task
        let d = await task.value
        if detailTasks[id] == task { detailTasks[id] = nil }
        guard gen == generation else { return d }
        if let d {
            details[id] = d
            detailLoadedAt[id] = Date()
        }
        return d
    }

    /// Loads or refreshes the details of many apps (for update checks), at most six at
    /// a time. Details younger than `maxAge` are kept.
    func refreshDetails(_ ids: [String], auth: AuthManager, maxAge: TimeInterval = 600) async {
        let now = Date()
        let todo = ids.filter { id in
            guard let at = detailLoadedAt[id], details[id] != nil else { return true }
            return now.timeIntervalSince(at) > maxAge
        }
        await withTaskGroup(of: Void.self) { group in
            var pending = todo.makeIterator()
            for _ in 0..<6 {
                guard let id = pending.next() else { break }
                group.addTask { @MainActor in _ = await self.detail(id, auth: auth, force: true) }
            }
            while await group.next() != nil {
                guard let id = pending.next() else { continue }
                group.addTask { @MainActor in _ = await self.detail(id, auth: auth, force: true) }
            }
        }
    }

    /// Forget everything fetched with the previous account (its token may have shown
    /// private or test-only apps).
    func reset(generation: Int) {
        guard generation != self.generation else { return }
        self.generation = generation
        highlights.removeAll()
        highlightsError.removeAll()
        details.removeAll()
        detailLoadedAt.removeAll()
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
    }
}
