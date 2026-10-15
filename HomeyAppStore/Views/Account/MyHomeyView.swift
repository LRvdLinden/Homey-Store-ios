import SwiftUI
import UIKit

/// "Mijn Homey": the apps installed on the selected Homey, with available updates,
/// test versions and CLI installs — like the App Store's updates/purchased list.
/// On Homey Pro you can also restart an app and switch automatic updates.
struct MyHomeyView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @State private var showLogin = false
    @State private var updatingAll = false
    @State private var myApps: [StoreApp] = []

    private var homeys: [HomeyRef] { library.homeys(for: store.platform, auth: auth) }
    private var target: HomeyRef? { library.target(for: store.platform, auth: auth) }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn {
                    ContentUnavailableView {
                        Label(L("Log in om te installeren"), systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text(L("Log in met je Homey-account om apps op je Homey te zien en te installeren."))
                    } actions: {
                        Button(L("Inloggen")) { showLogin = true }.buttonStyle(.borderedProminent)
                    }
                } else if let target {
                    installedList(target)
                } else {
                    ContentUnavailableView(L("Geen \(store.platform.title)"), systemImage: store.platform.icon,
                                           description: Text(L("Aan dit account is geen \(store.platform.title) gekoppeld. Wissel bovenaan van store of van account.")))
                }
            }
            .navigationTitle(L("Mijn Homey"))
            .storeToolbar()
            .storeDestinations()
            .fullScreenCover(isPresented: $showLogin) { LoginView(allowClose: true) }
        }
    }

    private func installedList(_ homey: HomeyRef) -> some View {
        let apps = (library.installed[homey.id].map { Array($0.values) } ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let updates = apps.filter { library.updateVersion(for: $0, detail: store.details[$0.id]) != nil }
        let updateIDs = Set(updates.map(\.id))
        let crashed = apps.filter { $0.crashed && !updateIDs.contains($0.id) }
        let crashedIDs = Set(crashed.map(\.id))
        let tests = apps.filter { $0.isTest && !updateIDs.contains($0.id) && !crashedIDs.contains($0.id) }
        let devkit = apps.filter { $0.isDevkit && !crashedIDs.contains($0.id) }
        let rest = apps.filter { !updateIDs.contains($0.id) && !crashedIDs.contains($0.id) && !$0.isTest && !$0.isDevkit }

        return List {
            Section {
                homeyHeader(homey, count: apps.count)
            }

            if let err = library.errors[homey.id] {
                ErrorBanner(message: err) { Task { await library.refresh(homey, auth: auth, force: true) } }
            }

            if !updates.isEmpty {
                Section {
                    ForEach(updates) { InstalledRow(app: $0, homey: homey) }
                } header: {
                    HStack {
                        Text(L("Updates beschikbaar")).font(.title3.weight(.bold)).foregroundStyle(.primary)
                        Spacer()
                        if homey.canInstall {
                            Button(updatingAll ? L("Bezig…") : L("Werk alles bij")) { updateAll(updates, on: homey) }
                                .font(.body).disabled(updatingAll)
                        }
                    }
                    .textCase(nil)
                }
            }

            if !crashed.isEmpty {
                Section(L("Gecrasht")) { ForEach(crashed) { InstalledRow(app: $0, homey: homey) } }
            }

            if !tests.isEmpty {
                Section(L("Testversies")) { ForEach(tests) { InstalledRow(app: $0, homey: homey) } }
            }

            Section(L("Geïnstalleerd")) {
                ForEach(rest) { InstalledRow(app: $0, homey: homey) }
            }

            if !devkit.isEmpty {
                Section(L("Ontwikkelversies (CLI)")) { ForEach(devkit) { InstalledRow(app: $0, homey: homey) } }
            }

            if !myApps.isEmpty {
                Section {
                    ForEach(myApps) { AppRow(app: $0, iconSize: 44) }
                } header: {
                    Text(L("Mijn apps als ontwikkelaar"))
                } footer: {
                    Text(L("Apps die je zelf in de Homey App Store hebt gezet, ook als ze alleen als test bestaan."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if apps.isEmpty && library.loadingHomeys.contains(homey.id) { ProgressView() }
        }
        .refreshable {
            await library.refresh(homey, auth: auth, force: true)
            let ids = library.installed[homey.id].map { Array($0.keys) } ?? []
            await store.refreshDetails(ids, auth: auth, maxAge: 0)
        }
        .task(id: "\(homey.id)|\(auth.generation)") {
            await library.refresh(homey, auth: auth)
            // Store info for every installed app (icons, latest live/test versions), six at a time.
            let ids = library.installed[homey.id].map { Array($0.keys) } ?? []
            await store.refreshDetails(ids, auth: auth)
            myApps = (try? await StoreAPI(auth: auth).myApps()) ?? []
        }
    }

    private func updateAll(_ updates: [InstalledApp], on homey: HomeyRef) {
        updatingAll = true
        Task {
            for app in updates {
                let target = library.updateVersion(for: app, detail: store.details[app.id])
                await library.install(app.id, channel: app.installedChannel, expectedVersion: target, on: homey, auth: auth)
            }
            updatingAll = false
        }
    }

    private func homeyHeader(_ homey: HomeyRef, count: Int) -> some View {
        HStack(spacing: 14) {
            HomeyImage(homey: homey, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(homey.name).font(.headline)
                Text(homey.details).font(.caption).foregroundStyle(.secondary)
                Text(L("\(count) apps")).font(.caption).foregroundStyle(.secondary)
                if !homey.canInstall {
                    Text(L("Alleen bekijken: je bent geen eigenaar of beheerder")).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if homeys.count > 1 {
                Menu {
                    ForEach(homeys) { h in
                        Button { library.setTarget(h, platform: store.platform, auth: auth) } label: {
                            if h.id == homey.id { Label("\(h.name) – \(h.model)", systemImage: "checkmark") } else { Text("\(h.name) – \(h.model)") }
                        }
                    }
                } label: {
                    Text(L("Wissel")).font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// One installed app. Shows version, channel and status; long-press for actions
/// (restart and automatic updates on Homey Pro, open in the store, share).
struct InstalledRow: View {
    let app: InstalledApp
    let homey: HomeyRef

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @State private var actionError: String?

    private var detail: StoreAppDetail? { store.details[app.id] }
    private var update: String? { library.updateVersion(for: app, detail: detail) }
    private var canManage: Bool { !homey.isCloud && homey.canInstall }
    private var storeApp: StoreApp { detail.map(StoreApp.init(detail:)) ?? StoreApp(id: app.id) }

    var body: some View {
        Group {
            if detail != nil || app.isFromStore {
                NavigationLink(value: storeApp) { content }
            } else {
                content
            }
        }
        .contextMenu { menu }
        .swipeActions(edge: .trailing) {
            if canManage {
                Button { Task { await library.restart(app.id, on: homey, auth: auth) } } label: {
                    Label(L("Herstart"), systemImage: "arrow.clockwise")
                }
                .tint(.orange)
            }
        }
        .alert(L("Lukt niet"), isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder private var menu: some View {
        if canManage {
            Button { Task { await library.restart(app.id, on: homey, auth: auth) } } label: {
                Label(L("Herstart app"), systemImage: "arrow.clockwise")
            }
            if app.isFromStore {
                Toggle(isOn: Binding(get: { app.autoUpdate }, set: { on in
                    Task { actionError = await library.setAutoUpdate(app.id, on, on: homey, auth: auth) }
                })) {
                    Label(L("Automatisch bijwerken"), systemImage: "arrow.down.circle")
                }
            }
        }
        if app.isFromStore {
            ShareLink(item: Config.storePage(app.id, test: app.isTest)) { Label(L("Deel"), systemImage: "square.and.arrow.up") }
        }
        Button { UIPasteboard.general.string = app.id } label: { Label(L("Kopieer app-ID"), systemImage: "doc.on.doc") }
    }

    private var content: some View {
        HStack(spacing: 12) {
            // Store icon when the app is in the store; otherwise the icon the Homey itself
            // serves (private apps and CLI installs).
            StoreAppIcon(url: detail?.primaryBuild?.iconURL ?? app.iconURL(on: homey),
                         brandColor: detail?.primaryBuild?.brandColor ?? (app.brandColor.isEmpty ? "#8E8E93" : app.brandColor),
                         name: app.name, size: 48, fallbackURL: detail?.primaryBuild?.imageSmallURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(app.version)")
                    if app.isTest {
                        Text("TEST").font(.caption2.weight(.bold)).foregroundStyle(Theme.testOrange)
                    }
                    if let update {
                        Text("→ \(update)").foregroundStyle(Theme.accent)
                    } else if let d = detail, d.hasTest, !app.isTest, d.testVersion != app.version {
                        Text(L("test \(d.testVersion)")).foregroundStyle(Theme.testOrange)
                    }
                    if app.crashed { Text(L("gecrasht")).foregroundStyle(.red) }
                    else if !app.enabled { Text(L("uit")).foregroundStyle(.red) }
                    if canManage, app.isFromStore, app.autoUpdate {
                        Image(systemName: "arrow.down.circle").foregroundStyle(.secondary).accessibilityLabel(L("Werkt automatisch bij"))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if app.crashed, !app.crashedMessage.isEmpty {
                    Text(app.crashedMessage).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            if case .working = library.state(app.id, on: homey) {
                ProgressView()
            } else if app.crashed, canManage {
                Button(L("Herstart")) { Task { await library.restart(app.id, on: homey, auth: auth) } }
                    .font(.footnote.weight(.bold)).buttonStyle(.bordered).controlSize(.small).tint(.orange)
            }
        }
    }
}
