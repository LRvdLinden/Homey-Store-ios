import Foundation

/// An app installed on a Homey (`GET /api/manager/apps/app/`).
struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    /// `appstore_release`, `appstore_test`, `devkit_install`, …
    let origin: String
    let channel: String
    let enabled: Bool
    let autoUpdate: Bool
    let brandColor: String
    /// Icon path on the Homey, e.g. `/app/<id>/assets/icon.svg`.
    let iconPath: String

    init?(_ j: JSON) {
        guard let id = j["id"].string, !id.isEmpty else { return nil }
        self.id = id
        name = j["name"].localized.isEmpty ? id : j["name"].localized
        version = j.firstString("version")
        origin = j.firstString("origin")
        channel = j.firstString("channel")
        enabled = j["enabled"].bool ?? true
        autoUpdate = j["autoupdate"].bool ?? false
        brandColor = j.firstString("brandColor")
        let iconObj = j["iconObj"]
        let path = iconObj.isContainer ? iconObj.firstString("url") : j.firstString("icon")
        iconPath = path.isEmpty ? "/app/\(id)/assets/icon.svg" : path
    }

    var isTest: Bool { origin.contains("test") || channel == "test" }

    func iconURL(on homey: HomeyRef) -> URL? {
        if iconPath.hasPrefix("http") { return URL(string: iconPath) }
        let base = homey.remoteURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + (iconPath.hasPrefix("/") ? iconPath : "/" + iconPath))
    }
    var isDevkit: Bool { origin.contains("devkit") }

    var originLabel: String {
        if isDevkit { return L("Ontwikkelversie (CLI)") }
        if isTest { return L("Testversie") }
        return L("Live")
    }
}

enum InstallChannel: String, Identifiable, CaseIterable {
    case live, test
    var id: String { rawValue }
    var title: String { self == .live ? L("Live") : L("Test") }
}

/// Homey Web API via the Homey's cloud remote URL (works for Homey Pro and Homey Cloud).
/// Auth: account token → delegation (`audience=homey`) → `POST /api/manager/users/login` → session Bearer.
@MainActor
final class HomeyClient {
    let homey: HomeyRef
    private let auth: AuthManager
    private var session: String?

    init(homey: HomeyRef, auth: AuthManager) {
        self.homey = homey
        self.auth = auth
    }

    private func login() async throws -> String {
        if let session { return session }
        let delegation = try await auth.delegationToken(audience: "homey")
        let resp = try await HTTP.send(
            homey.remoteURL.appendingPathComponent("api/manager/users/login"),
            method: "POST",
            body: JSON.object(["token": .string(delegation)]).data()
        ).json
        let token = resp.string ?? resp.firstString("token", "session")
        guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen Homey-sessie ontvangen."), url: homey.remoteURL.absoluteString) }
        session = token
        return token
    }

    func request(_ path: String, method: String = "GET", json body: JSON? = nil, timeout: TimeInterval? = nil) async throws -> JSON {
        let base = homey.remoteURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw APIError(status: 0, message: L("Ongeldig pad"), url: path) }
        func run() async throws -> JSON {
            let token = try await login()
            let data = body?.data() ?? ((method == "POST" || method == "PUT") ? Data("{}".utf8) : nil)
            return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(token)"], body: data, timeout: timeout).json
        }
        do { return try await run() } catch let e as APIError where e.isUnauthorized {
            session = nil
            auth.invalidateDelegation("homey")
            return try await run()
        }
    }

    func installedApps() async throws -> [InstalledApp] {
        try await request("/api/manager/apps/app/").items.compactMap(InstalledApp.init)
    }

    /// ManagerApps.installFromAppStore — `channel` "test" installs the test version.
    func install(appId: String, channel: InstallChannel) async throws {
        var body: [String: JSON] = ["id": .string(appId)]
        if channel == .test { body["channel"] = .string("test") }
        if !homey.isCloud { body["waitForInstall"] = .bool(true) }
        _ = try await request("/api/manager/apps/store", method: "POST", json: .object(body), timeout: 180)
    }

    func uninstall(appId: String) async throws {
        let enc = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? appId
        _ = try await request("/api/manager/apps/app/\(enc)", method: "DELETE", timeout: 60)
    }
}
