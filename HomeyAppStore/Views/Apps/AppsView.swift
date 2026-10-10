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
                                        .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
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

/// All apps in one category for the current store, paged.
struct CategoryAppsView: View {
    let category: StoreCategory?
    var query: String = ""
    var title: String? = nil

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @State private var apps: [StoreApp] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(apps) { app in
                AppRow(app: app)
                    .onAppear { if app.id == apps.last?.id { Task { await loadMore() } } }
            }
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
            }
            if let error {
                ErrorBanner(message: error) { Task { await reload() } }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if !loading, error == nil, apps.isEmpty {
                ContentUnavailableView(L("Geen apps"), systemImage: "square.dashed",
                                       description: Text(L("Er zijn hier nog geen apps voor \(store.platform.title).")))
            }
        }
        .navigationTitle(title ?? category?.title ?? L("Apps"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Text("\(total)").font(.footnote).foregroundStyle(.secondary) } }
        .task(id: store.platform) { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        apps = []; total = 0; error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !loading, apps.isEmpty || apps.count < total else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await StoreAPI(auth: auth).browse(platform: store.platform, query: query, category: category,
                                                             limit: 30, offset: apps.count)
            let known = Set(apps.map(\.id))
            apps += page.items.filter { !known.contains($0.id) }
            total = page.items.isEmpty ? apps.count : page.total
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
