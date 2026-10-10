import SwiftUI

/// Store brand colours, taken from the Homey App Store header on homey.app
/// (60° gradient per platform).
extension StorePlatform {
    var gradientColors: [Color] {
        switch self {
        case .local: [Color(hex: "#005CD5")!, Color(hex: "#52DEFF")!]
        case .cloud: [Color(hex: "#C70076")!, Color(hex: "#FC6767")!]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// Platform the store was last opened on (readable before StoreState exists).
    static var saved: StorePlatform {
        StorePlatform(rawValue: UserDefaults.standard.string(forKey: "store.platform") ?? "") ?? .local
    }
}

// MARK: - Frosted shapes

/// Triangle with rounded corners (the "glass" triangle from the store header).
struct RoundedTriangle: Shape {
    var radius: CGFloat = 0.18

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * radius
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        var p = Path()
        p.move(to: CGPoint(x: (left.x + right.x) / 2, y: rect.maxY))
        p.addArc(tangent1End: right, tangent2End: top, radius: r)
        p.addArc(tangent1End: top, tangent2End: left, radius: r)
        p.addArc(tangent1End: left, tangent2End: right, radius: r)
        p.closeSubpath()
        return p
    }
}

enum GlassKind { case triangle, circle, square }

/// White frosted glass shape: translucent white fill with a bright top edge.
struct GlassShape: View {
    let kind: GlassKind
    var size: CGFloat
    var opacity: Double = 1

    var body: some View {
        shape
            .frame(width: size, height: kind == .triangle ? size * 0.9 : size)
            .opacity(opacity)
            .shadow(color: Color(red: 0, green: 0.15, blue: 0.42).opacity(0.25), radius: size * 0.09, y: size * 0.07)
    }

    private var fill: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.42)], startPoint: .topTrailing, endPoint: .bottomLeading)
    }

    private var edge: LinearGradient {
        LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .topTrailing, endPoint: .bottomLeading)
    }

    @ViewBuilder private var shape: some View {
        switch kind {
        case .triangle:
            RoundedTriangle().fill(fill).overlay(RoundedTriangle().stroke(edge, lineWidth: max(1, size * 0.02)))
        case .circle:
            Circle().fill(fill).overlay(Circle().strokeBorder(edge, lineWidth: max(1, size * 0.02)))
        case .square:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(edge, lineWidth: max(1, size * 0.02)))
        }
    }
}

/// The app's mark: triangle, circle and rounded square (same as the app icon).
struct StoreMark: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            GlassShape(kind: .triangle, size: size * 0.40).rotationEffect(.degrees(-12))
                .offset(x: -size * 0.19, y: -size * 0.19)
            GlassShape(kind: .circle, size: size * 0.37)
                .offset(x: size * 0.19, y: -size * 0.19)
            GlassShape(kind: .square, size: size * 0.37).rotationEffect(.degrees(8))
                .offset(y: size * 0.20)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// App icon tile (gradient + mark), used on the login screen.
struct StoreLogoTile: View {
    var size: CGFloat = 60

    var body: some View {
        Image("StoreIcon")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Backdrop

/// Gradient with large frosted shapes drifting slowly, like the header of the
/// Homey App Store on homey.app.
struct StoreBackdrop: View {
    var platform: StorePlatform = .local
    var animated = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            TimelineView(.animation(paused: !animated)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    platform.gradient
                    RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: max(w, h) * 0.8)

                    GlassShape(kind: .triangle, size: w * 0.52, opacity: 0.32)
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 120) / 120 * 360))
                        .position(x: w * 0.05, y: h * 0.16)
                    GlassShape(kind: .square, size: w * 0.44, opacity: 0.30)
                        .rotationEffect(.degrees(8 + sin(t / 2.4) * 6))
                        .position(x: w * 0.98, y: h * 0.30 + sin(t / 2.4) * 14)
                    GlassShape(kind: .circle, size: w * 0.40, opacity: 0.26)
                        .position(x: w * 0.30 + cos(t / 1.6) * 10, y: h * 0.68 + sin(t / 1.6) * 16)
                }
                .frame(width: w, height: h)
            }
        }
        .ignoresSafeArea()
    }
}

/// Soft curved edge, like the bottom of the store header on homey.app.
struct CurveTop: Shape {
    var depth: CGFloat = 36

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + depth), control: CGPoint(x: rect.midX, y: rect.minY - depth))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
