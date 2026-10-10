import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @State private var tab = Tab.today

    enum Tab: Hashable { case today, apps, myHomey, search }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label(L("Vandaag"), systemImage: "doc.text.image") }
                .tag(Tab.today)
            AppsView()
                .tabItem { Label(L("Apps"), systemImage: "square.stack.3d.up.fill") }
                .tag(Tab.apps)
            MyHomeyView()
                .tabItem { Label(L("Mijn Homey"), systemImage: "house.fill") }
                .tag(Tab.myHomey)
            SearchView()
                .tabItem { Label(L("Zoeken"), systemImage: "magnifyingglass") }
                .tag(Tab.search)
        }
        // Keep the installed-apps state of the target Homey fresh for the Get buttons.
        .task(id: "\(auth.generation)|\(store.platform.rawValue)|\(auth.homeys.count)") {
            if let target = library.target(for: store.platform, auth: auth) {
                await library.refresh(target, auth: auth)
            }
        }
    }
}
