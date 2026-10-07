import SpriteKit
import SwiftUI

/// Hosts the SpriteKit view with multi-touch enabled (SwiftUI's SpriteView does not allow that).
struct GameSceneView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        view.backgroundColor = .black
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: ()) {
        uiView.presentScene(nil)
    }
}

struct GameView: View {
    @StateObject private var session: GameSession
    @Environment(\.scenePhase) private var scenePhase

    init(app: AppModel, levelIndex: Int, custom: CustomPlay? = nil) {
        _session = StateObject(wrappedValue: GameSession(app: app, levelIndex: levelIndex, custom: custom))
    }

    private var accent: Color { UIStyle.accent(for: session.worldInfo) }

    var body: some View {
        ZStack {
            GameSceneView(scene: session.scene)
                .ignoresSafeArea()

            HUDView(session: session, hud: session.hud, accent: accent)

            if session.showIntro && session.phase == .playing {
                IntroBanner(tag: session.levelTag, name: session.levelName,
                            hint: session.levelHint, accent: accent)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            overlay
        }
        .modifier(GameSystemOverlays())
        .onChange(of: scenePhase) { phase in
            if phase != .active { session.pause() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.phase {
        case .playing:
            EmptyView()
        case .paused:
            PauseOverlay(session: session, accent: accent)
        case .crashed:
            FailOverlay(session: session, accent: accent, outOfFuel: false)
        case .outOfFuel:
            FailOverlay(session: session, accent: accent, outOfFuel: true)
        case .won:
            if let result = session.result {
                WinOverlay(session: session, result: result, accent: accent)
            }
        }
    }
}

// MARK: - HUD

struct HUDView: View {
    let session: GameSession
    @ObservedObject var hud: HUDModel
    let accent: Color

    var body: some View {
        let s = hud.state
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                IconButton(icon: "pause.fill", size: 42) { session.pause() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.levelTag)
                        .font(UIStyle.font(11, .bold))
                        .tracking(1.5)
                        .foregroundColor(accent)
                    Text(session.levelName)
                        .font(UIStyle.font(17))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                if session.starTotal > 0 {
                    StarRow(filled: s.stars, total: session.starTotal, size: 20)
                }
            }
            HStack(spacing: 10) {
                FuelGauge(fraction: s.fuel)
                SpeedGauge(ratio: s.speedRatio)
                Text(session.s.time(s.elapsed))
                    .font(UIStyle.font(14, .bold).monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62, alignment: .trailing)
            }
            HStack(spacing: 8) {
                ForEach(Array(s.keys.enumerated()), id: \.offset) { _, color in
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(Palette.key(color)))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                Spacer()
                if s.tilted {
                    StatusPill(text: session.s.levelOut, color: UIStyle.gold)
                } else if s.landing > 0.02 {
                    StatusPill(text: session.s.touchdown(Int(s.landing * 100)), color: UIStyle.green)
                }
            }
            .frame(minHeight: 28)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(UIStyle.font(12, .heavy))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.6), radius: 8)
    }
}

struct FuelGauge: View {
    let fraction: Double

    private var color: Color {
        if fraction > 0.5 { return UIStyle.green }
        if fraction > 0.2 { return UIStyle.gold }
        return UIStyle.red
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                        .shadow(color: color.opacity(0.7), radius: 5)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shows how fast the rocket is moving compared to the crash limit.
struct SpeedGauge: View {
    let ratio: Double
    let span: Double = 1.5

    private var color: Color {
        if ratio < 0.75 { return UIStyle.green }
        if ratio < 1 { return UIStyle.gold }
        return UIStyle.red
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "speedometer")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: 58 * CGFloat(max(0.04, min(1, ratio / span))))
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: 14)
                    .offset(x: 58 / CGFloat(span) - 1)
            }
            .frame(width: 58, height: 10)
        }
    }
}

struct IntroBanner: View {
    let tag: String
    let name: String
    let hint: String
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(tag)
                .font(UIStyle.font(14, .bold))
                .tracking(3)
                .foregroundColor(accent)
            Text(name.uppercased())
                .font(UIStyle.font(32, .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 20)
                .shadow(color: accent.opacity(0.8), radius: 12)
            Text(hint)
                .font(UIStyle.font(15, .semibold))
                .foregroundColor(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.6), Color.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .offset(y: -70)
    }
}

// MARK: - Overlays

struct OverlayCard<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                content
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(UIStyle.card.opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(accent.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(color: accent.opacity(0.35), radius: 30)
            .padding(.horizontal, 22)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}

struct PauseOverlay: View {
    @EnvironmentObject var app: AppModel
    let session: GameSession
    let accent: Color

    var body: some View {
        OverlayCard(accent: accent) {
            Text(session.s.paused)
                .font(UIStyle.font(30, .black))
                .foregroundColor(.white)
            Text(session.custom == nil ? session.s.levelLine(session.levelLabel, session.levelName) : session.levelName)
                .font(UIStyle.font(15, .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            Text(session.levelHint)
                .font(UIStyle.font(14, .medium))
                .foregroundColor(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: session.s.resume, icon: "play.fill", kind: .primary, accent: accent) { session.resume() }
            ActionButton(title: session.s.restart, icon: "arrow.counterclockwise", accent: accent) { session.restart() }
            HStack(spacing: 12) {
                ActionButton(title: session.backTitle, icon: session.backIcon, accent: accent) { session.quitToLevels() }
                ActionButton(title: session.s.menu, icon: "house.fill", accent: accent) { session.quitToMenu() }
            }
            HStack(spacing: 22) {
                ToggleChip(icon: app.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: session.s.sound, on: app.soundOn) {
                    app.soundOn.toggle()
                }
                ToggleChip(icon: "iphone.radiowaves.left.and.right", label: session.s.haptics, on: app.hapticsOn) {
                    app.hapticsOn.toggle()
                }
            }
            .padding(.top, 4)
        }
    }
}

struct ToggleChip: View {
    let icon: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(UIStyle.font(13, .bold))
            .foregroundColor(on ? .white : Color.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(on ? 0.14 : 0.05)))
        }
        .buttonStyle(PressableStyle())
    }
}

struct FailOverlay: View {
    let session: GameSession
    let accent: Color
    let outOfFuel: Bool

    var body: some View {
        OverlayCard(accent: accent) {
            Image(systemName: outOfFuel ? "fuelpump.fill" : "flame.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(outOfFuel ? UIStyle.orange : UIStyle.red)
                .shadow(color: (outOfFuel ? UIStyle.orange : UIStyle.red).opacity(0.7), radius: 12)
            Text(outOfFuel ? session.s.outOfFuel : session.s.crashed)
                .font(UIStyle.font(32, .black))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(tip)
                .font(UIStyle.font(15, .semibold))
                .foregroundColor(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.s.attempt(session.attempts))
                .font(UIStyle.font(12, .bold))
                .foregroundColor(Color.white.opacity(0.4))
            ActionButton(title: session.s.tryAgain, icon: "arrow.counterclockwise", kind: .primary, accent: accent) { session.restart() }
            HStack(spacing: 12) {
                ActionButton(title: session.backTitle, icon: session.backIcon, accent: accent) { session.quitToLevels() }
                ActionButton(title: session.s.menu, icon: "house.fill", accent: accent) { session.quitToMenu() }
            }
        }
    }

    private var tip: String {
        let tips = outOfFuel ? session.s.fuelTips : session.s.crashTips
        return tips[(session.attempts - 1 + session.levelIndex) % tips.count]
    }
}

struct WinOverlay: View {
    @EnvironmentObject var app: AppModel
    let session: GameSession
    let result: LevelResult
    let accent: Color
    @State var shown = false

    private var perfect: Bool { session.starTotal > 0 && result.stars >= session.starTotal }

    var body: some View {
        OverlayCard(accent: accent) {
            Text(perfect ? session.s.perfect : session.s.landed)
                .font(UIStyle.font(34, .black))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: UIStyle.green.opacity(0.8), radius: 14)
            if session.starTotal > 0 {
                HStack(spacing: 14) {
                    ForEach(0..<session.starTotal, id: \.self) { i in
                        let middle = session.starTotal == 3 && i == 1
                        Image(systemName: i < result.stars ? "star.fill" : "star")
                            .font(.system(size: middle ? 50 : 40, weight: .bold))
                            .foregroundColor(i < result.stars ? UIStyle.gold : Color.white.opacity(0.25))
                            .shadow(color: i < result.stars ? UIStyle.gold.opacity(0.8) : .clear, radius: 12)
                            .offset(y: middle ? -8 : 0)
                            .scaleEffect(shown ? 1 : 0.2)
                            .opacity(shown ? 1 : 0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.15 + 0.18 * Double(i)), value: shown)
                    }
                }
                .padding(.vertical, 4)
            }

            VStack(spacing: 8) {
                statRow(icon: "timer", label: session.s.timeLabel, value: session.s.time(result.time),
                        badge: result.update.newBestTime ? session.s.newBest : nil)
                statRow(icon: "flag.fill", label: session.s.parLabel, value: session.s.wholeSeconds(result.par),
                        badge: result.underPar ? session.s.underPar : nil)
                statRow(icon: "fuelpump.fill", label: session.s.fuelLeft, value: "\(Int((result.fuelLeft * 100).rounded()))%", badge: nil)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))

            if let custom = session.custom {
                if custom.isTest {
                    Label(session.s.testCleared, systemImage: "checkmark.seal.fill")
                        .font(UIStyle.font(15, .bold))
                        .foregroundColor(UIStyle.green)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    ActionButton(title: session.s.editorButton, icon: "hammer.fill", kind: .primary, accent: accent) {
                        session.quitToLevels()
                    }
                } else if let level = custom.communityLevel {
                    LikeButton(community: app.community, level: level, accent: accent)
                    ActionButton(title: session.s.communityButton, icon: "person.3.fill", kind: .primary, accent: accent) {
                        session.quitToLevels()
                    }
                }
                ActionButton(title: session.s.retry, icon: "arrow.counterclockwise", accent: accent) { session.restart() }
            } else {
                if !session.hasNextLevel {
                    Text(session.s.allDone)
                        .font(UIStyle.font(15, .bold))
                        .foregroundColor(UIStyle.gold)
                        .multilineTextAlignment(.center)
                }

                if session.hasNextLevel {
                    ActionButton(title: session.s.nextLevel, icon: "play.fill", kind: .primary, accent: accent) { session.nextLevel() }
                } else {
                    ActionButton(title: session.s.mainMenu, icon: "house.fill", kind: .primary, accent: accent) { session.quitToMenu() }
                }
                HStack(spacing: 12) {
                    ActionButton(title: session.s.retry, icon: "arrow.counterclockwise", accent: accent) { session.restart() }
                    ActionButton(title: session.s.levelsButton, icon: "square.grid.3x3.fill", accent: accent) { session.quitToLevels() }
                }
            }
        }
        .onAppear { shown = true }
    }

    private func statRow(icon: String, label: String, value: String, badge: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 20)
            Text(label)
                .font(UIStyle.font(15, .semibold))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let badge = badge {
                Text(badge)
                    .font(UIStyle.font(10, .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(UIStyle.gold))
            }
            Text(value)
                .font(UIStyle.font(16, .bold).monospacedDigit())
                .foregroundColor(.white)
        }
    }
}
