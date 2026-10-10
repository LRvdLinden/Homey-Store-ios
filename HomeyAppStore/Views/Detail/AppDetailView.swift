import SwiftUI
import UIKit

/// App page in App Store style: header with Get button, info strip, What's New,
/// preview, description, test version, compatibility and information.
struct AppDetailView: View {
    let app: StoreApp

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(\.openURL) private var openURL

    @State private var detail: StoreAppDetail?
    @State private var changelog: [ChangelogEntry] = []
    @State private var error: String?
    @State private var expandReadme = false
    @State private var installChannel: InstallChannel?
    @State private var showLogin = false

    private var build: StoreBuild? { detail?.primaryBuild }
    private var target: HomeyRef? { library.target(for: store.platform, auth: auth) }
    private var installed: InstalledApp? { library.installedApp(app.id, on: target) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if let detail, detail.hasTest {
                    testBanner(detail).padding(.horizontal, 20).padding(.top, 16)
                }

                infoStrip.padding(.top, 18)

                if let error, detail == nil {
                    ErrorBanner(message: error) { Task { await load() } }.padding(20)
                }

                if let latest = changelog.first ?? build.map({ ChangelogEntry(version: $0.version, state: "live", text: $0.changelog, date: $0.stateChangedAt) }) {
                    whatsNew(latest)
                }

                preview

                if let build, !(build.readme.isEmpty && build.description.isEmpty) {
                    section(nil) {
                        Text(build.readme.isEmpty ? build.description : build.readme)
                            .font(.body)
                            .lineLimit(expandReadme ? nil : 4)
                        if !expandReadme && build.readme.count > 180 {
                            Button(L("meer")) { withAnimation { expandReadme = true } }.font(.body)
                        }
                    }
                }

                if let detail, detail.hasTest, let test = detail.testBuild {
                    testSection(detail, test)
                }

                if let build { worksWith(build) }

                if let build, let detail { information(detail, build) }

                Text("Homey Store \(Config.appVersion) · \(L("Gegevens uit de Homey App Store"))")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StoreAppIcon(url: app.iconURL ?? build?.iconURL, brandColor: brandColor, name: app.name, size: 28, fallbackURL: build?.imageSmallURL ?? app.smallImageURL)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: Config.storePage(app.id)) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task(id: app.id) { await load() }
        .refreshable { await load(force: true) }
        .sheet(item: $installChannel) { channel in
            InstallSheet(appId: app.id, preferred: channel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showLogin) { LoginView(allowClose: true) }
    }

    private var brandColor: String { app.brandColor.isEmpty ? (build?.brandColor ?? "") : app.brandColor }

    private func load(force: Bool = false) async {
        if let d = await store.detail(app.id, auth: auth, force: force) {
            detail = d; error = nil
        } else if detail == nil {
            error = L("Kon de app niet laden.")
        }
        changelog = (try? await StoreAPI(auth: auth).changelog(app.id)) ?? changelog
        if let target { await library.refresh(target, auth: auth, force: force) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            StoreAppIcon(url: app.iconURL ?? build?.iconURL, brandColor: brandColor, name: app.name, size: 118, fallbackURL: build?.imageSmallURL ?? app.smallImageURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(detail?.name ?? app.name).font(.title2.weight(.bold)).lineLimit(2)
                Text(detail?.subtitle.isEmpty == false ? detail!.subtitle : app.description)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 8)
                HStack {
                    GetButton(appId: app.id, name: app.name, prominent: true)
                    Spacer()
                    if let detail, !detail.supports(store.platform) {
                        Label(L("Niet voor \(store.platform.title)"), systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                targetLine
            }
            .frame(minHeight: 118)
        }
    }

    @ViewBuilder private var targetLine: some View {
        if auth.isLoggedIn {
            if let target {
                HStack(spacing: 4) {
                    HomeyImage(homey: target, size: 16)
                    Text(target.name).lineLimit(1)
                    if let installed { Text("· v\(installed.version)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(L("Geen \(store.platform.title) gekoppeld")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Test version

    private func testBanner(_ d: StoreAppDetail) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.testOrange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Testversie \(d.testVersion) beschikbaar")).font(.subheadline.weight(.semibold))
                Text(d.hasLive ? L("Live: \(d.liveVersion)") : L("Deze app is alleen als test beschikbaar"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard auth.isLoggedIn else { showLogin = true; return }
                installChannel = .test
            } label: {
                Text(installed?.isTest == true && installed?.version == d.testVersion ? L("KLAAR") : L("TEST"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.testOrange)
                    .padding(.horizontal, 14).frame(minHeight: 28)
                    .background(Theme.testOrange.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.testOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.testOrange.opacity(0.25)))
    }

    private func testSection(_ d: StoreAppDetail, _ test: StoreBuild) -> some View {
        section(L("Testversie")) {
            HStack {
                Text("\(L("Versie")) \(test.version)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let date = test.stateChangedAt {
                    Text(date, format: .relative(presentation: .named)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !test.changelog.isEmpty { Text(test.changelog).font(.body) }
            Text(L("Testversies kunnen nog fouten bevatten. Je Homey blijft daarna testupdates van deze app ontvangen tot je de live-versie opnieuw installeert."))
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    guard auth.isLoggedIn else { showLogin = true; return }
                    installChannel = .test
                } label: {
                    Label(L("Installeer test"), systemImage: "flask")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).tint(Theme.testOrange)
                ShareLink(item: Config.storePage(d.id, test: true)) {
                    Label(L("Deel testlink"), systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Info strip

    private var infoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                infoItem(L("BEOORDELING")) {
                    if let r = detail?.rating {
                        Text(String(format: "%.1f", r))
                        StarRow(rating: r)
                    } else {
                        Text("–")
                        Text(L("Nog geen")).font(.caption)
                    }
                }
                divider
                infoItem(L("CATEGORIE")) {
                    Image(systemName: detail?.category?.symbol ?? "square.grid.2x2")
                    Text(detail?.category?.title ?? "–").font(.caption)
                }
                divider
                infoItem(L("ONTWIKKELAAR")) {
                    Image(systemName: "person.crop.square")
                    Text(detail?.authorName.isEmpty == false ? detail!.authorName : app.authorName).font(.caption).lineLimit(1)
                }
                divider
                infoItem(L("VERSIE")) {
                    Text(detail?.liveVersion.isEmpty == false ? detail!.liveVersion : (detail?.testVersion ?? "–"))
                    Text(detail?.hasLive == false ? L("Test") : L("Live")).font(.caption)
                }
                divider
                infoItem(L("APPARATEN")) {
                    Text("\(build?.driverNames.count ?? 0)")
                    Text(L("drivers")).font(.caption)
                }
                divider
                infoItem(L("FLOWS")) {
                    Text("\(build?.flowCardCount ?? 0)")
                    Text(L("kaarten")).font(.caption)
                }
                divider
                infoItem("SDK") {
                    Text(build.map { "v\($0.sdk)" } ?? "–")
                    Text(build?.platforms.map { $0 == "cloud" ? "Cloud" : "Pro" }.joined(separator: " · ") ?? "").font(.caption)
                }
            }
            .padding(.horizontal, 12)
        }
        .redacted(reason: detail == nil ? .placeholder : [])
        .overlay(alignment: .top) { Divider().padding(.horizontal, 20) }
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 20) }
    }

    private var divider: some View { Divider().frame(height: 36) }

    private func infoItem<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 2) { content() }
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 96)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
    }

    // MARK: Sections

    private func section<C: View>(_ title: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.title2.weight(.bold)) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func whatsNew(_ latest: ChangelogEntry) -> some View {
        section(L("Nieuw")) {
            HStack {
                Text("\(L("Versie")) \(latest.version)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let date = latest.date {
                    Text(date, format: .relative(presentation: .named)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !latest.text.isEmpty { Text(latest.text).font(.body) }
            if changelog.count > 1 {
                NavigationLink {
                    VersionHistoryView(entries: changelog)
                } label: {
                    Text(L("Versiegeschiedenis")).font(.body)
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let url = build?.imageLargeURL ?? app.imageURL {
            section(L("Voorvertoning")) {
                PromoImage(url: url, brandColor: brandColor)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }

    @ViewBuilder private func worksWith(_ b: StoreBuild) -> some View {
        if !b.driverNames.isEmpty || b.widgetCount > 0 {
            section(L("Werkt met")) {
                FlowLayout(spacing: 8) {
                    ForEach(Array(Set(b.driverNames)).sorted(), id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.pill, in: Capsule())
                    }
                }
                HStack(spacing: 16) {
                    if b.triggerCount > 0 { Label("\(b.triggerCount) \(L("triggers"))", systemImage: "bolt.horizontal") }
                    if b.conditionCount > 0 { Label("\(b.conditionCount) \(L("voorwaarden"))", systemImage: "questionmark.diamond") }
                    if b.actionCount > 0 { Label("\(b.actionCount) \(L("acties"))", systemImage: "play") }
                    if b.widgetCount > 0 { Label("\(b.widgetCount) widgets", systemImage: "rectangle.3.group") }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func information(_ d: StoreAppDetail, _ b: StoreBuild) -> some View {
        section(L("Informatie")) {
            VStack(spacing: 0) {
                infoRow(L("Ontwikkelaar"), d.authorName.isEmpty ? app.authorName : d.authorName)
                infoRow(L("Categorie"), d.category?.title ?? b.category)
                infoRow(L("Compatibiliteit"), b.compatibility.isEmpty ? "–" : "Homey \(b.compatibility)")
                infoRow(L("Platformen"), b.platforms.map { $0 == "cloud" ? "Homey Cloud" : "Homey Pro" }.joined(separator: ", "))
                if !b.connectivity.isEmpty {
                    infoRow(L("Verbinding"), b.connectivity.map { $0.uppercased() }.joined(separator: ", "))
                }
                infoRow(L("Rechten"), b.permissions.isEmpty ? L("Geen") : b.permissions.map { $0.replacingOccurrences(of: "homey:", with: "") }.joined(separator: "\n"))
                if !b.developers.isEmpty { infoRow(L("Ontwikkelaars"), b.developers.joined(separator: ", ")) }
                if !b.translators.isEmpty { infoRow(L("Vertalers"), b.translators.joined(separator: ", ")) }
                infoRow("App ID", d.id, copyable: true)
            }
            VStack(spacing: 0) {
                linkRow(L("Community-topic / support"), "questionmark.bubble", b.support)
                linkRow(L("Website ontwikkelaar"), "safari", b.homepage)
                linkRow(L("Broncode"), "chevron.left.forwardslash.chevron.right", b.source)
                linkRow(L("Meld een probleem"), "ladybug", b.bugs)
                linkRow(L("Doneer aan de ontwikkelaar"), "heart", b.donate)
                linkRow(L("Bekijk op homey.app"), "arrow.up.right.square", Config.storePage(d.id))
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, copyable: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Text(value.isEmpty ? "–" : value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                if copyable {
                    Button { UIPasteboard.general.string = value } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 10)
            Divider()
        }
    }

    @ViewBuilder private func linkRow(_ title: String, _ icon: String, _ url: URL?) -> some View {
        if let url {
            Button { openURL(url) } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: icon)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 11)
            }
            Divider()
        }
    }
}

struct StarRow: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: rating >= Double(i) + 0.75 ? "star.fill" : rating >= Double(i) + 0.25 ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(.system(size: 9))
    }
}

struct VersionHistoryView: View {
    let entries: [ChangelogEntry]

    var body: some View {
        List(entries) { e in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(e.version).font(.headline)
                    if e.state == "live" {
                        Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.green, in: Capsule())
                    } else if e.state == "test" {
                        Text("TEST").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.testOrange, in: Capsule())
                    }
                    Spacer()
                    if let d = e.date { Text(d, format: .dateTime.day().month().year()).font(.subheadline).foregroundStyle(.secondary) }
                }
                if !e.text.isEmpty { Text(e.text).font(.subheadline) }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .navigationTitle(L("Versiegeschiedenis"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
