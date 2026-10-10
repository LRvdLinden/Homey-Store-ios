import Foundation

/// An app as it appears in lists (`/app/browse`, `/app/highlight2`).
struct StoreApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let iconURL: URL?
    let imageURL: URL?
    let brandColor: String
    let authorName: String
    let authorVerified: Bool
    let platforms: [String]

    /// Small version of the app photo (`…/images/small.*`), lighter for icon fallbacks.
    var smallImageURL: URL? {
        guard let imageURL else { return nil }
        let s = imageURL.absoluteString
        guard s.contains("/images/large.") else { return imageURL }
        return URL(string: s.replacingOccurrences(of: "/images/large.", with: "/images/small.")) ?? imageURL
    }

    init?(_ j: JSON) {
        guard let id = j["id"].string, !id.isEmpty else { return nil }
        self.id = id
        let live = j["liveBuild"]
        let name = j["name"].localized.isEmpty ? live["name"].localized : j["name"].localized
        self.name = name.isEmpty ? id : name
        description = j["description"].localized.isEmpty ? live["description"].localized : j["description"].localized
        iconURL = URL(string: j.firstString("icon").isEmpty ? live.firstString("icon") : j.firstString("icon"))
        imageURL = URL(string: j.firstString("image", "imageLarge").isEmpty ? live.firstString("imageLarge", "imageSmall") : j.firstString("image", "imageLarge"))
        brandColor = j.firstString("brandColor").isEmpty ? live.firstString("brandColor") : j.firstString("brandColor")
        authorName = j.firstString("authorName").isEmpty ? j["author"].firstString("name") : j.firstString("authorName")
        authorVerified = j["authorVerified"].bool ?? false
        platforms = (j["platforms"].array.isEmpty ? live["platforms"].array : j["platforms"].array).compactMap(\.string)
    }

    init(detail: StoreAppDetail) {
        id = detail.id
        name = detail.name
        description = detail.subtitle
        iconURL = detail.primaryBuild?.iconURL
        imageURL = detail.primaryBuild?.imageLargeURL
        brandColor = detail.primaryBuild?.brandColor ?? ""
        authorName = detail.authorName
        authorVerified = false
        platforms = detail.primaryBuild?.platforms ?? []
    }
}

/// One build of an app (`liveBuild` / `testBuild` on `/app/{id}`).
struct StoreBuild: Hashable, Sendable {
    let id: Int
    let name: String
    let version: String
    let readme: String
    let description: String
    let category: String
    let brandColor: String
    let iconURL: URL?
    let imageSmallURL: URL?
    let imageLargeURL: URL?
    let platforms: [String]
    let compatibility: String
    let sdk: Int
    let permissions: [String]
    let changelog: String
    let tags: [String]
    let driverNames: [String]
    let connectivity: [String]
    let triggerCount: Int
    let conditionCount: Int
    let actionCount: Int
    let widgetCount: Int
    let support: URL?
    let homepage: URL?
    let source: URL?
    let bugs: URL?
    let donate: URL?
    let stateChangedAt: Date?
    let developers: [String]
    let translators: [String]

    init?(_ j: JSON) {
        guard case .object = j, let id = j["id"].int else { return nil }
        self.id = id
        name = j["name"].localized
        version = j.firstString("version")
        readme = j["readme"].localized
        description = j["description"].localized
        category = j["category"].string ?? j["category"].array.first?.string ?? ""
        brandColor = j.firstString("brandColor")
        iconURL = URL(string: j.firstString("icon"))
        imageSmallURL = URL(string: j.firstString("imageSmall"))
        imageLargeURL = URL(string: j.firstString("imageLarge", "imageSmall"))
        platforms = j["platforms"].array.compactMap(\.string)
        compatibility = j.firstString("compatibility")
        sdk = j["sdk"].int ?? 0
        permissions = j["permissions"].array.compactMap(\.string)
        changelog = j["changelog"].localized
        tags = j["tags"].isContainer ? (j["tags"][Config.storeLanguage].array.isEmpty ? j["tags"]["en"].array : j["tags"][Config.storeLanguage].array).compactMap(\.string) : []
        let drivers = j["drivers"].array
        driverNames = drivers.map { $0["name"].localized.isEmpty ? $0.firstString("id") : $0["name"].localized }
        var conn = Set<String>()
        drivers.forEach { $0["connectivity"].array.compactMap(\.string).forEach { conn.insert($0) } }
        connectivity = conn.sorted()
        let flow = j["flow"]
        triggerCount = flow["triggers"].array.count
        conditionCount = max(flow["conditions"].array.count, j["conditions"].array.count)
        actionCount = max(flow["actions"].array.count, j["actions"].array.count)
        widgetCount = j["widgets"].object.count
        support = URL(string: j.firstString("support"))
        homepage = URL(string: j.firstString("homepage"))
        source = URL(string: j.firstString("source"))
        bugs = URL(string: j["bugs"].string ?? j["bugs"].firstString("url"))
        let donate = j["contributing"]["donate"]
        if let paypal = donate["paypal"]["username"].string, !paypal.isEmpty {
            self.donate = URL(string: "https://paypal.me/\(paypal)")
        } else if let bmc = donate["bunq"]["username"].string, !bmc.isEmpty {
            self.donate = URL(string: "https://bunq.me/\(bmc)")
        } else {
            self.donate = nil
        }
        stateChangedAt = j["stateChangedAt"].date
        developers = j["contributors"]["developers"].array.compactMap { $0["name"].string ?? $0.string }
        translators = j["contributors"]["translators"].array.compactMap { $0["name"].string ?? $0.string }
    }

    var flowCardCount: Int { triggerCount + conditionCount + actionCount }
}

/// Full app as returned by `/app/{id}`.
struct StoreAppDetail: Identifiable, Hashable, Sendable {
    let id: String
    let rating: Double?
    let liveVersion: String
    let testVersion: String
    let liveBuild: StoreBuild?
    let testBuild: StoreBuild?
    let authorName: String
    let authorId: String
    let isPrivate: Bool

    init?(_ j: JSON) {
        guard let id = j["id"].string, !id.isEmpty else { return nil }
        self.id = id
        rating = j["rating"].double
        liveBuild = StoreBuild(j["liveBuild"])
        testBuild = StoreBuild(j["testBuild"])
        liveVersion = j.firstString("liveVersion").isEmpty ? (liveBuild?.version ?? "") : j.firstString("liveVersion")
        testVersion = j.firstString("testVersion").isEmpty ? (testBuild?.version ?? "") : j.firstString("testVersion")
        authorName = j["author"].firstString("name", "fullname")
        authorId = j["author"].firstString("id", "_id")
        isPrivate = j["private"].bool ?? false
    }

    /// The live build, or the test build for apps that are only in test.
    var primaryBuild: StoreBuild? { liveBuild ?? testBuild }
    var hasLive: Bool { liveBuild != nil }
    /// A test version worth offering: exists and differs from live.
    var hasTest: Bool { testBuild != nil && (testVersion != liveVersion || liveBuild == nil) }
    var name: String { primaryBuild?.name.isEmpty == false ? primaryBuild!.name : id }
    var subtitle: String { primaryBuild?.description ?? "" }
    var category: StoreCategory? { StoreCategory(rawValue: primaryBuild?.category ?? "") }

    func supports(_ platform: StorePlatform) -> Bool {
        let p = primaryBuild?.platforms ?? []
        return p.isEmpty ? platform == .local : p.contains(platform.rawValue)
    }
}

struct ChangelogEntry: Identifiable, Hashable, Sendable {
    let version: String
    let state: String
    let text: String
    let date: Date?
    var id: String { version }

    static func parse(_ j: JSON) -> [ChangelogEntry] {
        j.object.map { version, v in
            ChangelogEntry(version: version, state: v.firstString("state"), text: v["changelog"].localized, date: v["createdAt"].date)
        }
        .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}

/// The store home page (`/app/highlight2`).
struct StoreHighlights: Sendable {
    var popular: [StoreApp] = []
    var recentlyCreated: [StoreApp] = []
    var recentlyUpdated: [StoreApp] = []
    var byCategory: [CategoryApps] = []

    init() {}

    init(_ j: JSON) {
        popular = j["popular"].array.compactMap(StoreApp.init)
        recentlyCreated = j["recentlyCreated"].array.compactMap(StoreApp.init)
        recentlyUpdated = j["recentlyUpdated"].array.compactMap(StoreApp.init)
        byCategory = StoreCategory.allCases.compactMap { c in
            let apps = j["byCategory"][c.rawValue].array.compactMap(StoreApp.init)
            return apps.isEmpty ? nil : CategoryApps(category: c, apps: apps)
        }
    }

    var isEmpty: Bool { popular.isEmpty && recentlyCreated.isEmpty && recentlyUpdated.isEmpty && byCategory.isEmpty }
}

struct CategoryApps: Identifiable, Sendable {
    let category: StoreCategory
    let apps: [StoreApp]
    var id: StoreCategory { category }
}

struct BrowsePage: Sendable {
    let items: [StoreApp]
    let total: Int
}
