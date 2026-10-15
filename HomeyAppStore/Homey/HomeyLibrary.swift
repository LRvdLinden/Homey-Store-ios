import Foundation
import Observation

/// Keeps track of the account's Homeys, which one you install to per store
/// (Pro / Cloud), which apps are installed on them, and running installs.
@MainActor
@Observable
final class HomeyLibrary {
    enum InstallState: Equatable {
        case idle
        case working(InstallChannel?)   // nil = removing / restarting
        case done
        case failed(String)
    }

    private(set) var installed: [String: [String: InstalledApp]] = [:]   // homeyID → appID → app
    private(set) var loadingHomeys: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var states: [String: InstallState] = [:]                // "homey|app"

    @ObservationIgnored private var clients: [String: HomeyClient] = [:]
    @ObservationIgnored private var generation = -1
    @ObservationIgnored private var refreshAgain: Set<String> = []

    // MARK: Account changes

    /// Forget everything of the previous account (called when the active account changes).
    func reset(generation: Int) {
        guard generation != self.generation else { return }
        clients.removeAll(); installed.removeAll(); errors.removeAll(); states.removeAll(); refreshAgain.removeAll()
        loadingHomeys.removeAll()
        self.generation = generation
    }

    // MARK: Target Homey per store

    private func targetKey(_ platform: StorePlatform, _ accountID: String?) -> String {
        "store.target.\(accountID ?? "-").\(platform.rawValue)"
    }

    /// Homeys that belong to a store: Homey Cloud for the Cloud store, everything else
    /// (Homey Pro, Pro mini, Self-Hosted Server) for the Pro store.
    func homeys(for platform: StorePlatform, auth: AuthManager) -> [HomeyRef] {
        auth.homeys.filter { platform == .cloud ? $0.isCloud : !$0.isCloud }
    }

    func target(for platform: StorePlatform, auth: AuthManager) -> HomeyRef? {
        let all = homeys(for: platform, auth: auth)
        let saved = UserDefaults.standard.string(forKey: targetKey(platform, auth.activeID))
        return all.first { $0.id == saved } ?? all.first(where: \.canInstall) ?? all.first
    }

    func setTarget(_ homey: HomeyRef, platform: StorePlatform, auth: AuthManager) {
        UserDefaults.standard.set(homey.id, forKey: targetKey(platform, auth.activeID))
        Task { await refresh(homey, auth: auth) }
    }

    // MARK: Installed apps

    func client(_ homey: HomeyRef, auth: AuthManager) -> HomeyClient {
        reset(generation: auth.generation)
        if let c = clients[homey.id] { return c }
        let c = HomeyClient(homey: homey, auth: auth)
        clients[homey.id] = c
        return c
    }

    func refresh(_ homey: HomeyRef, auth: AuthManager, force: Bool = false) async {
        let c = client(homey, auth: auth)
        let gen = generation
        if !force, installed[homey.id] != nil { return }
        guard !loadingHomeys.contains(homey.id) else {
            if force { refreshAgain.insert(homey.id) }   // run once more when the current load ends
            return
        }
        loadingHomeys.insert(homey.id)
        defer { loadingHomeys.remove(homey.id) }
        repeat {
            refreshAgain.remove(homey.id)
            do {
                let apps = try await c.installedApps()
                guard gen == generation else { return }
                installed[homey.id] = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                errors[homey.id] = nil
            } catch {
                guard gen == generation else { return }
                if let msg = ErrorText.message(error) { errors[homey.id] = msg }
            }
        } while refreshAgain.contains(homey.id)
    }

    func installedApp(_ appId: String, on homey: HomeyRef?) -> InstalledApp? {
        guard let homey else { return nil }
        return installed[homey.id]?[appId]
    }

    func installedCount(on homey: HomeyRef) -> Int { installed[homey.id]?.count ?? 0 }

    func state(_ appId: String, on homey: HomeyRef?) -> InstallState {
        guard let homey else { return .idle }
        return states["\(homey.id)|\(appId)"] ?? .idle
    }

    /// Clears a finished result (done / failed) so a sheet opened later starts clean.
    func clearState(_ appId: String, on homey: HomeyRef) {
        let key = "\(homey.id)|\(appId)"
        if case .working = states[key] { return }
        states[key] = nil
    }

    // MARK: Updates (one place for the whole app)

    /// The version this installed app can be updated to, or nil. Uses Homey's own
    /// `updateAvailable` first, otherwise the store version of the installed channel.
    /// Homey Cloud updates its apps itself (my.homey.app offers no update there either).
    func updateVersion(for app: InstalledApp, detail: StoreAppDetail?, on homey: HomeyRef? = nil) -> String? {
        guard app.isFromStore, homey?.isCloud != true else { return nil }
        if let v = app.updateVersion { return v }
        guard let detail else { return nil }
        let latest = app.isTest ? (detail.testVersion.isEmpty ? detail.liveVersion : detail.testVersion) : detail.liveVersion
        guard !latest.isEmpty, latest.compare(app.version, options: .numeric) == .orderedDescending else { return nil }
        return latest
    }

    func updates(on homey: HomeyRef, details: [String: StoreAppDetail]) -> [InstalledApp] {
        (installed[homey.id]?.values.map { $0 } ?? [])
            .filter { updateVersion(for: $0, detail: details[$0.id], on: homey) != nil }
    }

    // MARK: Actions

    /// Installs, updates or switches channel. Waits until the Homey really runs the
    /// expected version/channel before reporting "done".
    func install(_ appId: String, channel: InstallChannel, version: String? = nil, expectedVersion: String?,
                 on homey: HomeyRef, auth: AuthManager) async {
        let current = installed[homey.id]?[appId]
        // Keep Homey's own channel name when staying on the same channel (like my.homey.app);
        // only name a channel when installing a test version or leaving one.
        let apiChannel: String?
        if let current, current.installedChannel == channel, !current.channel.isEmpty {
            apiChannel = current.channel
        } else {
            apiChannel = channel == .test ? "test" : (current?.isTest == true ? "live" : nil)
        }
        // An installed app only changes when Homey is told which version to install.
        var sendVersion = version
        if sendVersion == nil, current != nil, let expectedVersion, !expectedVersion.isEmpty, !homey.isCloud {
            sendVersion = expectedVersion
        }
        await perform(appId, channel: channel, apiChannel: apiChannel, version: sendVersion,
                      expectedVersion: version ?? expectedVersion, on: homey, auth: auth)
    }

    /// Updates an installed app to `version` on its current channel.
    func update(_ app: InstalledApp, to version: String, on homey: HomeyRef, auth: AuthManager) async {
        await perform(app.id, channel: app.installedChannel, apiChannel: app.channel.isEmpty ? nil : app.channel,
                      version: version, expectedVersion: version, on: homey, auth: auth)
    }

    private func perform(_ appId: String, channel: InstallChannel, apiChannel: String?, version: String?,
                         expectedVersion: String?, on homey: HomeyRef, auth: AuthManager) async {
        let key = "\(homey.id)|\(appId)"
        states[key] = .working(channel)
        let gen = generation
        do {
            try await client(homey, auth: auth).install(appId: appId, channel: apiChannel, version: version)
            let ok = await waitForInstall(appId, channel: channel, version: expectedVersion, homey: homey, auth: auth)
            guard gen == generation else { return }
            states[key] = ok ? .done : .failed(L("De installatie is gestart maar nog niet klaar. Kijk over een minuut in Mijn Homey."))
        } catch {
            guard gen == generation else { return }
            if let msg = Self.friendly(error) { states[key] = .failed(msg) } else { states[key] = nil }
        }
    }

    func uninstall(_ appId: String, on homey: HomeyRef, auth: AuthManager) async {
        let key = "\(homey.id)|\(appId)"
        states[key] = .working(nil)
        do {
            try await client(homey, auth: auth).uninstall(appId: appId)
            installed[homey.id]?[appId] = nil
            states[key] = nil
        } catch {
            if let msg = Self.friendly(error) { states[key] = .failed(msg) } else { states[key] = nil }
        }
    }

    func restart(_ appId: String, on homey: HomeyRef, auth: AuthManager) async {
        let key = "\(homey.id)|\(appId)"
        states[key] = .working(nil)
        do {
            try await client(homey, auth: auth).restart(appId: appId)
            states[key] = nil
            try? await Task.sleep(for: .seconds(2))
            await refresh(homey, auth: auth, force: true)
        } catch {
            if let msg = Self.friendly(error) { states[key] = .failed(msg) } else { states[key] = nil }
        }
    }

    func setAutoUpdate(_ appId: String, _ on: Bool, on homey: HomeyRef, auth: AuthManager) async -> String? {
        do {
            try await client(homey, auth: auth).setAutoUpdate(appId: appId, on)
            await refresh(homey, auth: auth, force: true)
            return nil
        } catch {
            return Self.friendly(error)
        }
    }

    /// Polls the Homey until the app runs the expected version and channel (Homey Cloud
    /// answers before the install is finished; on Pro this is usually immediate).
    private func waitForInstall(_ appId: String, channel: InstallChannel, version: String?,
                                homey: HomeyRef, auth: AuthManager) async -> Bool {
        for attempt in 0..<20 {
            await refresh(homey, auth: auth, force: true)
            if let app = installed[homey.id]?[appId], app.installedChannel == channel,
               version == nil || version == "" || app.version == version,
               app.updateVersion == nil || app.updateVersion != version {
                return true
            }
            try? await Task.sleep(for: .seconds(attempt < 5 ? 1.5 : 3))
        }
        return false
    }

    /// Dutch message, or nil for a cancelled request.
    static func friendly(_ error: Error) -> String? {
        if let e = error as? APIError {
            switch e.status {
            case 401, 403: return L("Geen toestemming om apps te beheren op deze Homey (je hebt de rol eigenaar of beheerder nodig).")
            case 404: return L("Deze versie is niet (meer) beschikbaar in de Homey App Store.")
            default: break
            }
        }
        return ErrorText.message(error)
    }
}

extension HomeyRef {
    /// Only owners and managers may install or remove apps.
    var canInstall: Bool { role.isEmpty || ["owner", "manager"].contains(role.lowercased()) }
}
