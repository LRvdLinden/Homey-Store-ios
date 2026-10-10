import SwiftUI
import UIKit

/// App Store look: system grouped backgrounds, SF typography, blue accent,
/// grey capsule "Get" buttons — with Homey's blue as the accent.
enum Theme {
    static let accent = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let pill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)
    static let testOrange = Color(light: 0xF57C00, dark: 0xFF9F0A)

    static let homeyGradient = LinearGradient(
        colors: [Color(hex: "#005CD5")!, Color(hex: "#52DEFF")!],
        startPoint: .bottomLeading, endPoint: .topTrailing
    )
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// System / Light / Dark — chosen under Account, default follows the device.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: L("Automatisch"); case .light: L("Licht"); case .dark: L("Donker") }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// The Homey ring (colour or white glyph), optionally spinning.
struct HomeyLogo: View {
    var size: CGFloat = 40
    var spinning = false
    var asset = "HomeyLogo"
    var secondsPerTurn: Double = 1.4

    var body: some View {
        if spinning {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                image.rotationEffect(.degrees(t.truncatingRemainder(dividingBy: secondsPerTurn) / secondsPerTurn * 360))
            }
        } else {
            image
        }
    }

    private var image: some View {
        Image(asset).resizable().scaledToFit().frame(width: size, height: size).accessibilityLabel("Homey")
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button(L("Opnieuw"), action: retry).font(.footnote.weight(.semibold)) }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
