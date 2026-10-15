import SwiftUI

/// "Apps": shelves like the App Store Apps tab — popular, new, updated, top per category.
struct AppsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    let h = store.current

                    if let error = store.highlightsError[store.platform], h.isEmpty {
                        ErrorBanner(message: error) { Task { await store.loadHighlights(auth: auth, force: true) } }
                            .padding(.horizontal, 20)
                    } else if h.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }

                    if !h.popular.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(h.popular.prefix(5)) { app in
                                    FeatureCard(app: app, eyebrow: L("Populair"))
                                        .containerRelativeFrame(.horizontal) { w, _ in min(w - 40, 560) }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 20)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }

                    if !h.popular.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ShelfHeader(title: L("Populaire apps"), subtitle: L("Meest geïnstalleerd aller tijden")) {
                                AppListView(title: L("Populaire apps"), apps: h.popular)
                            }
                            AppShelf(apps: h.popular, ranked: true)
                        }
                    }

                    if !h.recentlyCreated.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ShelfHeader(title: L("Nieuwe apps")) { AppListView(title: L("Nieuwe apps"), apps: h.recentlyCreated) }
                            AppShelf(apps: h.recentlyCreated)
                        }
                    }

                    if !h.recentlyUpdated.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ShelfHeader(title: L("Onlangs bijgewerkt")) { AppListView(title: L("Onlangs bijgewerkt"), apps: h.recentlyUpdated) }
                            AppShelf(apps: h.recentlyUpdated)
                        }
                    }

                    ForEach(h.byCategory) { shelf in
                        VStack(alignment: .leading, spacing: 10) {
                            ShelfHeader(title: L("Top \(shelf.category.title)")) { CategoryAppsView(category: shelf.category) }
                            AppShelf(apps: shelf.apps, ranked: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ShelfHeader(title: L("Categorieën"))
                        CategoryList()
                            .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ShelfHeader(title: L("Op verbinding"), subtitle: L("Apps voor Zigbee, Z-Wave, Matter en meer"))
                        ConnectivityList()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 12)
            }
            .refreshable { await store.loadHighlights(auth: auth, force: true) }
            .navigationTitle(L("Apps"))
            .storeToolbar()
            .storeDestinations()
        }
    }
}

struct CategoryList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(StoreCategory.allCases) { c in
                NavigationLink(value: c) {
                    HStack(spacing: 14) {
                        Image(systemName: c.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color(hex: c.tint) ?? Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(c.title).font(.body).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if c != StoreCategory.allCases.last { Divider().padding(.leading, 44) }
            }
        }
    }
}

/// Entry points per connectivity (Zigbee, Z-Wave, Matter, …).
struct ConnectivityList: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(StoreConnectivity.allCases) { c in
                NavigationLink {
                    CategoryAppsView(category: nil, title: c.title, initialConnectivity: c)
                } label: {
                    HStack {
                        Image(systemName: c.symbol).foregroundStyle(Theme.accent)
                        Text(c.title).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum AppSort: String, CaseIterable, Identifiable {
    case relevance, name
    var id: String { rawValue }
    var title: String { self == .relevance ? L("Relevantie") : L("Naam (A–Z)") }
}

/// All apps in one category (or matching a search) for the current store, paged,
/// with filters for connectivity and widgets.
struct CategoryAppsView: View {
    let category: StoreCategory?
    let query: String
    let title: String?
    let initialConnectivity: StoreConnectivity?

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @State private var apps: [StoreApp] = []
    @State private var total: Int?
    @State private var offset = 0
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?
    /// What the current list was loaded for; reload only when this changes, so going
    /// back from an app keeps the list and scroll position.
    @State private var loadedFor: String?
    @State private var connectivity: StoreConnectivity?
    @State private var widgetsOnly = false
    @State private var sort = AppSort.relevance

    private let pageSize = 30

    init(category: StoreCategory?, query: String = "", title: String? = nil, initialConnectivity: StoreConnectivity? = nil) {
        self.category = category
        self.query = query
        self.title = title
        self.initialConnectivity = initialConnectivity
        _connectivity = State(initialValue: initialConnectivity)
    }

    private var filterKey: String {
        "\(store.platform.rawValue)|\(category?.rawValue ?? "")|\(query)|\(connectivity?.rawValue ?? "")|\(widgetsOnly)|\(auth.generation)"
    }

    private var shown: [StoreApp] {
        sort == .name ? apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } : apps
    }

    var body: some View {
        List {
            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(shown) { app in
                    AppRow(app: app)
                        .onAppear { if app.id == apps.last?.id { loadMore() } }
                }
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                }
                if let error {
                    ErrorBanner(message: error) { loadMore() }.listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !loading, error == nil, apps.isEmpty, loadedFor != nil {
                ContentUnavailableView(L("Geen apps"), systemImage: "square.dashed", description: Text(emptyText))
            }
        }
        .navigationTitle(title ?? category?.title ?? L("Apps"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let total { Text("\(total)").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .task(id: filterKey) {
            guard loadedFor != filterKey else { return }
            reload()
        }
        .refreshable { reload(); await loadTask?.value }
    }

    private var emptyText: String {
        if !query.isEmpty || connectivity != nil || widgetsOnly {
            return L("Geen apps gevonden met deze zoekopdracht of filters.")
        }
        return L("Er zijn hier nog geen apps voor \(store.platform.title).")
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker(L("Sorteer"), selection: $sort) {
                        ForEach(AppSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    FilterChip(title: sort.title, systemImage: "arrow.up.arrow.down", active: sort != .relevance)
                }
                Menu {
                    Button(L("Alle verbindingen")) { connectivity = nil }
                    ForEach(StoreConnectivity.allCases) { c in
                        Button { connectivity = c } label: {
                            if connectivity == c { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                        }
                    }
                } label: {
                    FilterChip(title: connectivity?.title ?? L("Verbinding"), systemImage: "antenna.radiowaves.left.and.right",
                               active: connectivity != nil)
                }
                Button { widgetsOnly.toggle() } label: {
                    FilterChip(title: L("Met widgets"), systemImage: "rectangle.3.group", active: widgetsOnly)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    private func reload() {
        loadTask?.cancel()
        apps = []; total = nil; offset = 0; reachedEnd = false; error = nil; loading = false
        loadedFor = filterKey
        loadMore()
    }

    private func loadMore() {
        guard !loading, !reachedEnd else { return }
        loading = true
        let key = filterKey
        let currentOffset = offset
        loadTask = Task {
            defer { if loadedFor == key { loading = false } }
            do {
                let page = try await StoreAPI(auth: auth).browse(
                    platform: store.platform, query: query, category: category,
                    connectivity: connectivity, widgetsOnly: widgetsOnly,
                    limit: pageSize, offset: currentOffset)
                guard !Task.isCancelled, loadedFor == key else { return }
                let known = Set(apps.map(\.id))
                apps += page.items.filter { !known.contains($0.id) }
                offset = currentOffset + page.received
                total = page.total
                // Stop when the API says we have everything, or a page comes back short.
                reachedEnd = page.received < pageSize || (page.total.map { offset >= $0 } ?? false)
                error = nil
            } catch {
                guard !Task.isCancelled, loadedFor == key else { return }
                self.error = ErrorText.message(error)
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    var active = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(active ? Color.white : Color.primary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.pill), in: Capsule())
    }
}
