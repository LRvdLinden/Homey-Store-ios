import SwiftUI

/// Install confirmation sheet (like the App Store purchase sheet): pick the Homey,
/// pick Live or Test, install — with progress and the result. With `version` set it
/// installs that exact (older) version instead (Homey Pro only).
struct InstallSheet: View {
    let appId: String
    var preferred: InstallChannel? = nil
    var version: String? = nil

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var channel: InstallChannel = .live
    @State private var homeyID: String?
    @State private var confirmRemove = false
    @State private var didSetup = false

    private var detail: StoreAppDetail? { store.details[appId] }

    /// All Homeys of the account; ones that can't take this app are shown greyed out.
    private var homeys: [HomeyRef] { auth.homeys }
    private var homey: HomeyRef? { homeys.first { $0.id == homeyID } }
    private var installed: InstalledApp? { library.installedApp(appId, on: homey) }
    private var state: HomeyLibrary.InstallState { library.state(appId, on: homey) }
    private var isRollback: Bool { !(version ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appHeader

                    if isRollback {
                        Label(L("Je installeert een oudere versie. Zet automatisch bijwerken uit als je deze versie wilt houden."),
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let detail, detail.hasLive, detail.hasTest {
                        Picker(L("Versie"), selection: $channel) {
                            Text("Live \(detail.liveVersion)").tag(InstallChannel.live)
                            Text("Test \(detail.testVersion)").tag(InstallChannel.test)
                        }
                        .pickerStyle(.segmented)
                    }
                    if !isRollback, channel == .test {
                        Label(L("Testversies zijn nog niet gecertificeerd en kunnen fouten bevatten."), systemImage: "flask")
                            .font(.footnote).foregroundStyle(Theme.testOrange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    homeyPicker

                    permissionsNotice

                    statusView

                    actionButton

                    if installed != nil, !isWorking, homey?.canInstall == true {
                        Button(L("Verwijder van deze Homey"), role: .destructive) { confirmRemove = true }
                            .font(.subheadline)
                    }
                }
                .padding(20)
                .readableWidth(560)
            }
            .navigationTitle(isRollback ? L("Versie \(version ?? "") installeren") : L("Installeren"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Sluit")) { dismiss() } }
            }
            .confirmationDialog(L("App verwijderen?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(L("Verwijder"), role: .destructive) {
                    guard let homey else { return }
                    Task { await library.uninstall(appId, on: homey, auth: auth) }
                }
            } message: {
                Text(L("De app, zijn apparaten en Flows die de app gebruiken verdwijnen van \(homey?.name ?? "Homey")."))
            }
        }
        .sensoryFeedback(trigger: state) { _, new in
            switch new {
            case .done: return .success
            case .failed: return .error
            default: return nil
            }
        }
        .task {
            guard !didSetup else { return }
            didSetup = true
            if let homey = library.target(for: store.platform, auth: auth) {
                library.clearState(appId, on: homey)
            }
            homeyID = library.target(for: store.platform, auth: auth)?.id
            applyDefaults()
            await store.detail(appId, auth: auth)
            // With the details known: make sure the chosen Homey can take the app.
            pickCompatibleHomey()
            applyDefaults()
            if let homey { await library.refresh(homey, auth: auth) }
            applyDefaults()
        }
        .onChange(of: homeyID) { _, _ in
            guard let homey else { return }
            library.clearState(appId, on: homey)
            Task {
                await library.refresh(homey, auth: auth)
                applyDefaults()
            }
        }
    }

    private var isWorking: Bool { if case .working = state { return true }; return false }

    private func isCompatible(_ h: HomeyRef) -> Bool {
        if isRollback && h.isCloud { return false }   // a specific version can only go to Homey Pro
        return detail?.supports(h.isCloud ? .cloud : .local) ?? true
    }

    private func pickCompatibleHomey() {
        if let homey, isCompatible(homey), homey.canInstall { return }
        homeyID = homeys.first { isCompatible($0) && $0.canInstall }?.id ?? homeys.first(where: isCompatible)?.id ?? homeyID
    }

    /// Start on the channel the app runs on now (so "✓ TEST" opens on Test), unless the
    /// sheet was opened for a specific channel; test-only apps always use Test.
    private func applyDefaults() {
        if let detail, !detail.hasLive { channel = .test; return }
        if let preferred { channel = preferred; return }
        if let installed { channel = installed.installedChannel }
    }

    // MARK: Parts

    private var targetVersion: String {
        if let version, !version.isEmpty { return version }
        // Homey itself knows best which update is ready for this app (Homey Pro).
        if let installed, installed.installedChannel == channel, let v = installed.updateVersion, homey?.isCloud == false {
            return v
        }
        guard let detail else { return "" }
        return channel == .test ? detail.testVersion : detail.liveVersion
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            StoreAppIcon(url: detail?.primaryBuild?.iconURL, brandColor: detail?.primaryBuild?.brandColor ?? "",
                         name: detail?.name ?? appId, size: 64, fallbackURL: detail?.primaryBuild?.imageSmallURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(detail?.name ?? appId).font(.headline)
                Text(detail?.authorName ?? "").font(.subheadline).foregroundStyle(.secondary)
                if detail != nil {
                    Text(channel == .test && !isRollback ? "\(L("Testversie")) \(targetVersion)" : "\(L("Versie")) \(targetVersion)")
                        .font(.caption).foregroundStyle(channel == .test && !isRollback ? Theme.testOrange : .secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var homeyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("INSTALLEER OP")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if homeys.isEmpty {
                Text(L("Er zijn geen Homeys gekoppeld aan dit account."))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(homeys) { h in
                        let compatible = isCompatible(h)
                        let usable = compatible && h.canInstall
                        let installed = library.installedApp(appId, on: h)
                        Button { homeyID = h.id } label: {
                            HomeyRow(homey: h, selected: h.id == homeyID,
                                     trailing: installed.map { $0.isTest ? "TEST \($0.version)" : $0.version },
                                     trailingTint: installed?.isTest == true ? Theme.testOrange : .secondary,
                                     subtitleOverride: subtitle(for: h, compatible: compatible))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!usable || isWorking)
                        .opacity(usable ? 1 : 0.45)
                        if h.id != homeys.last?.id { Divider().padding(.leading, 84) }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let homey, let err = library.errors[homey.id] {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func subtitle(for h: HomeyRef, compatible: Bool) -> String? {
        if isRollback && h.isCloud { return L("Een oudere versie kan alleen op Homey Pro") }
        if !compatible { return L("Deze app werkt niet op \(h.isCloud ? "Homey Cloud" : "Homey Pro")") }
        if !h.canInstall { return L("Alleen de eigenaar of een beheerder kan apps installeren") }
        return nil
    }

    /// New permissions the update asks for (reported by Homey Pro).
    @ViewBuilder private var permissionsNotice: some View {
        if let installed, !installed.updatePermissions.isEmpty, channel == installed.installedChannel, !isRollback {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("Deze update vraagt nieuwe rechten"), systemImage: "lock.shield").font(.subheadline.weight(.semibold))
                ForEach(installed.updatePermissions, id: \.self) {
                    Text("• " + $0.replacingOccurrences(of: "homey:", with: "")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder private var statusView: some View {
        switch state {
        case .working(let ch):
            HStack(spacing: 10) {
                ProgressView()
                Text(ch == nil ? L("Bezig…") : L("Installeren op \(homey?.name ?? "Homey")…"))
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        case .done:
            Label(L("Geïnstalleerd op \(homey?.name ?? "Homey")"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        case .failed(let message):
            ErrorBanner(message: message)
        case .idle:
            EmptyView()
        }
    }

    /// Homey Cloud keeps its apps up to date by itself; there's nothing to do on the same channel.
    private var cloudSelfUpdates: Bool {
        guard let homey, homey.isCloud, let installed, !isRollback else { return false }
        return installed.installedChannel == channel
    }

    private var actionTitle: String {
        if isRollback { return L("Installeer versie \(targetVersion)") }
        if cloudSelfUpdates { return L("Homey Cloud werkt deze app zelf bij") }
        guard let installed, detail != nil else { return channel == .test ? L("Installeer testversie") : L("Installeer") }
        if installed.version == targetVersion && installed.installedChannel == channel { return L("Opnieuw installeren") }
        if channel == .test && !installed.isTest { return L("Wissel naar testversie") }
        if channel == .live && installed.isTest { return L("Wissel naar live-versie") }
        return L("Update naar \(targetVersion)")
    }

    private var canAct: Bool {
        guard let homey, detail != nil, !isWorking else { return false }
        return isCompatible(homey) && homey.canInstall && !targetVersion.isEmpty && !cloudSelfUpdates
    }

    private var actionButton: some View {
        Button {
            guard let homey else { return }
            let ch = isRollback ? (installed?.installedChannel ?? .live) : channel
            Task {
                await library.install(appId, channel: ch, version: isRollback ? version : nil,
                                      expectedVersion: targetVersion, on: homey, auth: auth)
            }
        } label: {
            Text(actionTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(channel == .test && !isRollback ? Theme.testOrange : Theme.accent)
        .disabled(!canAct)
    }
}
