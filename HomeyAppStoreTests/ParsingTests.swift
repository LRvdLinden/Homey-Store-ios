import XCTest
@testable import HomeyAppStore

/// Parsing of Homey App Store and Homey Web API data, and the logic built on it.
final class ParsingTests: XCTestCase {

    private func json(_ s: String) -> JSON { JSON.parse(Data(s.utf8)) }

    // MARK: Store

    func testBrowseItem() {
        let app = StoreApp(json("""
        {"id":"nl.philips.hue","name":"Philips Hue","description":"Licht","icon":"https://x/icon.svg",
         "image":"https://x/assets/images/large.png","brandColor":"#F4AF2E","platforms":["local","cloud"],
         "authorName":"Athom B.V.","authorVerified":true}
        """))
        XCTAssertEqual(app?.name, "Philips Hue")
        XCTAssertEqual(app?.platforms, ["local", "cloud"])
        XCTAssertEqual(app?.smallImageURL?.absoluteString, "https://x/assets/images/small.png")
        XCTAssertTrue(app?.authorVerified ?? false)
    }

    func testFullAppObjectFallsBackToTestBuild() {
        let app = StoreApp(json("""
        {"id":"com.example.new","liveBuild":null,
         "testBuild":{"id":3,"name":{"en":"New app"},"description":{"en":"Only in test"},"icon":"https://x/i.svg","brandColor":"#123456"}}
        """))
        XCTAssertEqual(app?.name, "New app")
        XCTAssertEqual(app?.brandColor, "#123456")
    }

    func testDetailLiveAndTest() {
        let d = StoreAppDetail(json("""
        {"id":"a.b","rating":4.5,"liveVersion":"1.0.0","testVersion":"1.1.0",
         "liveBuild":{"id":1,"version":"1.0.0","name":{"en":"A"},"platforms":["local"],"drivers":[{"id":"bulb","name":{"en":"Lamp"},"connectivity":["zigbee"]}],
                      "widgets":{"w1":{"name":{"en":"Clock"}}}},
         "testBuild":{"id":2,"version":"1.1.0","name":{"en":"A"}},
         "author":{"id":"649eefe59a54fe7531821578","name":"Dev"}}
        """))
        XCTAssertNotNil(d)
        XCTAssertTrue(d!.hasLive)
        XCTAssertTrue(d!.hasTest)
        XCTAssertEqual(d!.authorId, "649eefe59a54fe7531821578")
        XCTAssertTrue(d!.supports(.local))
        XCTAssertFalse(d!.supports(.cloud))
        XCTAssertEqual(d!.liveBuild?.drivers.first?.connectivity, ["zigbee"])
        XCTAssertEqual(d!.liveBuild?.widgets, ["Clock"])
    }

    func testTestEqualToLiveIsNotOffered() {
        let d = StoreAppDetail(json("""
        {"id":"a.b","liveVersion":"1.0.0","testVersion":"1.0.0",
         "liveBuild":{"id":1,"version":"1.0.0"},"testBuild":{"id":1,"version":"1.0.0"}}
        """))
        XCTAssertFalse(d!.hasTest)
    }

    func testChangelogSortedNewestFirst() {
        let entries = ChangelogEntry.parse(json("""
        {"1.2.0":{"state":"live","changelog":{"en":"b"}},"1.10.0":{"state":"test","changelog":{"en":"c"}},"1.1.0":{"state":"superseded","changelog":null}}
        """))
        XCTAssertEqual(entries.map(\.version), ["1.10.0", "1.2.0", "1.1.0"])
        XCTAssertEqual(entries.first { $0.state == "live" }?.version, "1.2.0")
    }

    func testReviewsAndSummary() {
        let reviews = json("""
        [{"userId":"1","userName":"Kim","rating":1,"version":"5.5.8","comment":"Kapot","response":"Opgelost?","updatedAt":"2022-04-20T16:25:37.598Z"},
         {"userId":"2","userName":"Dennie","rating":5,"version":"5.5.8","comment":null,"response":null}]
        """).array.compactMap(StoreReview.init)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0].response, "Opgelost?")
        XCTAssertEqual(reviews[1].comment, "")
        let s = ReviewSummary(reviews)
        XCTAssertEqual(s.average, 3, accuracy: 0.001)
        XCTAssertEqual(s.distribution[0], 0.5, accuracy: 0.001)   // 5 stars
        XCTAssertEqual(s.distribution[4], 0.5, accuracy: 0.001)   // 1 star
    }

    // MARK: Homey

    func testInstalledAppFields() {
        let app = InstalledApp(json("""
        {"id":"nl.lrvdlinden.birthdays","name":{"en":"Birthdays"},"version":"2.1.5","origin":"appstore","channel":"beta",
         "enabled":true,"autoupdate":true,"color":"#ef35aa","state":"crashed","crashedMessage":"boom",
         "updateAvailable":{"version":"2.2.0","permissions":["homey:manager:speech-output"]}}
        """))!
        XCTAssertTrue(app.isTest)           // "beta" counts as test, like my.homey.app
        XCTAssertTrue(app.isFromStore)
        XCTAssertFalse(app.isDevkit)
        XCTAssertEqual(app.brandColor, "#ef35aa")
        XCTAssertTrue(app.crashed)
        XCTAssertEqual(app.updateVersion, "2.2.0")
        XCTAssertEqual(app.updatePermissions, ["homey:manager:speech-output"])
        XCTAssertEqual(app.iconPath, "/app/nl.lrvdlinden.birthdays/assets/icon.svg")
    }

    func testDevkitInstall() {
        let app = InstalledApp(json(#"{"id":"x.y","version":"0.1.0","origin":"devkit_install","channel":"live"}"#))!
        XCTAssertTrue(app.isDevkit)
        XCTAssertFalse(app.isTest)
    }

    func testHomeyModelNames() {
        XCTAssertEqual(HomeyRef.modelName(code: "homey5q", platform: "local"), "Homey Pro (Early 2023)")
        XCTAssertEqual(HomeyRef.modelName(code: "homey6q", platform: "local"), "Homey Pro mini")
        XCTAssertEqual(HomeyRef.modelName(code: "shs", platform: "local"), "Homey Self-Hosted Server")
        XCTAssertEqual(HomeyRef.modelName(code: "", platform: "cloud"), "Homey Cloud")
        let h = HomeyRef(json(#"{"id":"abc","name":"Thuis","platform":"local","model":"homey5q","role":"user","modelImage":{"light":"https://x/l.png","dark":"https://x/d.png"}}"#))!
        XCTAssertFalse(h.canInstall)
        XCTAssertEqual(h.imageDark?.absoluteString, "https://x/d.png")
    }

    @MainActor
    func testUpdateVersionLogic() {
        let library = HomeyLibrary()
        let detail = StoreAppDetail(json("""
        {"id":"a.b","liveVersion":"1.2.0","testVersion":"1.3.0","liveBuild":{"id":1,"version":"1.2.0"},"testBuild":{"id":2,"version":"1.3.0"}}
        """))
        let live = InstalledApp(json(#"{"id":"a.b","version":"1.1.0","origin":"appstore","channel":"live"}"#))!
        let test = InstalledApp(json(#"{"id":"a.b","version":"1.3.0","origin":"appstore","channel":"test"}"#))!
        let dev = InstalledApp(json(#"{"id":"a.b","version":"0.1.0","origin":"devkit_run"}"#))!
        XCTAssertEqual(library.updateVersion(for: live, detail: detail), "1.2.0")
        XCTAssertNil(library.updateVersion(for: test, detail: detail))      // already on newest test
        XCTAssertNil(library.updateVersion(for: dev, detail: detail))       // CLI installs never "update"
    }

    // MARK: Links

    @MainActor
    func testLinks() {
        XCTAssertEqual(Router.appID(in: URL(string: "homeystore://app/nl.philips.hue")!), "nl.philips.hue")
        XCTAssertEqual(Router.appID(in: URL(string: "https://homey.app/a/com.sonos/test")!), "com.sonos")
        XCTAssertEqual(Router.appID(in: URL(string: "https://homey.app/nl-nl/app/nl.philips.hue/Philips-Hue/")!), "nl.philips.hue")
        XCTAssertEqual(Router.appID(inText: "nl.lrvdlinden.birthdays"), "nl.lrvdlinden.birthdays")
        XCTAssertNil(Router.appID(inText: "philips hue"))
        XCTAssertNil(Router.appID(in: URL(string: "https://example.com/a/x.y")!))
    }
}
