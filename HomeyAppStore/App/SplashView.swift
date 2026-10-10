import SwiftUI

/// Launch splash: the blueprint background of the launch screen, the app tile
/// pops in, the Homey ring spins up, then the name and version fade in.
struct SplashView: View {
    @State private var tileIn = false
    @State private var textIn = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            BlueprintBackground().ignoresSafeArea()

            // Soft glow behind the tile
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .scaleEffect(pulse ? 1.12 : 0.9)

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Theme.homeyGradient)
                        .frame(width: 150, height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        )
                    HomeyLogo(size: 92, spinning: true, asset: "HomeyGlyph", secondsPerTurn: 1.3)
                }
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
                .scaleEffect(tileIn ? 1 : 0.6)
                .opacity(tileIn ? 1 : 0)

                VStack(spacing: 6) {
                    Text("Homey Store")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Apps voor Homey Pro en Homey Cloud")
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 10)
            }

            VStack {
                Spacer()
                Text("Versie \(Config.appVersion) (\(Config.appBuild))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
                    .opacity(textIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { tileIn = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) { textIn = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

#Preview { SplashView() }
