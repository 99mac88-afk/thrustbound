import SwiftUI

extension Color {
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}

enum UIStyle {
    static let bgTop = Color(hex: "#040714")
    static let bgBottom = Color(hex: "#0C1A3A")
    static let card = Color(hex: "#0B1328")
    static let cyan = Color(hex: "#3BE3FF")
    static let gold = Color(hex: "#FFE14D")
    static let green = Color(hex: "#44FF88")
    static let red = Color(hex: "#FF2E4D")
    static let orange = Color(hex: "#FFB020")

    static func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func accent(for world: WorldInfo?) -> Color {
        Color(hex: world?.neon ?? "#3BE3FF")
    }

    static func time(_ t: Double) -> String {
        String(format: "%.1fs", max(0, t))
    }
}

/// Slowly drifting star field used behind the menus.
struct StarfieldBackground: View {
    var top: Color = UIStyle.bgTop
    var bottom: Color = UIStyle.bgBottom

    private struct Star {
        let x: Double
        let y: Double
        let r: Double
        let speed: Double
        let alpha: Double
    }

    private static let stars: [Star] = {
        var rng = SeededRandom(seed: 3)
        return (0..<150).map { _ in
            Star(x: rng.next(in: 0...1), y: rng.next(in: 0...1), r: rng.next(in: 0.5...1.9),
                 speed: rng.next(in: 0.008...0.05), alpha: rng.next(in: 0.25...0.95))
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { gc, size in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                gc.fill(Path(CGRect(origin: .zero, size: size)),
                        with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero,
                                              endPoint: CGPoint(x: 0, y: size.height)))
                for s in Self.stars {
                    let y = (s.y + t * s.speed).truncatingRemainder(dividingBy: 1)
                    let p = CGPoint(x: s.x * size.width, y: y * size.height)
                    let rect = CGRect(x: p.x - s.r, y: p.y - s.r, width: s.r * 2, height: s.r * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(s.alpha)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The rocket drawn with the same vector art as the game.
struct RocketGlyph: View {
    var flame = true

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { gc, size in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                let s = size.height / 64
                gc.translateBy(x: size.width / 2, y: size.height / 2 - 9.5 * s)
                gc.scaleBy(x: s, y: -s)
                if flame {
                    var f = gc
                    f.translateBy(x: 0, y: -15)
                    f.scaleBy(x: 1, y: CGFloat(1 + 0.18 * sin(t * 31) + 0.08 * sin(t * 53)))
                    f.fill(Path(RocketArt.flame(length: 24, width: 10)), with: .color(Color(hex: "#FF7A2E")))
                    f.fill(Path(RocketArt.flame(length: 13, width: 6)), with: .color(Color(hex: "#FFF4B0")))
                }
                let red = Color(Palette.rocketRed)
                gc.fill(Path(RocketArt.fins), with: .color(red))
                gc.fill(Path(RocketArt.nozzle), with: .color(Color(Palette.metal)))
                gc.fill(Path(RocketArt.hull), with: .color(Color(Palette.hull)))
                gc.stroke(Path(RocketArt.hull), with: .color(Color(Palette.hullShade)), lineWidth: 1)
                gc.fill(Path(RocketArt.stripe), with: .color(red))
                gc.fill(Path(RocketArt.nose), with: .color(red))
                gc.fill(Path(RocketArt.window), with: .color(Color(Palette.window)))
                gc.stroke(Path(RocketArt.window), with: .color(.white), lineWidth: 1)
            }
        }
    }
}

struct StarRow: View {
    let filled: Int
    var total = 3
    var size: CGFloat = 18
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundColor(i < filled ? UIStyle.gold : Color.white.opacity(0.28))
                    .shadow(color: i < filled ? UIStyle.gold.opacity(0.6) : .clear, radius: 6)
            }
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ActionButton: View {
    enum Kind {
        case primary
        case secondary
    }

    let title: String
    var icon: String?
    var kind: Kind = .secondary
    var accent: Color = UIStyle.cyan
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button {
            SoundManager.shared.play(.click, volume: 0.6)
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 17, weight: .bold))
                }
                Text(title).font(UIStyle.font(18))
            }
            .foregroundColor(kind == .primary ? Color.black.opacity(0.85) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(kind == .primary
                          ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(kind == .primary ? Color.white.opacity(0.5) : accent.opacity(0.45), lineWidth: 1.5)
            )
            .shadow(color: kind == .primary ? accent.opacity(0.55) : .clear, radius: 14)
        }
        .buttonStyle(PressableStyle())
    }
}

struct IconButton: View {
    let icon: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button {
            SoundManager.shared.play(.click, volume: 0.6)
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct ScreenHeader: View {
    let title: String
    var trailing: String?
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconButton(icon: "chevron.left", action: back)
            Text(title)
                .font(UIStyle.font(24))
                .foregroundColor(.white)
            Spacer()
            if let trailing = trailing {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").foregroundColor(UIStyle.gold)
                    Text(trailing).font(UIStyle.font(16, .bold)).foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// Hides the home indicator and keeps bottom-edge swipes from stealing the controls (iOS 16+).
struct GameSystemOverlays: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .bottom)
        } else {
            content
        }
    }
}
