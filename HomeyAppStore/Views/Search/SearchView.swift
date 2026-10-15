import SwiftUI

/// "Zoeken": search field with suggestions and categories, live results while typing.
/// A pasted homey.app link or an app id ("nl.philips.hue") opens that app directly.
struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var results: [StoreApp] = []
    @State private var total: Int?
    @State private var received = 0
    @State private var searching = false
    @State private var error: String?
    @AppStorage("search.recent") private var recentRaw = ""

    private let pageSize = 30
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var linkedID: String? { Router.appID(inText: trimmed) }

    /// Installed apps on the target Homey whose name matches.
    private var installedMatches: [InstalledApp] {
        guard !trimmed.isEmpty, let target = library.target(for: store.platform, auth: auth) else { return [] }
        return (library.installed[target.id]?.values.map { $0 } ?? [])
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    discover
                } else {
                    resultsSection
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("Zoeken"))
            .storeToolbar()
            .storeDestinations()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: L("Apps, merken of een homey.app-link"))
            .onSubmit(of: .search) {
                if let id = linkedID, results.isEmpty { router.linkedApp = StoreApp(id: id) }
                remember(trimmed)
            }
            .task(id: "\(trimmed)|\(store.platform.rawValue)") { await search() }
        }
    }

    @ViewBuilder private var discover: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { term in
                    Button { pick(term) } label: {
                        Label(term, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text(L("Recent")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
                    Spacer()
                    Button(L("Wis")) { recentRaw = "" }.font(.body).textCase(nil)
                }
            }
        }

        Section {
            ForEach(["Philips Hue", "Sonos", "Shelly", "Tuya", "Energie", "Weer"], id: \.self) { term in
                Button { pick(term) } label: {
                    Label(term, systemImage: "magnifyingglass").foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text(L("Ontdek")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
        }

        Section {
            ConnectivityList().listRowSeparator(.hidden)
        } header: {
            Text(L("Op verbinding")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
        }

        Section {
            CategoryList().listRowSeparator(.hidden)
        } header: {
            Text(L("Categorieën")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
        }
    }

    @ViewBuilder private var resultsSection: some View {
        if let id = linkedID {
            Section {
                Button { router.linkedApp = StoreApp(id: id) } label: {
                    Label(L("Open app \(id)"), systemImage: "arrow.up.forward.app")
                }
            }
        }

        if !installedMatches.isEmpty {
            Section(L("Op je Homey")) {
                ForEach(installedMatches.prefix(5)) { app in
                    NavigationLink(value: store.details[app.id].map(StoreApp.init(detail:)) ?? StoreApp(id: app.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                Text("v\(app.version)\(app.isTest ? " · TEST" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
        }

        Section {
            if let error {
                ErrorBanner(message: error) { Task { await search() } }.listRowSeparator(.hidden)
            }
            if results.isEmpty && !searching && error == nil && linkedID == nil && installedMatches.isEmpty {
                ContentUnavailableView.search(text: trimmed).listRowSeparator(.hidden)
            }
            ForEach(results) { app in
                AppRow(app: app)
            }
            if searching && results.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
            } else if hasMore {
                NavigationLink {
                    CategoryAppsView(category: nil, query: trimmed, title: trimmed)
                } label: {
                    Text(total.map { L("Toon alle \($0) resultaten") } ?? L("Toon meer resultaten")).foregroundStyle(Theme.accent)
                }
            }
        } header: {
            if !results.isEmpty, !installedMatches.isEmpty || linkedID != nil {
                Text(L("In de store"))
            }
        }
    }

    private var hasMore: Bool {
        if let total { return total > results.count }
        return received >= pageSize
    }

    private func pick(_ term: String) {
        query = term
        remember(term)
    }

    private func search() async {
        let q = trimmed
        guard !q.isEmpty else { results = []; total = nil; error = nil; searching = false; return }
        searching = true   // right away, so "no results" doesn't flash while typing
        try? await Task.sleep(for: .milliseconds(280))   // debounce typing
        guard !Task.isCancelled else { return }
        defer { if !Task.isCancelled { searching = false } }
        do {
            let page = try await StoreAPI(auth: auth).browse(platform: store.platform, query: q, limit: pageSize)
            guard !Task.isCancelled else { return }
            results = page.items
            total = page.total
            received = page.received
            error = nil
        } catch {
            if !Task.isCancelled, let msg = ErrorText.message(error) { self.error = msg }
        }
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, Router.appID(inText: t) == nil else { return }
        recentRaw = ([t] + recent.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(6).joined(separator: "\n")
    }
}
