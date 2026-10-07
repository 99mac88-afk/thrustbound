import SpriteKit
import SwiftUI

/// Hosts the editor canvas with multi-touch enabled.
struct EditorCanvasView: UIViewRepresentable {
    let scene: EditorScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene { uiView.presentScene(scene) }
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: ()) {
        uiView.presentScene(nil)
    }
}

struct EditorView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var maker: LevelStore
    let levelID: UUID

    var body: some View {
        if let session = maker.openSession(levelID) {
            EditorScreen(session: session)
        } else {
            Color.black.ignoresSafeArea()
                .onAppear { app.go(.maker) }
        }
    }
}

private enum EditorAlert {
    case problems([LevelCompiler.Problem])
    case needsTest
    case confirmPublish(again: Bool)
    case published
    case message(title: String, body: String)
}

private struct EditorScreen: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var maker: LevelStore
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var community: CommunityStore
    @ObservedObject var session: EditorSession

    @State var showSettings = false
    @State var showAccount = false
    @State var alert: EditorAlert?
    @State var publishing = false
    @State var noticeText: String?
    @State var noticeToken = 0

    private var s: L10n { app.s }
    private var accent: Color { UIStyle.accent(for: session.worldInfo(session.level.theme)) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                EditorCanvasView(scene: session.scene)
                if let text = noticeText {
                    Text(text)
                        .font(UIStyle.font(14, .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(UIStyle.gold))
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            toolOptions
            toolPalette
            actions
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            session.strings = app.s
        }
        .onChange(of: session.notice) { notice in
            guard let notice = notice else { return }
            show(s.notice(notice))
            session.notice = nil
        }
        .sheet(isPresented: $showSettings) {
            EditorSettingsSheet(session: session, onDelete: {
                showSettings = false
                maker.delete(session.level.id)
                app.go(.maker)
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showAccount) {
            AccountSheet()
                .environmentObject(app)
                .environmentObject(account)
                .environmentObject(community)
        }
        .alert(alertTitle, isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }), presenting: alert) { a in
            switch a {
            case .confirmPublish:
                Button(s.publish) { Task { await publish() } }
                Button(s.cancel, role: .cancel) {}
            case .needsTest:
                Button(s.test) { test() }
                Button(s.cancel, role: .cancel) {}
            default:
                Button(s.ok, role: .cancel) {}
            }
        } message: { a in
            Text(alertMessage(a))
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            IconButton(icon: "chevron.left", size: 40) {
                session.save()
                app.go(.maker)
            }
            Button {
                showSettings = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.level.name)
                        .font(UIStyle.font(17))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PressableStyle())
            IconButton(icon: "arrow.uturn.backward", size: 40) { session.undo() }
                .opacity(session.canUndo ? 1 : 0.35)
                .disabled(!session.canUndo)
                .accessibilityLabel(s.undo)
            IconButton(icon: "arrow.uturn.forward", size: 40) { session.redo() }
                .opacity(session.canRedo ? 1 : 0.35)
                .disabled(!session.canRedo)
                .accessibilityLabel(s.redo)
            IconButton(icon: "slider.horizontal.3", size: 40) { showSettings = true }
                .accessibilityLabel(s.levelSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(UIStyle.card)
    }

    private var statusLine: some View {
        let level = session.level
        let (text, color): (String, Color) = {
            if level.isPublishedAsIs { return (s.statusPublished, UIStyle.cyan) }
            if level.isCleared { return (s.statusTested, UIStyle.green) }
            if level.publishedID != nil { return (s.statusChanged, UIStyle.gold) }
            return (s.statusDraft, Color.white.opacity(0.5))
        }()
        return HStack(spacing: 6) {
            Image(systemName: level.isCleared ? "checkmark.seal.fill" : "circle.dashed")
            Text(text)
            Text("· " + s.gridSize(level.cols, level.rows))
                .foregroundColor(Color.white.opacity(0.4))
            Image(systemName: "fuelpump.fill").foregroundColor(Color.white.opacity(0.4))
            Text("\(Int(level.fuel))")
                .foregroundColor(Color.white.opacity(0.4))
        }
        .font(UIStyle.font(12, .bold))
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var toolOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.pendingMine != nil ? s.notice(.mineTrack) : s.toolHint(session.tool))
                .font(UIStyle.font(12, .semibold))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            optionChips
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(minHeight: 44, alignment: .top)
        .background(UIStyle.card)
    }

    @ViewBuilder
    private var optionChips: some View {
        switch session.tool {
        case .wind:
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { d in
                    chip(icon: ["arrow.up", "arrow.right", "arrow.down", "arrow.left"][d], selected: session.windDir == d) {
                        session.windDir = d
                    }
                }
            }
        case .key, .door:
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { c in
                    chip(icon: session.tool == .key ? "key.fill" : "door.left.hand.closed", label: s.colorName(c),
                         tint: Color(Palette.key(c)), selected: session.color == c) {
                        session.color = c
                    }
                }
            }
        case .laser:
            HStack(spacing: 8) {
                chip(icon: "arrow.left.and.right", label: s.across, selected: session.laserDir == 0) { session.laserDir = 0 }
                chip(icon: "arrow.up.and.down", label: s.upDown, selected: session.laserDir == 1) { session.laserDir = 1 }
            }
        case .spinner:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([2, 3, 4], id: \.self) { n in
                        chip(icon: nil, label: s.bladeSize(n), selected: session.spinnerSize == n) { session.spinnerSize = n }
                    }
                    chip(icon: "arrow.counterclockwise", label: nil, selected: session.spinnerDir == 0) { session.spinnerDir = 0 }
                        .accessibilityLabel(s.anticlockwise)
                    chip(icon: "arrow.clockwise", label: nil, selected: session.spinnerDir == 1) { session.spinnerDir = 1 }
                        .accessibilityLabel(s.clockwise)
                }
            }
        default:
            EmptyView()
        }
    }

    private func chip(icon: String?, label: String? = nil, tint: Color? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon).foregroundColor(tint ?? (selected ? .black : .white))
                }
                if let label = label { Text(label).lineLimit(1) }
            }
            .font(UIStyle.font(13, .bold))
            .foregroundColor(selected ? .black : .white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(selected ? accent : Color.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
    }

    private var toolPalette: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EditorTool.allCases) { tool in
                        let selected = session.tool == tool
                        Button {
                            Haptics.light()
                            SoundManager.shared.play(.click, volume: 0.4)
                            session.tool = tool
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(selected ? .black : toolColor(tool))
                                    .frame(height: 22)
                                Text(s.toolName(tool))
                                    .font(UIStyle.font(10, .bold))
                                    .foregroundColor(selected ? .black : .white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(width: 58, height: 56)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? accent : Color.white.opacity(0.07)))
                        }
                        .buttonStyle(PressableStyle())
                        .id(tool)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onAppear { proxy.scrollTo(session.tool, anchor: .center) }
        }
        .background(UIStyle.card)
    }

    private func toolColor(_ tool: EditorTool) -> Color {
        switch tool {
        case .rock: return accent
        case .erase, .spikes, .mine, .movingMine, .spinner, .laser: return UIStyle.red
        case .start: return Color(hex: "#C9D3E3")
        case .goal: return UIStyle.green
        case .star: return UIStyle.gold
        case .fuel: return UIStyle.orange
        case .wind: return Color(Palette.wind)
        case .key, .door: return Color(Palette.key(0))
        case .hand: return .white
        }
    }

    private var actions: some View {
        let level = session.level
        return HStack(spacing: 12) {
            ActionButton(title: s.test, icon: "play.fill", kind: .primary, accent: accent, height: 50) { test() }
            ActionButton(title: level.isPublishedAsIs ? s.published : s.publish,
                         icon: level.isPublishedAsIs ? "checkmark.icloud.fill" : "icloud.and.arrow.up.fill",
                         accent: accent, height: 50) {
                publishTapped()
            }
            .opacity(publishing ? 0.5 : (level.isPublishedAsIs ? 0.6 : 1))
            .disabled(publishing || level.isPublishedAsIs)
            .overlay(publishing ? ProgressView().tint(.white) : nil)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(UIStyle.card.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func show(_ text: String) {
        noticeToken += 1
        let token = noticeToken
        withAnimation(.easeOut(duration: 0.2)) { noticeText = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if token == noticeToken {
                withAnimation(.easeIn(duration: 0.25)) { noticeText = nil }
            }
        }
    }

    private func test() {
        let problems = session.problems
        guard problems.isEmpty else {
            alert = .problems(problems)
            return
        }
        session.save()
        let level = session.level
        let compiled = LevelCompiler.compile(level, worldCount: app.worlds.count)
        app.go(.custom(CustomPlay(level: compiled, origin: .editor(levelID: level.id, hash: level.contentHash))))
    }

    private func publishTapped() {
        guard account.isConfigured else {
            alert = .message(title: s.notConfiguredTitle, body: s.notConfiguredBody)
            return
        }
        guard account.isSignedIn else {
            showAccount = true
            return
        }
        let problems = session.problems
        guard problems.isEmpty else {
            alert = .problems(problems)
            return
        }
        guard session.level.isCleared else {
            alert = .needsTest
            return
        }
        alert = .confirmPublish(again: session.level.publishedID != nil)
    }

    private func publish() async {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }
        let level = session.level
        do {
            let remoteID = try await community.publish(level)
            maker.markPublished(id: level.id, remoteID: remoteID, hash: level.contentHash)
            Haptics.success()
            alert = .published
        } catch {
            alert = .message(title: s.publish, body: s.onlineError(error))
        }
    }

    private var alertTitle: String {
        switch alert {
        case .problems?: return s.notReadyTitle
        case .needsTest?: return s.publishNeedsTestTitle
        case .confirmPublish?: return s.publishConfirmTitle(session.level.name)
        case .published?: return s.publishedTitle
        case .message(let title, _)?: return title
        case nil: return ""
        }
    }

    private func alertMessage(_ a: EditorAlert) -> String {
        switch a {
        case .problems(let list): return list.map { "• " + s.problem($0) }.joined(separator: "\n")
        case .needsTest: return s.publishNeedsTest
        case .confirmPublish(let again): return again ? s.publishAgainMessage : s.publishConfirmMessage
        case .published: return s.publishedMessage
        case .message(_, let body): return body
        }
    }
}

// MARK: - Level settings

struct EditorSettingsSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject var session: EditorSession
    let onDelete: () -> Void

    @State var name = ""
    @State var fuel: Double = 25
    @State var confirmDelete = false

    private var s: L10n { app.s }

    var body: some View {
        ZStack {
            UIStyle.card.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(s.levelSettings)
                            .font(UIStyle.font(24))
                            .foregroundColor(.white)
                        Spacer()
                        Button(s.done) {
                            commitName()
                            dismiss()
                        }
                        .font(UIStyle.font(17, .bold))
                        .foregroundColor(UIStyle.cyan)
                    }

                    section(s.nameLabel) {
                        TextField(s.nameLabel, text: $name, onCommit: commitName)
                            .font(UIStyle.font(18, .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                            .disableAutocorrection(true)
                    }

                    section(s.themeLabel) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                            ForEach(0..<max(1, session.worlds.count), id: \.self) { i in
                                themeChip(i)
                            }
                        }
                    }

                    section(s.widthLabel) {
                        HStack(spacing: 8) {
                            choice(s.narrow + " · 14", selected: session.level.cols == EditorLevel.narrowCols) {
                                session.edit { $0.resize(cols: EditorLevel.narrowCols, rows: $0.rows) }
                            }
                            choice(s.wide + " · 28", selected: session.level.cols == EditorLevel.wideCols) {
                                session.edit { $0.resize(cols: EditorLevel.wideCols, rows: $0.rows) }
                            }
                        }
                    }

                    section(s.heightLabel) {
                        HStack {
                            Text(s.rowsCount(session.level.rows))
                                .font(UIStyle.font(17, .bold))
                                .foregroundColor(.white)
                            Spacer()
                            stepButton("minus", enabled: session.level.rows > EditorLevel.minRows) {
                                session.edit { $0.resize(cols: $0.cols, rows: $0.rows - 5) }
                            }
                            stepButton("plus", enabled: session.level.rows < EditorLevel.maxRows) {
                                session.edit { $0.resize(cols: $0.cols, rows: $0.rows + 5) }
                            }
                        }
                        Text(s.shrinkWarning)
                            .font(UIStyle.font(12, .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                    }

                    section(s.fuelLabel) {
                        HStack {
                            Image(systemName: "fuelpump.fill").foregroundColor(UIStyle.orange)
                            Text("\(Int(fuel))")
                                .font(UIStyle.font(20, .black).monospacedDigit())
                                .foregroundColor(.white)
                                .frame(width: 44, alignment: .leading)
                            Slider(value: $fuel, in: EditorLevel.fuelRange, step: 1, onEditingChanged: { editing in
                                if !editing { commitFuel() }
                            })
                            .tint(UIStyle.orange)
                        }
                        Text(s.fuelDetail)
                            .font(UIStyle.font(12, .medium))
                            .foregroundColor(Color.white.opacity(0.5))
                    }

                    Button {
                        confirmDelete = true
                    } label: {
                        Label(s.deleteLevel, systemImage: "trash.fill")
                            .font(UIStyle.font(16, .bold))
                            .foregroundColor(UIStyle.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(UIStyle.red.opacity(0.12)))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .onAppear {
            name = session.level.name
            fuel = session.level.fuel
        }
        .onDisappear {
            commitName()
            commitFuel()
        }
        .alert(s.deleteLevelTitle, isPresented: $confirmDelete) {
            Button(s.delete, role: .destructive) { onDelete() }
            Button(s.cancel, role: .cancel) {}
        } message: {
            Text(s.deleteLevelMessage)
        }
    }

    private func commitName() {
        session.rename(name)
    }

    private func commitFuel() {
        let value = fuel.rounded()
        if value != session.level.fuel {
            session.edit { $0.fuel = value }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(UIStyle.font(12, .heavy))
                .tracking(1.2)
                .foregroundColor(Color.white.opacity(0.5))
            content()
        }
    }

    private func themeChip(_ i: Int) -> some View {
        let world = session.worldInfo(i)
        let selected = session.level.theme == i
        let neon = UIStyle.accent(for: world)
        return Button {
            Haptics.light()
            session.edit { $0.theme = i }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Color(hex: world?.bgTop ?? "#03070F"), Color(hex: world?.bgBottom ?? "#0A1C30")],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: world?.rock ?? "#0E2233"))
                        .frame(height: 12)
                        .overlay(Rectangle().fill(neon).frame(height: 2), alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 40)
                Text(s.worldName(world, index: i))
                    .font(UIStyle.font(10, .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12).stroke(selected ? neon : Color.white.opacity(0.12), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(UIStyle.font(15, .bold))
                .foregroundColor(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? UIStyle.cyan : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
