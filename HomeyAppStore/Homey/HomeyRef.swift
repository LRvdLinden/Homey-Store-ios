import Foundation

struct HomeyRef: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let platform: String
    let model: String
    let softwareVersion: String
    let remoteURL: URL
    let localURL: URL?
    let role: String
    let apiVersion: Int
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].string ?? j["_id"].string else { return nil }
        self.id = id
        name = j.firstString("name").isEmpty ? "Homey" : j.firstString("name")
        platform = j.firstString("platform", "platformVersion")
        model = j.firstString("modelName", "model")
        softwareVersion = j.firstString("softwareVersion", "version")
        remoteURL = URL(string: j.firstString("remoteUrl", "remoteUrlForwarded")) ?? URL(string: "https://\(id).connect.athom.com") ?? Config.athomAPI
        localURL = URL(string: j.firstString("localUrlSecure", "localUrl"))
        role = j.firstString("role")
        apiVersion = j["apiVersion"].int ?? 0
        raw = j
    }

    var isCloud: Bool { platform == "cloud" }
    var subtitle: String {
        let kind = isCloud ? "Homey Cloud" : (model.isEmpty ? "Homey Pro" : model)
        return [kind, softwareVersion.isEmpty ? "" : "v\(softwareVersion)", role].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
