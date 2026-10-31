import SwiftUI

@main
struct ThrustboundApp: App {
    @StateObject var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.maker)
                .environmentObject(app.account)
                .environmentObject(app.community)
                .environmentObject(app.progress)
                .preferredColorScheme(.dark)
                .onAppear { SoundManager.shared.prepare() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

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
                case .maker:
                    MakerHomeView().transition(.opacity)
                case .editor(let id):
                    EditorView(levelID: id)
                        .id(id)
                        .transition(.opacity)
                case .community:
                    CommunityView().transition(.opacity)
                case .custom(let play):
                    GameView(app: app, levelIndex: 0, custom: play)
                        .id(app.gameToken)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            // Pick up progress made on other devices when the game comes back.
            if phase == .active { app.progress.syncIfStale() }
        }
    }
}
