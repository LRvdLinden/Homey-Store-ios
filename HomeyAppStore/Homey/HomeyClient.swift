import Foundation

/// An app installed on a Homey (`GET /api/manager/apps/app/`).
/// Field meanings follow my.homey.app: `channel` is `live`/`test`/`beta`,
/// `origin` is `appstore` for store installs (`devkit_run`/`devkit_install` for the CLI).
struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let origin: String
    let channel: String
    let enabled: Bool
    let autoUpdate: Bool
    let brandColor: String
    /// `running`, `starting`, `stopped`, `crashed`, …
    let state: String
    let crashed: Bool
    let crashedMessage: String
    /// Version Homey itself says is ready to install (Homey Pro), if any.
    let updateVersion: String?
    /// New permissions the update asks for.
    let updatePermissions: [String]
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
        brandColor = j.firstString("color", "brandColor")
        state = j.firstString("state")
        crashed = j["crashed"].bool ?? (j.firstString("state") == "crashed")
        crashedMessage = j.firstString("crashedMessage")
        let upd = j["updateAvailable"]
        let updVersion = upd.isContainer ? upd.firstString("version") : ""
        updateVersion = updVersion.isEmpty ? nil : updVersion
        updatePermissions = upd["permissions"].array.compactMap(\.string)
        let iconObj = j["iconObj"]
        let path = iconObj.isContainer ? iconObj.firstString("url") : j.firstString("icon")
        iconPath = path.isEmpty ? "/app/\(id)/assets/icon.svg" : path
    }

    var isTest: Bool { channel == "test" || channel == "beta" }
    var isFromStore: Bool { origin.isEmpty || origin == "appstore" }
    var isDevkit: Bool { !isFromStore }
    var installedChannel: InstallChannel { isTest ? .test : .live }

    func iconURL(on homey: HomeyRef) -> URL? {
        if iconPath.hasPrefix("http") { return URL(string: iconPath) }
        let base = homey.remoteURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + (iconPath.hasPrefix("/") ? iconPath : "/" + iconPath))
    }

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
    private var loginTask: Task<String, Error>?

    init(homey: HomeyRef, auth: AuthManager) {
        self.homey = homey
        self.auth = auth
    }

    /// Restart, auto-update and installing a specific version exist on Homey Pro
    /// (and Self-Hosted Server), not on Homey Cloud.
    var supportsAppManagement: Bool { !homey.isCloud }

    private func login() async throws -> String {
        if let session { return session }
        if let loginTask { return try await loginTask.value }
        let task = Task { @MainActor () throws -> String in
            let delegation = try await self.auth.delegationToken(audience: "homey")
            let resp = try await HTTP.send(
                self.homey.remoteURL.appendingPathComponent("api/manager/users/login"),
                method: "POST",
                body: JSON.object(["token": .string(delegation)]).data()
            ).json
            let token = resp.string ?? resp.firstString("token", "session")
            guard !token.isEmpty else {
                throw APIError(status: 0, message: L("Geen Homey-sessie ontvangen."), url: self.homey.remoteURL.absoluteString)
            }
            return token
        }
        loginTask = task
        defer { loginTask = nil }
        let token = try await task.value
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

    private func enc(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    func installedApps() async throws -> [InstalledApp] {
        try await request("/api/manager/apps/app/").items.compactMap(InstalledApp.init)
    }

    /// ManagerApps.installFromAppStore — exactly what my.homey.app sends:
    /// `{ id, channel, version }`. For an update the version is required: without it
    /// Homey sees the app as already installed and does nothing. `channel` is the
    /// channel name Homey uses (e.g. the installed app's own `channel` value).
    func install(appId: String, channel: String?, version: String?) async throws {
        // For "back to live" the channel name differs between firmware versions; try the
        // known names, then Homey's default channel.
        var candidates: [String?] = [channel]
        if channel == "live" { candidates = ["live", "stable", nil] }
        for (i, ch) in candidates.enumerated() {
            var body: [String: JSON] = ["id": .string(appId)]
            if let ch, !ch.isEmpty { body["channel"] = .string(ch) }
            if let version, !version.isEmpty { body["version"] = .string(version) }
            do {
                _ = try await request("/api/manager/apps/store", method: "POST", json: .object(body), timeout: 240)
                return
            } catch let e as APIError where e.status == 400 && i < candidates.count - 1 {
                continue
            }
        }
    }

    func uninstall(appId: String) async throws {
        _ = try await request("/api/manager/apps/app/\(enc(appId))", method: "DELETE", timeout: 60)
    }

    func restart(appId: String) async throws {
        _ = try await request("/api/manager/apps/app/\(enc(appId))/restart", method: "POST", timeout: 60)
    }

    func setAutoUpdate(appId: String, _ on: Bool) async throws {
        _ = try await request("/api/manager/apps/app/\(enc(appId))", method: "PUT", json: .object(["autoupdate": .bool(on)]))
    }
}
