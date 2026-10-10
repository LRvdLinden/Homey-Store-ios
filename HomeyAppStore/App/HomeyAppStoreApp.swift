import SwiftUI

@main
struct HomeyAppStoreApp: App {
    @State private var auth = AuthManager()
    @State private var store = StoreState()
    @State private var library = HomeyLibrary()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(store)
                .environment(library)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @AppStorage("store.skippedLogin") private var skippedLogin = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if auth.isLoggedIn || skippedLogin {
                MainTabView()
                    .transition(.opacity)
            } else if !showSplash {
                LoginView(onSkip: { withAnimation { skippedLogin = true } })
                    .transition(.opacity)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isLoggedIn)
        .task {
            // Preload the account and store front while the splash is on screen
            // (at least 1.4 s, at most ~4 s on a slow connection).
            Task { @MainActor in
                if auth.isLoggedIn { try? await auth.loadUser() }
                await store.loadHighlights(auth: auth)
            }
            try? await Task.sleep(for: .milliseconds(1400))
            for _ in 0..<26 where store.highlightsLoading { try? await Task.sleep(for: .milliseconds(100)) }
            withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
        }
    }
}
