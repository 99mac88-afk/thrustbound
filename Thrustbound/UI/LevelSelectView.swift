import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject var app: AppModel

    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: app.s.levelsTitle, trailing: "\(app.totalStars)/\(app.maxStars)") {
                    app.go(.menu)
                }
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 26) {
                            ForEach(app.worldIndices(), id: \.self) { world in
                                worldSection(world).id(world)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .task {
                        let target = app.levels[app.continueIndex].world
                        guard target > 0 else { return }
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func worldSection(_ world: Int) -> some View {
        let info = app.worlds.indices.contains(world) ? app.worlds[world] : nil
        let accent = UIStyle.accent(for: info)
        let indices = app.levelIndices(inWorld: world)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.s.worldTag(world))
                        .font(UIStyle.font(12, .bold))
                        .tracking(2)
                        .foregroundColor(accent)
                    Text(app.s.worldName(info, index: world))
                        .font(UIStyle.font(24))
                        .foregroundColor(.white)
                    Text(app.s.worldSubtitle(info))
                        .font(UIStyle.font(13, .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundColor(UIStyle.gold)
                    Text("\(app.stars(inWorld: world))/\(indices.count * 3)")
                        .foregroundColor(.white)
                }
                .font(UIStyle.font(14, .bold))
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(indices.enumerated()), id: \.element) { offset, index in
                    LevelTile(number: offset + 1,
                              stars: app.record(forIndex: index)?.stars,
                              unlocked: app.isUnlocked(index),
                              accent: accent) {
                        app.go(.game(index))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct LevelTile: View {
    let number: Int
    let stars: Int?
    let unlocked: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button {
            guard unlocked else { return }
            SoundManager.shared.play(.click, volume: 0.6)
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 4) {
                if unlocked {
                    Text("\(number)")
                        .font(UIStyle.font(22))
                        .foregroundColor(.white)
                    StarRow(filled: stars ?? 0, size: 9, spacing: 1)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(unlocked ? accent.opacity(stars != nil ? 0.28 : 0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(unlocked ? accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: stars != nil ? 2 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(!unlocked)
    }
}
