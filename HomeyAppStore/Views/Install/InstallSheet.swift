import SwiftUI

/// Install confirmation sheet (like the App Store purchase sheet): pick the Homey,
/// pick Live or Test, install — with progress and the result.
struct InstallSheet: View {
    let appId: String
    var preferred: InstallChannel? = nil

    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var channel: InstallChannel = .live
    @State private var homeyID: String?
    @State private var confirmRemove = false

    private var detail: StoreAppDetail? { store.details[appId] }

    /// All Homeys of the account; the ones of the other platform are shown greyed out.
    private var homeys: [HomeyRef] { auth.homeys }
    private var homey: HomeyRef? { homeys.first { $0.id == homeyID } }
    private var installed: InstalledApp? { library.installedApp(appId, on: homey) }
    private var state: HomeyLibrary.InstallState { library.state(appId, on: homey) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    appHeader

                    if let detail, detail.hasTest {
                        Picker(L("Versie"), selection: $channel) {
                            Text("Live \(detail.liveVersion)").tag(InstallChannel.live)
                                .disabled(!detail.hasLive)
                            Text("Test \(detail.testVersion)").tag(InstallChannel.test)
                        }
                        .pickerStyle(.segmented)
                        if channel == .test {
                            Label(L("Testversies zijn nog niet gecertificeerd en kunnen fouten bevatten."), systemImage: "flask")
                                .font(.footnote).foregroundStyle(Theme.testOrange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    homeyPicker

                    statusView

                    actionButton

                    if installed != nil, !isWorking {
                        Button(L("Verwijder van deze Homey"), role: .destructive) { confirmRemove = true }
                            .font(.subheadline)
                    }
                }
                .padding(20)
            }
            .navigationTitle(L("Installeren"))
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
        .task {
            if let preferred { channel = preferred }
            if homeyID == nil {
                homeyID = library.target(for: store.platform, auth: auth)?.id
                    ?? homeys.first(where: { detail?.supports($0.isCloud ? .cloud : .local) ?? true })?.id
            }
            let d = await store.detail(appId, auth: auth)
            if let d, !d.hasLive { channel = .test }
            if let homey { await library.refresh(homey, auth: auth) }
        }
        .onChange(of: homeyID) { _, _ in
            if let homey { Task { await library.refresh(homey, auth: auth) } }
        }
    }

    private var isWorking: Bool { if case .working = state { return true }; return false }

    // MARK: Parts

    private var appHeader: some View {
        HStack(spacing: 14) {
            StoreAppIcon(url: detail?.primaryBuild?.iconURL, brandColor: detail?.primaryBuild?.brandColor ?? "",
                         name: detail?.name ?? appId, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(detail?.name ?? appId).font(.headline)
                Text(detail?.authorName ?? "").font(.subheadline).foregroundStyle(.secondary)
                if let detail {
                    Text(channel == .test ? "\(L("Testversie")) \(detail.testVersion)" : "\(L("Versie")) \(detail.liveVersion)")
                        .font(.caption).foregroundStyle(channel == .test ? Theme.testOrange : .secondary)
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
                        let compatible = detail?.supports(h.isCloud ? .cloud : .local) ?? true
                        Button { homeyID = h.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: h.isCloud ? "cloud.fill" : "cube.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(h.isCloud ? Color.cyan : Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(h.name).foregroundStyle(.primary)
                                    Text(compatible ? h.subtitle : L("Deze app werkt niet op \(h.isCloud ? "Homey Cloud" : "Homey Pro")"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let app = library.installedApp(appId, on: h) {
                                    Text(app.isTest ? "TEST \(app.version)" : app.version)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(app.isTest ? Theme.testOrange : .secondary)
                                }
                                Image(systemName: h.id == homeyID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(h.id == homeyID ? Theme.accent : Color.secondary)
                                    .font(.title3)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!compatible || isWorking)
                        .opacity(compatible ? 1 : 0.45)
                        if h.id != homeys.last?.id { Divider().padding(.leading, 58) }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let homey, let err = library.errors[homey.id] {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch state {
        case .working(let ch):
            HStack(spacing: 10) {
                ProgressView()
                Text(ch == nil ? L("Verwijderen…") : L("Installeren op \(homey?.name ?? "Homey")…"))
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

    private var actionTitle: String {
        guard let installed, let detail else { return channel == .test ? L("Installeer testversie") : L("Installeer") }
        let target = channel == .test ? detail.testVersion : detail.liveVersion
        if installed.version == target && installed.isTest == (channel == .test) { return L("Opnieuw installeren") }
        if channel == .test && !installed.isTest { return L("Wissel naar testversie") }
        if channel == .live && installed.isTest { return L("Wissel naar live-versie") }
        return L("Update naar \(target)")
    }

    private var actionButton: some View {
        Button {
            guard let homey else { return }
            Task { await library.install(appId, channel: channel, on: homey, auth: auth) }
        } label: {
            Text(actionTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(channel == .test ? Theme.testOrange : Theme.accent)
        .disabled(homey == nil || isWorking || detail == nil)
    }
}
