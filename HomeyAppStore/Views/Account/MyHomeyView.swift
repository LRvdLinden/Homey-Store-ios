import SwiftUI

/// "Mijn Homey": the apps installed on the selected Homey, with available updates
/// and test versions — like the App Store's updates/purchased list.
struct MyHomeyView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @State private var showLogin = false
    @State private var updatingAll = false

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
        let updates = apps.filter { hasUpdate($0) }
        let tests = apps.filter { $0.isTest }
        let devkit = apps.filter { $0.isDevkit }

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
                        Button(updatingAll ? L("Bezig…") : L("Werk alles bij")) {
                            updatingAll = true
                            Task {
                                for app in updates { await library.install(app.id, channel: .live, on: homey, auth: auth) }
                                updatingAll = false
                            }
                        }
                        .font(.body).disabled(updatingAll)
                    }
                    .textCase(nil)
                }
            }

            if !tests.isEmpty {
                Section(L("Testversies")) { ForEach(tests) { InstalledRow(app: $0, homey: homey) } }
            }

            Section(L("Geïnstalleerd")) {
                ForEach(apps.filter { !hasUpdate($0) && !$0.isTest && !$0.isDevkit }) { InstalledRow(app: $0, homey: homey) }
            }

            if !devkit.isEmpty {
                Section(L("Ontwikkelversies (CLI)")) { ForEach(devkit) { InstalledRow(app: $0, homey: homey) } }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if apps.isEmpty && library.loadingHomeys.contains(homey.id) { ProgressView() }
        }
        .refreshable { await library.refresh(homey, auth: auth, force: true) }
        .task(id: homey.id) {
            await library.refresh(homey, auth: auth)
            // Load store info for all installed apps (icons, latest versions).
            let ids = (library.installed[homey.id].map { Array($0.keys) } ?? []).filter { store.details[$0] == nil }
            await withTaskGroup(of: Void.self) { group in
                for id in ids.prefix(80) {
                    group.addTask { @MainActor in _ = await store.detail(id, auth: auth) }
                }
            }
        }
    }

    private func homeyHeader(_ homey: HomeyRef, count: Int) -> some View {
        HStack(spacing: 14) {
            HomeyImage(homey: homey, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(homey.name).font(.headline)
                Text(homey.details).font(.caption).foregroundStyle(.secondary)
                Text(L("\(count) apps")).font(.caption).foregroundStyle(.secondary)
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

    private func hasUpdate(_ app: InstalledApp) -> Bool {
        guard !app.isTest, !app.isDevkit, let d = store.details[app.id], !d.liveVersion.isEmpty else { return false }
        return d.liveVersion.compare(app.version, options: .numeric) == .orderedDescending
    }
}

struct InstalledRow: View {
    let app: InstalledApp
    let homey: HomeyRef

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library

    private var detail: StoreAppDetail? { store.details[app.id] }

    var body: some View {
        HStack(spacing: 12) {
            if let detail {
                NavigationLink(value: StoreApp(detail: detail)) { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            // Store icon when the app is in the store; otherwise the icon the Homey itself serves
            // (private apps and CLI installs).
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
                    if let d = detail, !app.isTest, d.liveVersion.compare(app.version, options: .numeric) == .orderedDescending {
                        Text("→ \(d.liveVersion)").foregroundStyle(Theme.accent)
                    }
                    if let d = detail, d.hasTest, !app.isTest, d.testVersion != app.version {
                        Text(L("test \(d.testVersion)")).foregroundStyle(Theme.testOrange)
                    }
                    if !app.enabled { Text(L("uit")).foregroundStyle(.red) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if case .working = library.state(app.id, on: homey) { ProgressView() }
        }
    }
}
