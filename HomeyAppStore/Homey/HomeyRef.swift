import Foundation

/// A Homey linked to the account (from `GET api.athom.com/user/me` → `homeys`).
struct HomeyRef: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let platform: String
    /// Model code, e.g. `homey5q` (Pro Early 2023), `homey6q` (Pro mini), `shs`.
    let modelCode: String
    /// Display model, e.g. "Homey Pro (Early 2023)".
    let model: String
    let softwareVersion: String
    let remoteURL: URL
    let localURL: URL?
    let role: String
    let apiVersion: Int
    /// Product images, the same ones my.homey.app shows (`modelImage.light/dark`).
    let imageLight: URL?
    let imageDark: URL?
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].string ?? j["_id"].string else { return nil }
        self.id = id
        name = j.firstString("name").isEmpty ? "Homey" : j.firstString("name")
        platform = j.firstString("platform")
        modelCode = j.firstString("model")
        let named = j.firstString("modelName")
        model = named.isEmpty ? Self.modelName(code: modelCode, platform: platform) : named
        softwareVersion = j.firstString("softwareVersion", "version")
        remoteURL = URL(string: j.firstString("remoteUrl", "remoteUrlForwarded")) ?? URL(string: "https://\(id).connect.athom.com") ?? Config.athomAPI
        localURL = URL(string: j.firstString("localUrlSecure", "localUrl"))
        role = j.firstString("role")
        apiVersion = j["apiVersion"].int ?? 0
        let img = j["modelImage"]
        if img.isContainer {
            imageLight = URL(string: img.firstString("light", "default", "url"))
            imageDark = URL(string: img.firstString("dark", "light", "default", "url"))
        } else {
            imageLight = URL(string: img.string ?? "")
            imageDark = imageLight
        }
        raw = j
    }

    var isCloud: Bool { platform == "cloud" }
    var isSelfHosted: Bool { modelCode == "shs" }

    /// Same mapping as my.homey.app when the API gives no model name.
    static func modelName(code: String, platform: String) -> String {
        if platform == "cloud" { return "Homey Cloud" }
        switch code {
        case "homey5q": return "Homey Pro (Early 2023)"
        case "homey7q": return "Homey Pro"
        case "homey6q": return "Homey Pro mini"
        case "shs": return "Homey Self-Hosted Server"
        case "homey3s", "homey3d", "homey4d": return "Homey Pro (Early 2019)"
        default: return "Homey Pro"
        }
    }

    /// Line under the name, like my.homey.app: just the model.
    var subtitle: String { model }

    /// Longer line for detail screens.
    var details: String {
        [model, softwareVersion.isEmpty ? "" : "v\(softwareVersion)", role].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// SF Symbol used while the product image loads or when there is none.
    var fallbackSymbol: String {
        if isCloud { return "house.fill" }
        if isSelfHosted { return "server.rack" }
        return "circle.circle.fill"
    }
}
