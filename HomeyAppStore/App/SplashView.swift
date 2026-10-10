import SwiftUI

/// Launch splash in the style of the Homey App Store header on homey.app:
/// the platform gradient with frosted shapes drifting, the app mark settles,
/// the title appears and a light curved panel rises with the store pill.
struct SplashView: View {
    private let platform = StorePlatform.saved

    @State private var spread = false
    @State private var textIn = false
    @State private var panelIn = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StoreBackdrop(platform: platform)

                VStack(spacing: 26) {
                    Spacer()
                    // The launch screen shows the mark at 180 pt in the centre;
                    // it starts there and gently lifts.
                    StoreMark(size: 180)
                        .scaleEffect(spread ? 0.84 : 1)
                        .rotationEffect(.degrees(spread ? -4 : 0))
                        .offset(y: spread ? -40 : 0)

                    VStack(spacing: 8) {
                        Text("Homey Store")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Apps voor je slimme huis")
                            .font(.title3.weight(.medium))
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? -40 : -24)
                    Spacer()
                    Spacer().frame(height: geo.size.height * 0.20)
                }

                // Light curved panel with the store choice, as on homey.app/apps.
                VStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .top) {
                        CurveTop(depth: 34)
                            .fill(Theme.groupedBackground)
                        VStack(spacing: 18) {
                            HStack(spacing: 8) {
                                Image(systemName: platform.icon)
                                Text(platform.title).fontWeight(.semibold)
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Theme.card, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                            .offset(y: -22)

                            ProgressView().tint(.secondary)

                            Text("Versie \(Config.appVersion) (\(Config.appBuild))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: geo.size.height * 0.24)
                    .offset(y: panelIn ? 0 : geo.size.height * 0.3)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.1)) { spread = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) { textIn = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.45)) { panelIn = true }
        }
    }
}

#Preview { SplashView() }
