import SwiftUI

enum StoreTab: Hashable { case today, apps, myHomey, search }

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var tab = StoreTab.today

    private var updateCount: Int {
        guard let target = library.target(for: store.platform, auth: auth) else { return 0 }
        return library.updates(on: target, details: store.details).count
    }

    var body: some View {
        @Bindable var router = router
        tabs
            .overlay(alignment: .top) { OfflineBanner() }
            // Keep the installed apps of the target Homey fresh for the Get buttons,
            // and check them for updates in the background (badge on Mijn Homey).
            .task(id: "\(auth.generation)|\(store.platform.rawValue)|\(auth.homeys.count)") {
                guard let target = library.target(for: store.platform, auth: auth) else { return }
                await library.refresh(target, auth: auth)
                let ids = library.installed[target.id].map { Array($0.keys) } ?? []
                await store.refreshDetails(ids, auth: auth)
            }
            .sheet(item: $router.linkedApp) { app in
                NavigationStack {
                    AppDetailView(app: app)
                        .storeDestinations()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L("Sluit")) { router.linkedApp = nil }
                            }
                        }
                }
            }
    }

    /// iPhone: tab bar. iPad on iOS 18+: the same tabs, shown as a sidebar when wide.
    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab(L("Vandaag"), systemImage: "doc.text.image", value: StoreTab.today) { TodayView() }
                Tab(L("Apps"), systemImage: "square.stack.3d.up.fill", value: StoreTab.apps) { AppsView() }
                Tab(L("Mijn Homey"), systemImage: "house.fill", value: StoreTab.myHomey) { MyHomeyView() }
                    .badge(updateCount)
                Tab(L("Zoeken"), systemImage: "magnifyingglass", value: StoreTab.search, role: .search) { SearchView() }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView(selection: $tab) {
                TodayView()
                    .tabItem { Label(L("Vandaag"), systemImage: "doc.text.image") }
                    .tag(StoreTab.today)
                AppsView()
                    .tabItem { Label(L("Apps"), systemImage: "square.stack.3d.up.fill") }
                    .tag(StoreTab.apps)
                MyHomeyView()
                    .tabItem { Label(L("Mijn Homey"), systemImage: "house.fill") }
                    .badge(updateCount)
                    .tag(StoreTab.myHomey)
                SearchView()
                    .tabItem { Label(L("Zoeken"), systemImage: "magnifyingglass") }
                    .tag(StoreTab.search)
            }
        }
    }
}

/// Small "offline" pill at the top while there is no internet connection.
struct OfflineBanner: View {
    var body: some View {
        if !NetworkMonitor.shared.isOnline {
            Label(L("Je bent offline"), systemImage: "wifi.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.orange, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// Readable width on iPad: content is centred and never wider than `max`.
extension View {
    func readableWidth(_ max: CGFloat = 720) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
    }
}
