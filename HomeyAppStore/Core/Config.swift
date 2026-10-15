import Foundation

/// Localised string (Dutch source strings; English can be added via a String Catalog later).
func L(_ value: String.LocalizationValue) -> String { String(localized: value) }

enum Config {
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
    static let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.0.1"

    static let athomAPI = URL(string: "https://api.athom.com")!
    /// Public Homey App Store catalogue (same data as homey.app/apps).
    static let appsAPI = "https://apps-api.athom.com/api/v1"
    /// Athom login runs on the Developer Tools website (same as the Homey Dev app),
    /// so the app needs no OAuth client id/secret of its own.
    static let developerToolsWeb = URL(string: "https://tools.developer.homey.app/")!
    static let accountPage = URL(string: "https://tools.developer.homey.app/me")!

    static func storePage(_ appId: String, test: Bool = false) -> URL {
        URL(string: "https://homey.app/a/\(appId)/\(test ? "test/" : "")")!
    }

    /// The language the app's UI is shown in (Dutch until a translation is added).
    /// Store content and dates follow it, so a screen never mixes languages.
    static let uiLanguage: String = {
        let lang = Bundle.main.preferredLocalizations.first ?? "nl"
        return String(lang.prefix(2))
    }()

    static var appLocale: Locale { Locale(identifier: uiLanguage == "nl" ? "nl_NL" : uiLanguage) }

    /// Language for app names/descriptions from the store.
    static var storeLanguage: String {
        let supported = ["en", "nl", "de", "fr", "it", "sv", "no", "es", "da", "ru", "pl", "ko", "ar"]
        return supported.contains(uiLanguage) ? uiLanguage : "en"
    }
}

/// Which Homey App Store you're browsing — just like the tabs on homey.app/apps.
enum StorePlatform: String, CaseIterable, Identifiable, Codable {
    /// Homey Pro, Homey Pro mini and Self-Hosted Server.
    case local
    /// Homey Cloud.
    case cloud

    var id: String { rawValue }
    var title: String { self == .local ? "Homey Pro" : "Homey Cloud" }
    var icon: String { self == .local ? "cube.fill" : "cloud.fill" }
    var subtitle: String { self == .local ? L("Pro, Pro mini & Self-Hosted Server") : L("Homey Cloud & Homey Bridge") }
}

enum StoreCategory: String, CaseIterable, Identifiable {
    case lights, security, climate, energy, music, video, appliances, tools, internet, localization
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lights: L("Verlichting")
        case .security: L("Beveiliging")
        case .climate: L("Klimaat")
        case .energy: L("Energie")
        case .music: L("Muziek")
        case .video: L("Video")
        case .appliances: L("Apparaten")
        case .tools: L("Tools")
        case .internet: L("Internet")
        case .localization: L("Lokalisatie")
        }
    }

    var symbol: String {
        switch self {
        case .lights: "lightbulb.fill"
        case .security: "lock.shield.fill"
        case .climate: "thermometer.medium"
        case .energy: "bolt.fill"
        case .music: "music.note"
        case .video: "tv.fill"
        case .appliances: "washer.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .internet: "globe"
        case .localization: "location.fill"
        }
    }

    var tint: String {
        switch self {
        case .lights: "#F7B500"
        case .security: "#E5484D"
        case .climate: "#12A594"
        case .energy: "#30A46C"
        case .music: "#E93D82"
        case .video: "#8E4EC6"
        case .appliances: "#3E63DD"
        case .tools: "#6E6E73"
        case .internet: "#0091FF"
        case .localization: "#F76808"
        }
    }
}
