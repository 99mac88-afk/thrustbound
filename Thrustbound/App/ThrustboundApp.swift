import SwiftUI

@main
struct ThrustboundApp: App {
    @StateObject var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .onAppear { SoundManager.shared.prepare() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if app.levels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundColor(UIStyle.gold)
                    Text(app.s.levelsFailed).font(UIStyle.font(18, .bold)).foregroundColor(.white)
                }
            } else {
                switch app.screen {
                case .menu:
                    MainMenuView().transition(.opacity)
                case .levels:
                    LevelSelectView().transition(.opacity)
                case .game(let index):
                    GameView(app: app, levelIndex: index)
                        .id(app.gameToken)
                        .transition(.opacity)
                case .howTo:
                    HowToPlayView().transition(.opacity)
                case .settings:
                    SettingsView().transition(.opacity)
                }
            }
        }
    }
}
