import Foundation

/// Homey App Store catalogue (apps-api.athom.com). The public endpoints need no login;
/// when an account is active, its `apps` delegation token is sent along so apps
/// that are only visible to you (e.g. your own test-only apps) show up too.
@MainActor
struct StoreAPI {
    var auth: AuthManager?

    /// `requireAuth`: the call only works for a logged-in account (e.g. `/app/me`).
    private func get(_ path: String, query: [URLQueryItem] = [], requireAuth: Bool = false) async throws -> JSON {
        guard var comps = URLComponents(string: Config.appsAPI + path) else {
            throw APIError(status: 0, message: L("Ongeldig pad"), url: path)
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(status: 0, message: L("Ongeldig pad"), url: path) }
        var headers: [String: String] = [:]
        // Only send the account token when the session is known to work; an expired
        // web session would otherwise cost a slow refresh on every catalogue call.
        if let auth, requireAuth ? auth.isLoggedIn : auth.hasUsableSession {
            if let token = try? await auth.delegationToken(audience: "apps") {
                headers["Authorization"] = "Bearer \(token)"
            } else if requireAuth {
                throw APIError(status: 401, message: L("Je sessie is verlopen. Log opnieuw in."), url: path)
            }
        }
        try Task.checkCancellation()
        do {
            return try await HTTP.send(url, headers: headers).json
        } catch let e as APIError where (e.status == 401 || e.status == 403) && !headers.isEmpty && !requireAuth {
            auth?.invalidateDelegation("apps")
            return try await HTTP.send(url).json   // fall back to the public catalogue
        }
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }

    func highlights(platform: StorePlatform) async throws -> StoreHighlights {
        StoreHighlights(try await get("/app/highlight2", query: [
            .init(name: "platform", value: platform.rawValue),
            .init(name: "language", value: Config.storeLanguage),
        ]))
    }

    func browse(platform: StorePlatform, query: String = "", category: StoreCategory? = nil,
                connectivity: StoreConnectivity? = nil, widgetsOnly: Bool = false,
                limit: Int = 30, offset: Int = 0) async throws -> BrowsePage {
        var q: [URLQueryItem] = [
            .init(name: "platform", value: platform.rawValue),
            .init(name: "language", value: Config.storeLanguage),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { q.append(.init(name: "query", value: trimmed)) }
        if let category { q.append(.init(name: "category", value: category.rawValue)) }
        if let connectivity { q.append(.init(name: "connectivity", value: connectivity.rawValue)) }
        if widgetsOnly { q.append(.init(name: "features", value: "widgets")) }
        let j = try await get("/app/browse", query: q)
        let items = (j["items"].array.isEmpty ? j.array : j["items"].array).compactMap(StoreApp.init)
        return BrowsePage(items: items, total: j["total"].int, received: j["items"].array.isEmpty ? j.array.count : j["items"].array.count)
    }

    func app(_ id: String) async throws -> StoreAppDetail {
        guard let d = StoreAppDetail(try await get("/app/\(enc(id))")) else {
            throw APIError(status: 404, message: L("App niet gevonden."), url: id)
        }
        return d
    }

    func changelog(_ id: String) async throws -> [ChangelogEntry] {
        ChangelogEntry.parse(try await get("/app/\(enc(id))/changelog"))
    }

    func reviews(_ id: String) async throws -> [StoreReview] {
        try await get("/app/\(enc(id))/review").array.compactMap(StoreReview.init)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// All live apps of one developer (`GET /app?author=`).
    func apps(byAuthor authorId: String) async throws -> [StoreApp] {
        guard !authorId.isEmpty else { return [] }
        return try await get("/app", query: [.init(name: "author", value: authorId), .init(name: "count", value: "19")])
            .items.compactMap(StoreApp.init)
    }

    /// Apps of the logged-in developer, including ones that only have a test build.
    func myApps() async throws -> [StoreApp] {
        try await get("/app/me", requireAuth: true).items.compactMap(StoreApp.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
