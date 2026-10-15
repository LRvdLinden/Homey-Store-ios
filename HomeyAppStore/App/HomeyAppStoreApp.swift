import SwiftUI

@main
struct HomeyAppStoreApp: App {
    @State private var auth = AuthManager()
    @State private var store = StoreState()
    @State private var library = HomeyLibrary()
    @State private var router = Router()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(store)
                .environment(library)
                .environment(router)
                // Dates and numbers follow the app's language, like the store texts.
                .environment(\.locale, Config.appLocale)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .onOpenURL { router.open($0) }
        }
    }
}

/// Opens apps from links: `homeystore://app/<id>`, `homeystore://app/<id>/test`,
/// and pasted store links `https://homey.app/a/<id>` or `…/app/<id>/…`.
@MainActor
@Observable
final class Router {
    /// App to show as a sheet on top of the current tab.
    var linkedApp: StoreApp?

    func open(_ url: URL) {
        guard let id = Self.appID(in: url) else { return }
        linkedApp = StoreApp(id: id)
    }

    /// The app id in a Homey Store or homey.app link, if any.
    static func appID(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "homeystore" {
            // homeystore://app/<id>  → host "app", first path part = id
            if url.host == "app", let id = parts.first { return id }
            if let i = parts.firstIndex(of: "app"), parts.indices.contains(i + 1) { return parts[i + 1] }
            return nil
        }
        guard let host = url.host, host.hasSuffix("homey.app") else { return nil }
        // homey.app/a/<id>[/test] and homey.app/<locale>/app/<id>/<name>/
        for marker in ["a", "app"] {
            if let i = parts.firstIndex(of: marker), parts.indices.contains(i + 1) {
                let id = parts[i + 1]
                if id.contains(".") { return id }
            }
        }
        return nil
    }

    /// Recognises a link or a bare app id ("nl.philips.hue") typed into search.
    static func appID(inText text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: t), url.scheme != nil, let id = appID(in: url) { return id }
        if t.hasPrefix("homey.app/"), let url = URL(string: "https://" + t), let id = appID(in: url) { return id }
        let isID = t.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+){1,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
        return isID && !t.contains(" ") ? t.lowercased() : nil
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
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
        // Another account: forget everything fetched with the previous one.
        .onChange(of: auth.generation) { _, gen in
            store.reset(generation: gen)
            library.reset(generation: gen)
            Task { await store.loadHighlights(auth: auth, force: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AppIconRenderer.shared.retryFailures() }
        }
        .task {
            // Preload the account and store front while the splash is on screen
            // (at least 1.4 s, at most ~4 s on a slow connection).
            store.reset(generation: auth.generation)
            library.reset(generation: auth.generation)
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
