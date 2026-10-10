import Foundation

/// Homey App Store catalogue (apps-api.athom.com). The public endpoints need no login;
/// when an account is active, its `apps` delegation token is sent along so apps
/// that are only visible to you (e.g. your own test-only apps) show up too.
@MainActor
struct StoreAPI {
    var auth: AuthManager?

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> JSON {
        guard var comps = URLComponents(string: Config.appsAPI + path) else {
            throw APIError(status: 0, message: L("Ongeldig pad"), url: path)
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(status: 0, message: L("Ongeldig pad"), url: path) }
        var headers: [String: String] = [:]
        if let auth, auth.isLoggedIn, let token = try? await auth.delegationToken(audience: "apps") {
            headers["Authorization"] = "Bearer \(token)"
        }
        do {
            return try await HTTP.send(url, headers: headers).json
        } catch let e as APIError where (e.status == 401 || e.status == 403) && !headers.isEmpty {
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
        let j = try await get("/app/browse", query: q)
        let items = (j["items"].array.isEmpty ? j.array : j["items"].array).compactMap(StoreApp.init)
        return BrowsePage(items: items, total: j["total"].int ?? items.count)
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
}
