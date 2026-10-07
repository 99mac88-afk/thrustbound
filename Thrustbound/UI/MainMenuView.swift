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
                            .frame(width: 110, height: min(170, geo.size.height * 0.19))
                            .rotationEffect(.degrees(bob ? 6 : -6))
                            .offset(y: bob ? -10 : 8)
                    }
                    .frame(height: min(220, geo.size.height * 0.25))

                    Text("THRUSTBOUND")
                        .font(UIStyle.font(min(44, geo.size.width * 0.105), .black))
                        .tracking(2)
                        .foregroundColor(.white)
                        .shadow(color: UIStyle.cyan.opacity(0.9), radius: 10)
                        .shadow(color: UIStyle.cyan.opacity(0.6), radius: 24)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(app.s.tagline)
                        .font(UIStyle.font(16, .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.top, 6)

                    Spacer(minLength: 24)

                    let compact = geo.size.height < 720
                    let buttonHeight: CGFloat = compact ? 48 : 54
                    VStack(spacing: compact ? 10 : 14) {
                        let next = app.continueIndex
                        ActionButton(title: app.hasProgress ? app.s.continueGame : app.s.play, icon: "play.fill", kind: .primary,
                                     height: compact ? 56 : 62) {
                            app.go(.game(next))
                        }
                        if app.levels.indices.contains(next) {
                            Text(app.s.levelLine(levelLabel(next), app.s.name(app.levels[next])))
                                .font(UIStyle.font(13, .semibold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .padding(.top, -6)
                        }
                        ActionButton(title: app.s.levelsButton, icon: "square.grid.3x3.fill", height: buttonHeight) {
                            app.go(.levels)
                        }
                        HStack(spacing: 14) {
                            ActionButton(title: app.s.communityButton, icon: "person.3.fill", height: buttonHeight) {
                                app.go(.community)
                            }
                            ActionButton(title: app.s.makerButton, icon: "hammer.fill", height: buttonHeight) {
                                app.go(.maker)
                            }
                        }
                        HStack(spacing: 14) {
                            ActionButton(title: app.s.howToButton, icon: "questionmark.circle.fill", height: buttonHeight) {
                                app.go(.howTo)
                            }
                            ActionButton(title: app.s.settingsButton, icon: "gearshape.fill", height: buttonHeight) {
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
