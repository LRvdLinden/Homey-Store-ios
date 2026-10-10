import Foundation
import Observation

/// Keeps track of the account's Homeys, which one you install to per store
/// (Pro / Cloud), which apps are installed on them, and running installs.
@MainActor
@Observable
final class HomeyLibrary {
    enum InstallState: Equatable {
        case idle
        case working(InstallChannel?)   // nil = removing
        case done
        case failed(String)
    }

    private(set) var installed: [String: [String: InstalledApp]] = [:]   // homeyID → appID → app
    private(set) var loadingHomeys: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var states: [String: InstallState] = [:]                // "homey|app"

    @ObservationIgnored private var clients: [String: HomeyClient] = [:]
    @ObservationIgnored private var generation = -1

    // MARK: Target Homey per store

    private func targetKey(_ platform: StorePlatform, _ accountID: String?) -> String {
        "store.target.\(accountID ?? "-").\(platform.rawValue)"
    }

    func homeys(for platform: StorePlatform, auth: AuthManager) -> [HomeyRef] {
        auth.homeys.filter { platform == .cloud ? $0.isCloud : !$0.isCloud }
    }

    func target(for platform: StorePlatform, auth: AuthManager) -> HomeyRef? {
        let all = homeys(for: platform, auth: auth)
        let saved = UserDefaults.standard.string(forKey: targetKey(platform, auth.activeID))
        return all.first { $0.id == saved } ?? all.first
    }

    func setTarget(_ homey: HomeyRef, platform: StorePlatform, auth: AuthManager) {
        UserDefaults.standard.set(homey.id, forKey: targetKey(platform, auth.activeID))
        Task { await refresh(homey, auth: auth) }
    }

    // MARK: Installed apps

    private func client(_ homey: HomeyRef, auth: AuthManager) -> HomeyClient {
        if generation != auth.generation {
            clients.removeAll(); installed.removeAll(); errors.removeAll(); states.removeAll()
            generation = auth.generation
        }
        if let c = clients[homey.id] { return c }
        let c = HomeyClient(homey: homey, auth: auth)
        clients[homey.id] = c
        return c
    }

    func refresh(_ homey: HomeyRef, auth: AuthManager, force: Bool = false) async {
        let c = client(homey, auth: auth)
        if !force, installed[homey.id] != nil { return }
        guard !loadingHomeys.contains(homey.id) else { return }
        loadingHomeys.insert(homey.id)
        defer { loadingHomeys.remove(homey.id) }
        do {
            let apps = try await c.installedApps()
            installed[homey.id] = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            errors[homey.id] = nil
        } catch {
            errors[homey.id] = error.localizedDescription
        }
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

    func clearState(_ appId: String, on homey: HomeyRef) {
        states["\(homey.id)|\(appId)"] = nil
    }

    // MARK: Actions

    func install(_ appId: String, channel: InstallChannel, on homey: HomeyRef, auth: AuthManager) async {
        let key = "\(homey.id)|\(appId)"
        states[key] = .working(channel)
        do {
            try await client(homey, auth: auth).install(appId: appId, channel: channel)
            await pollUntilInstalled(appId, channel: channel, homey: homey, auth: auth)
            states[key] = .done
        } catch {
            states[key] = .failed(Self.friendly(error))
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
            states[key] = .failed(Self.friendly(error))
        }
    }

    /// Homey Cloud returns before the app is ready; poll briefly so the button flips to "Open".
    private func pollUntilInstalled(_ appId: String, channel: InstallChannel, homey: HomeyRef, auth: AuthManager) async {
        for attempt in 0..<12 {
            await refresh(homey, auth: auth, force: true)
            if installed[homey.id]?[appId] != nil { return }
            try? await Task.sleep(for: .seconds(attempt < 4 ? 1.5 : 3))
        }
    }

    private static func friendly(_ error: Error) -> String {
        if let e = error as? APIError {
            switch e.status {
            case 401, 403: return L("Geen toestemming om apps te installeren op deze Homey (je hebt de rol eigenaar of beheerder nodig).")
            case 404: return L("Deze versie is niet (meer) beschikbaar in de Homey App Store.")
            default: break
            }
        }
        return error.localizedDescription
    }
}
