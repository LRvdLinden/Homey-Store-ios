import SwiftUI

/// "Zoeken": search field with suggestions and categories, live results while typing.
struct SearchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store

    @State private var query = ""
    @State private var results: [StoreApp] = []
    @State private var total = 0
    @State private var searching = false
    @State private var error: String?
    @AppStorage("search.recent") private var recentRaw = ""

    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
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
                        prompt: L("Apps, merken en apparaten"))
            .onSubmit(of: .search) { remember(query) }
            .task(id: "\(query)|\(store.platform.rawValue)") { await search() }
        }
    }

    @ViewBuilder private var discover: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { term in
                    Button { query = term } label: {
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
            ForEach(["Philips Hue", "Sonos", "Zigbee", "Energie", "Tuya", "Shelly"], id: \.self) { term in
                Button { query = term } label: {
                    Label(term, systemImage: "magnifyingglass").foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text(L("Ontdek")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
        }

        Section {
            CategoryList().listRowSeparator(.hidden)
        } header: {
            Text(L("Categorieën")).font(.title2.weight(.bold)).foregroundStyle(.primary).textCase(nil)
        }
    }

    @ViewBuilder private var resultsSection: some View {
        if let error {
            ErrorBanner(message: error) { Task { await search() } }.listRowSeparator(.hidden)
        }
        if results.isEmpty && !searching && error == nil {
            ContentUnavailableView.search(text: query).listRowSeparator(.hidden)
        }
        ForEach(results) { app in
            AppRow(app: app)
        }
        if searching {
            HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
        } else if total > results.count {
            NavigationLink {
                CategoryAppsView(category: nil, query: query, title: query)
            } label: {
                Text(L("Toon alle \(total) resultaten")).foregroundStyle(Theme.accent)
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; total = 0; error = nil; return }
        try? await Task.sleep(for: .milliseconds(280))   // debounce typing
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let page = try await StoreAPI(auth: auth).browse(platform: store.platform, query: q, limit: 30)
            guard !Task.isCancelled else { return }
            results = page.items
            total = page.total
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentRaw = ([t] + recent.filter { $0.caseInsensitiveCompare(t) != .orderedSame }).prefix(6).joined(separator: "\n")
    }
}
