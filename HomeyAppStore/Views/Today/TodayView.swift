import SwiftUI

/// "Vandaag": big editorial cards like the App Store Today tab.
struct TodayView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    header

                    if let error = store.highlightsError[store.platform], store.current.isEmpty {
                        ErrorBanner(message: error) { Task { await store.loadHighlights(auth: auth, force: true) } }
                    } else if store.current.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.card).frame(height: 360)
                                .redacted(reason: .placeholder)
                        }
                    }

                    let h = store.current
                    if let first = h.popular.first {
                        TodayHeroCard(app: first, eyebrow: L("Populair"), title: L("Het meest geïnstalleerd"))
                    }
                    if !h.recentlyCreated.isEmpty {
                        TodayListCard(eyebrow: L("Nieuw in de store"), title: L("Vers van de pers"),
                                      apps: Array(h.recentlyCreated.prefix(4)), all: h.recentlyCreated, tint: "#5856D6")
                    }
                    if let pick = h.recentlyUpdated.first {
                        TodayHeroCard(app: pick, eyebrow: L("Net bijgewerkt"), title: pick.description)
                    }
                    if let energy = h.byCategory.first(where: { $0.category == .energy }) {
                        TodayListCard(eyebrow: L("Bespaar energie"), title: L("Apps die je helpen besparen"),
                                      apps: Array(energy.apps.prefix(4)), all: energy.apps, tint: StoreCategory.energy.tint)
                    }
                    if h.popular.count > 1 {
                        TodayHeroCard(app: h.popular[1], eyebrow: L("Aanrader"), title: h.popular[1].description)
                    }
                    if let security = h.byCategory.first(where: { $0.category == .security }) {
                        TodayListCard(eyebrow: L("Veilig thuis"), title: L("Apps voor een veilig huis"),
                                      apps: Array(security.apps.prefix(4)), all: security.apps, tint: StoreCategory.security.tint)
                    }
                    if !h.recentlyUpdated.isEmpty {
                        TodayListCard(eyebrow: L("Updates"), title: L("Onlangs bijgewerkt"),
                                      apps: Array(h.recentlyUpdated.dropFirst().prefix(4)), all: h.recentlyUpdated, tint: "#0A84FF")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .refreshable { await store.loadHighlights(auth: auth, force: true) }
            .background(Theme.groupedBackground)
            .toolbar(.hidden, for: .navigationBar)
            .storeDestinations()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text(L("Vandaag")).font(.largeTitle.weight(.bold))
            }
            Spacer()
            PlatformMenu()
            AccountButton()
        }
        .padding(.top, 8)
    }
}

/// Full-bleed hero card with the app's promo image.
struct TodayHeroCard: View {
    let app: StoreApp
    let eyebrow: String
    let title: String

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationLink(value: app) {
                PromoImage(url: app.imageURL, brandColor: app.brandColor)
                    .frame(height: 420)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(eyebrow.uppercased()).font(.subheadline.weight(.semibold)).opacity(0.85)
                            Text(title).font(.system(size: 28, weight: .bold)).lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 8)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                    }
            }
            .buttonStyle(CardPressStyle())

            HStack(spacing: 10) {
                NavigationLink(value: app) {
                    HStack(spacing: 10) {
                        StoreAppIcon(url: app.iconURL, brandColor: app.brandColor, name: app.name, size: 48, fallbackURL: app.smallImageURL)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.subheadline.weight(.semibold))
                            Text(app.description).font(.caption).opacity(0.8).lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                GetButton(appId: app.id, name: app.name)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
    }
}

/// "List" card with four apps, opening the full list.
struct TodayListCard: View {
    let eyebrow: String
    let title: String
    let apps: [StoreApp]
    let all: [StoreApp]
    var tint: String = "#0A84FF"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                AppListView(title: title, apps: all)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased()).font(.subheadline.weight(.semibold)).foregroundStyle(Color(hex: tint) ?? Theme.accent)
                    Text(title).font(.title2.weight(.bold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                AppRow(app: app, iconSize: 52)
                if i < apps.count - 1 { Divider().padding(.leading, 64) }
            }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Plain list of apps (from a card or "See all").
struct AppListView: View {
    let title: String
    let apps: [StoreApp]

    var body: some View {
        List(apps) { app in
            AppRow(app: app)
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
