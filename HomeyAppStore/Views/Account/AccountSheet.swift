import SwiftUI

/// Account page (App Store style): active account, quick switch between saved
/// accounts, add account, your Homeys, store choice, appearance and sign out.
struct AccountSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(StoreState.self) private var store
    @Environment(HomeyLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @AppStorage("store.skippedLogin") private var skippedLogin = false

    @State private var addAccount = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let active = auth.active {
                    Section {
                        HStack(spacing: 14) {
                            AccountAvatar(url: auth.avatarURL, initials: active.initials, size: 60)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(auth.displayName.isEmpty ? active.email : auth.displayName).font(.title3.weight(.semibold))
                                Text(auth.email).font(.subheadline).foregroundStyle(.secondary)
                                Text(active.methodLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        if active.needsLogin {
                            Label(L("Sessie verlopen – voeg dit account opnieuw toe."), systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }

                    if auth.accounts.count > 1 {
                        Section(L("Wissel van account")) {
                            ForEach(auth.otherAccounts) { acc in
                                Button {
                                    let id = acc.id
                                    dismiss()
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(400))
                                        auth.switchTo(id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        AccountAvatar(url: acc.avatarURL, initials: acc.initials, size: 36)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(acc.name.isEmpty ? acc.email : acc.name).foregroundStyle(.primary)
                                            Text(acc.email).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button(L("Afmelden"), role: .destructive) { auth.signOut(acc.id) }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { addAccount = true } label: {
                        Label(auth.isLoggedIn ? L("Account toevoegen") : L("Inloggen met Homey"), systemImage: "person.crop.circle.badge.plus")
                    }
                }

                if auth.isLoggedIn {
                    Section {
                        if auth.homeys.isEmpty {
                            Text(L("Geen Homeys gekoppeld")).foregroundStyle(.secondary)
                        }
                        ForEach(auth.homeys) { h in
                            let platform: StorePlatform = h.isCloud ? .cloud : .local
                            let isTarget = library.target(for: platform, auth: auth)?.id == h.id
                            Button {
                                library.setTarget(h, platform: platform, auth: auth)
                            } label: {
                                HomeyRow(homey: h, selected: isTarget)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(L("Mijn Homeys"))
                    } footer: {
                        Text(L("Het vinkje geeft aan op welke Homey de knop Installeer in de store werkt (één voor Homey Pro, één voor Homey Cloud)."))
                    }
                }

                Section(L("Store")) {
                    Picker(L("Store"), selection: Binding(get: { store.platform }, set: { p in
                        store.platform = p
                        Task { await store.loadHighlights(auth: auth) }
                    })) {
                        ForEach(StorePlatform.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L("Weergave"), selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    }
                }

                if auth.isLoggedIn {
                    Section {
                        Button(L("Afmelden"), role: .destructive) { confirmSignOut = true }
                    }
                } else {
                    Section {
                        Button(L("Toon het welkomstscherm")) {
                            // Close this sheet first; the screen under it is replaced.
                            dismiss()
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                skippedLogin = false
                            }
                        }
                    }
                }

                Section {
                    LabeledContent(L("Versie"), value: Config.appVersion)
                    LabeledContent(L("Build"), value: Config.appBuild)
                } footer: {
                    Text("© Homey Store – PixelForges. \(L("Niet officieel van Athom; app-gegevens komen uit de openbare Homey App Store."))")
                }
            }
            .navigationTitle(L("Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Klaar")) { dismiss() } } }
            .confirmationDialog(L("Afmelden bij \(auth.active?.email ?? "")?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(L("Afmelden"), role: .destructive) {
                    // Signing out of the last account replaces the whole screen: close the
                    // sheet first, then sign out (swapping the view tree under an open
                    // sheet is what crashed before).
                    let last = auth.accounts.count <= 1
                    if last {
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(550))
                            auth.logout()
                        }
                    } else {
                        auth.logout()
                    }
                }
            }
            .fullScreenCover(isPresented: $addAccount) {
                LoginView(isAddingAccount: auth.isLoggedIn, allowClose: true, onAdded: { dismiss() })
            }
            .task { if auth.isLoggedIn && auth.user.isNull { try? await auth.loadUser() } }
        }
    }
}
