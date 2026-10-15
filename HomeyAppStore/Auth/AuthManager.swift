import Foundation
import Observation

enum Credential: Codable, Equatable, Sendable {
    /// Logged in with email + password on the Developer Tools website.
    case web(WebSession)
    /// Personal Access Token (My Account → Personal Access Tokens).
    case pat(String)

    var accessToken: String {
        switch self {
        case .web(let s): return s.accessToken
        case .pat(let p): return p
        }
    }
}

/// One saved Athom/Homey account (like the account switcher in the Facebook app).
struct StoredAccount: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var email: String
    var avatar: String
    var credential: Credential
    var lastUsed: Date
    var needsLogin: Bool = false

    init(id: String, name: String, email: String, avatar: String, credential: Credential, lastUsed: Date, needsLogin: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.avatar = avatar
        self.credential = credential
        self.lastUsed = lastUsed
        self.needsLogin = needsLogin
    }

    /// Tolerant decoding: fields added later (like `needsLogin`) may be missing in
    /// accounts saved by an older build — they must not make all accounts disappear.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        credential = try c.decode(Credential.self, forKey: .credential)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? .distantPast
        needsLogin = try c.decodeIfPresent(Bool.self, forKey: .needsLogin) ?? false
    }

    var avatarURL: URL? { URL(string: avatar) }
    var methodLabel: String {
        switch credential { case .web: return L("Homey-account"); case .pat: return "Personal Access Token" }
    }
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? String(email.prefix(1)).uppercased() : s.uppercased()
    }
}

/// Owns all saved accounts, the active one, token refresh and delegation tokens
/// for the Apps API (`audience=apps`) and Homey (`audience=homey`).
@MainActor
@Observable
final class AuthManager {
    /// Bumped whenever the active account changes, so screens can reload.
    private(set) var generation = 0

    private(set) var accounts: [StoredAccount] = []
    private(set) var activeID: String?
    private(set) var user: JSON = .null
    private(set) var userError: String?

    @ObservationIgnored private var delegated: [String: (token: String, expires: Date?)] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Error>?
    /// One running delegation-token request per audience, shared by all callers.
    @ObservationIgnored private var delegationTasks: [String: Task<String, Error>] = [:]
    /// When the last web-session refresh failed; we don't retry for a while.
    @ObservationIgnored private var refreshFailedAt: Date?

    private enum Keys {
        static let accounts = "store.accounts.v1"
        static let active = "store.activeAccountID"
    }

    init() {
        accounts = Keychain.load([StoredAccount].self, for: Keys.accounts) ?? []
        activeID = UserDefaults.standard.string(forKey: Keys.active)
        if active == nil { activeID = accounts.sorted { $0.lastUsed > $1.lastUsed }.first?.id }
    }

    var active: StoredAccount? { accounts.first { $0.id == activeID } }
    var isLoggedIn: Bool { active != nil }
    var otherAccounts: [StoredAccount] { accounts.filter { $0.id != activeID }.sorted { $0.lastUsed > $1.lastUsed } }
    /// Whether the account's token is usable for optional extras (the private part of
    /// the store catalogue). False while the session is known to be expired.
    var hasUsableSession: Bool { active != nil && active?.needsLogin != true }

    // MARK: Adding accounts

    /// A verified account that is not yet saved. Login screens first verify,
    /// then close themselves, and only then `commit` — so the view tree under
    /// a sheet is never swapped while that sheet is still on screen (this
    /// crashed the Mac app on sign-in).
    struct PendingAccount: Sendable {
        let account: StoredAccount
        let me: JSON
    }

    func verifyWebAccount(_ session: WebSession) async throws -> PendingAccount {
        try await verify(credential: .web(session))
    }

    func verifyPATAccount(_ raw: String) async throws -> PendingAccount {
        let pat = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pat.isEmpty else { throw APIError(status: 0, message: L("Vul een Personal Access Token in."), url: "") }
        return try await verify(credential: .pat(pat))
    }

    /// Saves a verified account and makes it the active one.
    func commit(_ pending: PendingAccount) {
        let account = pending.account
        if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i] = account } else { accounts.append(account) }
        activate(account.id)
        user = pending.me
        userError = nil
        save()
    }

    /// Runs `dismissAll` (closes sheets), waits for the dismiss animation,
    /// then saves and activates the account.
    func commitAfterDismiss(_ pending: PendingAccount, _ dismissAll: () -> Void) async {
        dismissAll()
        try? await Task.sleep(for: .milliseconds(650))
        commit(pending)
    }

    private func verify(credential: Credential) async throws -> PendingAccount {
        let me = try await HTTP.send(
            Config.athomAPI.appendingPathComponent("user/me"),
            headers: ["Authorization": "Bearer \(credential.accessToken)"]
        ).json
        let id = me.firstString("_id", "id").isEmpty ? me.firstString("email") : me.firstString("_id", "id")
        guard !id.isEmpty else { throw APIError(status: 0, message: L("Kon het account niet herkennen."), url: "user/me") }
        let account = StoredAccount(
            id: id,
            name: Self.displayName(me),
            email: me.firstString("email"),
            avatar: Self.avatar(me),
            credential: credential,
            lastUsed: Date()
        )
        return PendingAccount(account: account, me: me)
    }

    // MARK: Switching / signing out

    func switchTo(_ id: String) {
        guard id != activeID, accounts.contains(where: { $0.id == id }) else { return }
        activate(id)
        user = .null
        save()
        Task { try? await loadUser() }
    }

    private func activate(_ id: String) {
        activeID = id
        generation += 1
        delegated.removeAll()
        delegationTasks.values.forEach { $0.cancel() }
        delegationTasks.removeAll()
        refreshTask = nil
        refreshFailedAt = nil
        if let i = accounts.firstIndex(where: { $0.id == id }) { accounts[i].lastUsed = Date() }
        UserDefaults.standard.set(id, forKey: Keys.active)
    }

    /// Removes the account from this device ("Afmelden").
    func signOut(_ id: String) {
        accounts.removeAll { $0.id == id }
        if activeID == id {
            user = .null
            delegated.removeAll()
            delegationTasks.removeAll()
            activeID = nil
            generation += 1
            if let next = accounts.sorted(by: { $0.lastUsed > $1.lastUsed }).first { activate(next.id); Task { try? await loadUser() } }
            else { UserDefaults.standard.removeObject(forKey: Keys.active) }
        }
        save()
    }

    func logout() { if let activeID { signOut(activeID) } }

    private func save() { Keychain.save(accounts, for: Keys.accounts) }

    private func updateActive(_ change: (inout StoredAccount) -> Void) {
        guard let i = accounts.firstIndex(where: { $0.id == activeID }) else { return }
        change(&accounts[i])
        save()
    }

    // MARK: Tokens

    func accessToken() throws -> String {
        guard let active else { throw APIError(status: 401, message: L("Niet ingelogd."), url: "") }
        return active.credential.accessToken
    }

    private func refreshActive() async throws {
        if let refreshTask { return try await refreshTask.value }
        if let failed = refreshFailedAt, Date().timeIntervalSince(failed) < 300 {
            throw APIError(status: 401, message: L("Je sessie is verlopen. Log opnieuw in."), url: "")
        }
        guard case .web(let session) = active?.credential else {
            throw APIError(status: 401, message: L("Token ongeldig of ingetrokken. Voeg het account opnieuw toe."), url: "")
        }
        let id = activeID
        let task = Task { () throws -> Void in
            do {
                let new = try await WebSessionBridge.refresh(session)
                guard self.activeID == id else { return }
                self.updateActive { $0.credential = .web(new); $0.needsLogin = false }
                self.delegated.removeAll()
                self.refreshFailedAt = nil
            } catch {
                if self.activeID == id {
                    self.updateActive { $0.needsLogin = true }
                    self.refreshFailedAt = Date()
                }
                throw error
            }
        }
        refreshTask = task
        // Only clear our own task: an account switch may already have started a new one.
        defer { if self.refreshTask == task { self.refreshTask = nil } }
        try await task.value
    }

    /// Request against api.athom.com with the account token; refreshes once on 401.
    func athom(_ path: String, method: String = "GET", json body: JSON? = nil) async throws -> JSON {
        guard let url = URL(string: path, relativeTo: Config.athomAPI)?.absoluteURL else {
            throw APIError(status: 0, message: L("Ongeldig pad"), url: path)
        }
        func run() async throws -> JSON {
            let token = try accessToken()
            let data = body.map { $0.data() } ?? (method == "POST" ? Data("{}".utf8) : nil)
            return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(token)"], body: data).json
        }
        do { return try await run() } catch let e as APIError where e.isUnauthorized {
            try await refreshActive()
            return try await run()
        }
    }

    func loadUser() async throws {
        do {
            let me = try await athom("/user/me")
            user = me
            userError = nil
            updateActive {
                $0.name = Self.displayName(me)
                $0.email = me.firstString("email")
                $0.avatar = Self.avatar(me)
            }
        } catch {
            userError = ErrorText.message(error)
            throw error
        }
    }

    func delegationToken(audience: String) async throws -> String {
        if let cached = delegated[audience], (cached.expires ?? .distantFuture) > Date() { return cached.token }
        if let running = delegationTasks[audience] { return try await running.value }
        let gen = generation
        let task = Task { @MainActor () throws -> String in try await self.fetchDelegationToken(audience: audience) }
        delegationTasks[audience] = task
        defer { if self.delegationTasks[audience] == task { self.delegationTasks[audience] = nil } }
        let token = try await task.value
        guard gen == generation else { throw CancellationError() }   // account changed meanwhile
        delegated[audience] = (token, JWT.expiry(token))
        return token
    }

    private func fetchDelegationToken(audience: String) async throws -> String {
        let resp = try await athom("/delegation/token?audience=\(audience)", method: "POST", json: .object([:]))
        let token: String
        switch resp {
        case .string(let s): token = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        default: token = resp.firstString("token", "access_token")
        }
        guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen delegation token ontvangen (\(audience))."), url: "delegation/token") }
        return token
    }

    func invalidateDelegation(_ audience: String) { delegated[audience] = nil }

    // MARK: User helpers

    private static func displayName(_ me: JSON) -> String {
        let full = "\(me["firstname"].string ?? "") \(me["lastname"].string ?? "")".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? me.firstString("fullname", "name", "email") : full
    }

    private static func avatar(_ me: JSON) -> String {
        let a = me["avatar"]
        return a.isContainer ? a.firstString("large", "medium", "small", "url") : (a.string ?? "")
    }

    var displayName: String { user.isNull ? (active?.name ?? "") : Self.displayName(user) }
    var email: String { user.isNull ? (active?.email ?? "") : user.firstString("email") }
    var avatarURL: URL? { URL(string: user.isNull ? (active?.avatar ?? "") : Self.avatar(user)) }

    /// Homeys linked to the account (same source as Developer Tools: `user.homeys`).
    var homeys: [HomeyRef] {
        var seen = Set<String>()
        return user["homeys"].items.compactMap(HomeyRef.init)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
