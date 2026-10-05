import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var app: AppModel
    @State var bob = false

    var body: some View {
        ZStack {
            StarfieldBackground()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [UIStyle.cyan.opacity(0.35), .clear], center: .center,
                                                 startRadius: 4, endRadius: 120))
                            .frame(width: 240, height: 240)
                        RocketGlyph()
                            .frame(width: 110, height: min(170, geo.size.height * 0.22))
                            .rotationEffect(.degrees(bob ? 6 : -6))
                            .offset(y: bob ? -10 : 8)
                    }
                    .frame(height: min(220, geo.size.height * 0.28))

                    Text("THRUSTBOUND")
                        .font(UIStyle.font(min(44, geo.size.width * 0.105), .black))
                        .tracking(2)
                        .foregroundColor(.white)
                        .shadow(color: UIStyle.cyan.opacity(0.9), radius: 10)
                        .shadow(color: UIStyle.cyan.opacity(0.6), radius: 24)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Defy gravity. Stick the landing.")
                        .font(UIStyle.font(16, .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.top, 6)

                    Spacer(minLength: 24)

                    VStack(spacing: 14) {
                        let next = app.continueIndex
                        ActionButton(title: app.hasProgress ? "CONTINUE" : "PLAY", icon: "play.fill", kind: .primary, height: 62) {
                            app.go(.game(next))
                        }
                        if app.levels.indices.contains(next) {
                            Text("Level \(levelLabel(next)) · \(app.levels[next].name)")
                                .font(UIStyle.font(13, .semibold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .padding(.top, -6)
                        }
                        ActionButton(title: "LEVELS", icon: "square.grid.3x3.fill") {
                            app.go(.levels)
                        }
                        HStack(spacing: 14) {
                            ActionButton(title: "HOW TO", icon: "questionmark.circle.fill") {
                                app.go(.howTo)
                            }
                            ActionButton(title: "SETTINGS", icon: "gearshape.fill") {
                                app.go(.settings)
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    HStack(spacing: 18) {
                        Label("\(app.totalStars)/\(app.maxStars)", systemImage: "star.fill")
                        Label("\(app.completedCount)/\(app.levels.count)", systemImage: "flag.fill")
                    }
                    .font(UIStyle.font(15, .bold))
                    .foregroundColor(Color.white.opacity(0.75))
                    .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private func levelLabel(_ index: Int) -> String {
        let level = app.levels[index]
        let inWorld = app.levelIndices(inWorld: level.world)
        return "\(level.world + 1)-\((inWorld.firstIndex(of: index) ?? 0) + 1)"
    }
}
