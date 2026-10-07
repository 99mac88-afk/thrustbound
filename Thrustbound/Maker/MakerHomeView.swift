import SwiftUI

/// The player's own levels: create, open, duplicate and delete.
struct MakerHomeView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var maker: LevelStore
    @State var pendingDelete: EditorLevel?

    private var s: L10n { app.s }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: s.makerTitle) { app.go(.menu) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ActionButton(title: s.newLevel, icon: "plus", kind: .primary) { createLevel() }

                        if maker.levels.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(UIStyle.cyan)
                                Text(s.makerIntro)
                                    .font(UIStyle.font(16, .semibold))
                                    .foregroundColor(Color.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: s.openExample, icon: "sparkles") {
                                    let sample = maker.addSample(theme: 0)
                                    app.go(.editor(sample.id))
                                }
                            }
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
                        }

                        ForEach(maker.levels) { level in
                            card(level)
                        }

                        ActionButton(title: s.communityButton, icon: "person.3.fill") { app.go(.community) }
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(s.deleteLevelTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(s.delete, role: .destructive) {
                if let level = pendingDelete { maker.delete(level.id) }
                pendingDelete = nil
            }
            Button(s.cancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(s.deleteLevelMessage)
        }
    }

    private func createLevel() {
        let names = Set(maker.levels.map(\.name))
        var n = maker.levels.count + 1
        while names.contains(s.defaultLevelName(n)) { n += 1 }
        let level = maker.create(name: s.defaultLevelName(n), theme: 0)
        app.go(.editor(level.id))
    }

    private func card(_ level: EditorLevel) -> some View {
        let world = app.worlds.indices.contains(level.theme) ? app.worlds[level.theme] : nil
        let accent = UIStyle.accent(for: world)
        let (status, color, icon): (String, Color, String) = {
            if level.isPublishedAsIs { return (s.statusPublished, UIStyle.cyan, "checkmark.icloud.fill") }
            if level.isCleared { return (s.statusTested, UIStyle.green, "checkmark.seal.fill") }
            if level.publishedID != nil { return (s.statusChanged, UIStyle.gold, "pencil.circle.fill") }
            return (s.statusDraft, Color.white.opacity(0.5), "circle.dashed")
        }()
        return HStack(spacing: 14) {
            Button {
                SoundManager.shared.play(.click, volume: 0.6)
                Haptics.light()
                app.go(.editor(level.id))
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: world?.bgTop ?? "#03070F"), Color(hex: world?.bgBottom ?? "#0A1C30")],
                                                 startPoint: .top, endPoint: .bottom))
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(accent)
                    }
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.6), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.name)
                            .font(UIStyle.font(17))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Label(status, systemImage: icon)
                            .font(UIStyle.font(12, .bold))
                            .foregroundColor(color)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Label(s.gridSize(level.cols, level.rows), systemImage: "square.grid.3x3")
                            Label("\(Int(level.fuel))", systemImage: "fuelpump.fill")
                            if let date = level.updatedAt {
                                Text(s.ago(date))
                            }
                        }
                        .font(UIStyle.font(11, .semibold))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Menu {
                Button {
                    if let copy = maker.duplicate(level.id, suffix: s.copySuffix) {
                        app.go(.editor(copy.id))
                    }
                } label: {
                    Label(s.duplicate, systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    pendingDelete = level
                } label: {
                    Label(s.delete, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
