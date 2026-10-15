import SwiftUI
import UIKit

// MARK: - Get / Installed button

/// The capsule button from the App Store ("Get" / "Open" / "Update"), wired to the
/// Homey you install to in the current store.
struct GetButton: View {
    let appId: String
    var name: String = ""
    var prominent = false

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @State private var showInstall = false
    @State private var showLogin = false
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 28
    @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 74

    private var target: HomeyRef? { library.target(for: store.platform, auth: auth) }
    private var installed: InstalledApp? { library.installedApp(appId, on: target) }
    private var state: HomeyLibrary.InstallState { library.state(appId, on: target) }
    private var detail: StoreAppDetail? { store.details[appId] }

    private var hasUpdate: Bool {
        guard let installed else { return false }
        return library.updateVersion(for: installed, detail: detail, on: target) != nil
    }

    private var minWidth: CGFloat { prominent ? width * 1.2 : width }
    private var minHeight: CGFloat { prominent ? height * 1.15 : height }
    private var labelFont: Font { prominent ? .subheadline.weight(.bold) : .footnote.weight(.bold) }

    var body: some View {
        Button {
            guard auth.isLoggedIn else { showLogin = true; return }
            showInstall = true
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel(accessibility)
        .sheet(isPresented: $showInstall) {
            InstallSheet(appId: appId)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginView(allowClose: true)
        }
    }

    private var isWorking: Bool { if case .working = state { return true }; return false }

    @ViewBuilder private var label: some View {
        if case .working = state {
            ProgressView()
                .controlSize(.small)
                .frame(width: minWidth, height: minHeight)
        } else if let installed, !hasUpdate {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                Text(installed.isTest ? "TEST" : (installed.version.isEmpty ? L("KLAAR") : installed.version))
            }
            .font(labelFont)
            .lineLimit(1)
            .foregroundStyle(installed.isTest ? Theme.testOrange : Theme.accent)
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .background(Theme.pill, in: Capsule())
        } else {
            Text(hasUpdate ? L("UPDATE") : L("INSTALLEER"))
                .font(labelFont)
                .foregroundStyle(prominent ? .white : Theme.accent)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: minWidth, minHeight: minHeight)
                .background(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.pill), in: Capsule())
        }
    }

    private var accessibility: String {
        if installed != nil { return hasUpdate ? L("Update \(name)") : L("\(name) is geïnstalleerd") }
        return L("Installeer \(name)")
    }
}

// MARK: - Rows & tiles

/// Standard App Store list row: icon, name, subtitle, Get button.
struct AppRow: View {
    let app: StoreApp
    var rank: Int? = nil
    var iconSize: CGFloat = 62

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: app) {
                HStack(spacing: 12) {
                    StoreAppIcon(url: app.iconURL, brandColor: app.brandColor, name: app.name, size: iconSize, fallbackURL: app.smallImageURL)
                    if let rank {
                        Text("\(rank)").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                            .frame(minWidth: 18)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                        Text(app.description.isEmpty ? app.authorName : app.description)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        if app.authorVerified {
                            Label(app.authorName, systemImage: "checkmark.seal.fill")
                                .font(.caption2).foregroundStyle(.secondary).labelStyle(VerifiedLabelStyle())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GetButton(appId: app.id, name: app.name)
        }
        .padding(.vertical, 6)
        .contextMenu {
            ShareLink(item: Config.storePage(app.id), preview: SharePreview(app.name, image: Image("StoreIcon"))) {
                Label(L("Deel"), systemImage: "square.and.arrow.up")
            }
            Link(destination: Config.storePage(app.id)) { Label(L("Bekijk op homey.app"), systemImage: "safari") }
            Button { UIPasteboard.general.string = app.id } label: { Label(L("Kopieer app-ID"), systemImage: "doc.on.doc") }
        } preview: {
            AppPeek(app: app)
        }
    }
}

/// Preview shown when long-pressing an app row.
struct AppPeek: View {
    let app: StoreApp

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PromoImage(url: app.imageURL, brandColor: app.brandColor).frame(width: 320, height: 200)
            HStack(spacing: 12) {
                StoreAppIcon(url: app.iconURL, brandColor: app.brandColor, name: app.name, size: 48, fallbackURL: app.smallImageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text(app.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(14)
        }
        .frame(width: 320)
    }
}

struct VerifiedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title.lineLimit(1)
            configuration.icon.foregroundStyle(Theme.accent).imageScale(.small)
        }
    }
}

/// Section title with an optional "See all" link, as on App Store shelves.
struct ShelfHeader<Destination: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.bottom, 10)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                Spacer()
                if Destination.self != EmptyView.self {
                    NavigationLink(destination: destination) {
                        Text(L("Bekijk alles")).font(.body)
                    }
                }
            }
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 20)
    }
}

extension ShelfHeader where Destination == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The 3-rows-per-page horizontal shelf used for app lists in the App Store.
struct AppShelf: View {
    let apps: [StoreApp]
    var rows = 3
    var ranked = false

    var body: some View {
        let columns = stride(from: 0, to: apps.count, by: rows).map { Array(apps[$0..<min($0 + rows, apps.count)]) }
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(Array(columns.enumerated()), id: \.offset) { col, group in
                    VStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { i, app in
                            AppRow(app: app, rank: ranked ? col * rows + i + 1 : nil)
                            if i < group.count - 1 { Divider().padding(.leading, 74) }
                        }
                        Spacer(minLength: 0)
                    }
                    .containerRelativeFrame(.horizontal) { w, _ in min(w - 56, 380) }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Big App Store "screenshot" card: the app's promo image with the app strip below.
struct FeatureCard: View {
    let app: StoreApp
    var eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(app.name).font(.title2)
            Text(app.description).font(.title3).foregroundStyle(.secondary).lineLimit(1)
            ZStack(alignment: .bottom) {
                NavigationLink(value: app) {
                    PromoImage(url: app.imageURL, brandColor: app.brandColor)
                        .frame(height: 220)
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    NavigationLink(value: app) {
                        HStack(spacing: 10) {
                            StoreAppIcon(url: app.iconURL, brandColor: app.brandColor, name: app.name, size: 44, fallbackURL: app.smallImageURL)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(app.authorName).font(.caption).foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    GetButton(appId: app.id, name: app.name)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Raster promo image (`imageLarge`) with a brand-colour fallback.
struct PromoImage: View {
    let url: URL?
    let brandColor: String

    var body: some View {
        Rectangle()
            .fill(Color(hex: brandColor)?.gradient ?? Theme.accent.gradient)
            .overlay {
                if let url {
                    RemoteImage(url: url, contentMode: .fill) { Color.clear }
                }
            }
            .clipped()
    }
}

// MARK: - Toolbar: store switch + account

/// "Homey Pro ▾" menu that switches between the Pro and Cloud store.
struct PlatformMenu: View {
    @Environment(StoreState.self) private var store
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Menu {
            Picker(L("Store"), selection: Binding(get: { store.platform }, set: { p in
                store.platform = p
                Task { await store.loadHighlights(auth: auth) }
            })) {
                ForEach(StorePlatform.allCases) { p in
                    Label { Text(p.title); Text(p.subtitle) } icon: { Image(systemName: p.icon) }.tag(p)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.platform.icon)
                Text(store.platform.title).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.pill, in: Capsule())
        }
        .accessibilityLabel(L("Wissel van store, nu \(store.platform.title)"))
    }
}

struct AccountAvatar: View {
    let url: URL?
    let initials: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Theme.homeyGradient)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Account avatar top-right, like the App Store. Opens the account sheet.
struct AccountButton: View {
    @Environment(AuthManager.self) private var auth
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            if auth.isLoggedIn {
                AccountAvatar(url: auth.avatarURL, initials: auth.active?.initials ?? "", size: 32)
                    .overlay(alignment: .bottomTrailing) {
                        if auth.accounts.count > 1 {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white, Theme.accent)
                                .offset(x: 3, y: 3)
                        }
                    }
            } else {
                Image(systemName: "person.crop.circle").font(.system(size: 26)).foregroundStyle(Theme.accent)
            }
        }
        .accessibilityLabel(L("Account"))
        .sheet(isPresented: $show) { AccountSheet() }
    }
}

extension View {
    /// Large title + store switch + account avatar, used on every tab.
    func storeToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { PlatformMenu() }
            ToolbarItem(placement: .topBarTrailing) { AccountButton() }
        }
    }

    /// Detail navigation for StoreApp values pushed from any list.
    func storeDestinations() -> some View {
        navigationDestination(for: StoreApp.self) { AppDetailView(app: $0) }
            .navigationDestination(for: StoreCategory.self) { CategoryAppsView(category: $0) }
    }
}
