import SwiftUI

/// Browse levels other pilots published.
struct CommunityView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var community: CommunityStore
    @EnvironmentObject var progress: ProgressSync
    @State var tab: CommunityTab = .newest
    @State var showAccount = false
    @State var selected: CommunityLevel?

    private var s: L10n { app.s }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                header
                if account.isConfigured {
                    tabs
                    list
                } else {
                    notConfigured
                }
            }
        }
        .task(id: tab) {
            await community.loadIfNeeded(tab)
        }
        .onAppear {
            progress.syncIfStale()
            if app.launch.screen == "account-code" { showAccount = true }
        }
        .onChange(of: account.userID) { _ in
            community.reset()
            Task { await community.reload(tab) }
        }
        .onChange(of: account.config) { _ in
            community.reset()
            Task { await community.reload(tab) }
        }
        .sheet(item: $selected) { level in
            CommunityDetailSheet(level: level)
                .environmentObject(app)
                .environmentObject(account)
                .environmentObject(community)
                .environmentObject(progress)
        }
        .sheet(isPresented: $showAccount) {
            AccountSheet()
                .environmentObject(app)
                .environmentObject(account)
                .environmentObject(community)
                .environmentObject(progress)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(icon: "chevron.left") { app.go(.menu) }
            Text(s.communityTitle)
                .font(UIStyle.font(24))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button {
                SoundManager.shared.play(.click, volume: 0.6)
                showAccount = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                    Text(account.profile?.username ?? (account.isSignedIn ? s.accountTitle : s.signIn))
                        .lineLimit(1)
                    if account.isAdmin {
                        Image(systemName: "shield.lefthalf.filled").foregroundColor(UIStyle.gold)
                    }
                }
                .font(UIStyle.font(14, .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(CommunityTab.allCases) { t in
                let on = t == tab
                Button {
                    guard !on else { return }
                    Haptics.light()
                    tab = t
                } label: {
                    Text(s.tabName(t))
                        .font(UIStyle.font(13, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(on ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? UIStyle.cyan : Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var list: some View {
        let levels = community.levels(tab)
        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if tab == .mine && !account.isSignedIn {
                    message(s.signInForMine, icon: "person.crop.circle") {
                        ActionButton(title: s.signIn, icon: "person.fill", kind: .primary) { showAccount = true }
                    }
                } else {
                    ForEach(levels) { level in
                        Button {
                            SoundManager.shared.play(.click, volume: 0.6)
                            Haptics.light()
                            selected = level
                        } label: {
                            CommunityRow(level: level, mine: level.authorID == account.userID,
                                         liked: community.liked.contains(level.id),
                                         finished: progress.clearTime(level.id), s: s)
                        }
                        .buttonStyle(PressableStyle())
                        .onAppear {
                            if level.id == levels.last?.id {
                                Task { await community.loadMore(tab) }
                            }
                        }
                    }
                    footer(levels)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .refreshable {
            await community.reload(tab)
        }
    }

    @ViewBuilder
    private func footer(_ levels: [CommunityLevel]) -> some View {
        if community.loading.contains(tab) {
            ProgressView().tint(.white).padding(24)
        } else if let error = community.errors[tab] {
            message(s.onlineError(error), icon: "wifi.exclamationmark") {
                ActionButton(title: s.retryShort, icon: "arrow.clockwise") {
                    Task { await community.reload(tab) }
                }
            }
        } else if levels.isEmpty && community.lists[tab] != nil {
            message(tab == .mine ? s.emptyMine : s.emptyList, icon: tab == .mine ? "hammer.fill" : "sparkles") {
                ActionButton(title: s.makerButton, icon: "hammer.fill") { app.go(.maker) }
            }
        }
    }

    private func message<Extra: View>(_ text: String, icon: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(UIStyle.cyan)
            Text(text)
                .font(UIStyle.font(15, .semibold))
                .foregroundColor(Color.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
        .padding(.top, 10)
    }

    private var notConfigured: some View {
        ScrollView {
            message(s.notConfiguredBody, icon: "server.rack") {
                ActionButton(title: s.serverTitle, icon: "gearshape.fill") { showAccount = true }
            }
            .padding(.horizontal, 18)
        }
    }
}

struct CommunityRow: View {
    let level: CommunityLevel
    let mine: Bool
    let liked: Bool
    /// The player's best time if they finished this level.
    let finished: Double?
    let s: L10n

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(level.title)
                        .font(UIStyle.font(17))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if mine {
                        Text(s.yours)
                            .font(UIStyle.font(9, .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(UIStyle.cyan))
                    }
                }
                HStack(spacing: 6) {
                    Text(s.byAuthor(level.author))
                    if let date = level.createdAt {
                        Text("· " + s.ago(date))
                    }
                }
                .font(UIStyle.font(12, .semibold))
                .foregroundColor(Color.white.opacity(0.55))
                .lineLimit(1)
                if let time = finished {
                    Label(s.finishedIn(time), systemImage: "checkmark.seal.fill")
                        .font(UIStyle.font(12, .bold))
                        .foregroundColor(UIStyle.green)
                        .lineLimit(1)
                } else {
                    Label(s.notFinished, systemImage: "circle.dashed")
                        .font(UIStyle.font(12, .semibold))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Label("\(level.likes)", systemImage: liked ? "heart.fill" : "heart")
                    .foregroundColor(liked ? UIStyle.red : .white)
                Label("\(level.views)", systemImage: "eye.fill")
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .font(UIStyle.font(13, .bold).monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.white.opacity(0.35))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// One community level: play it, like it, or (author / admin) delete it.
struct CommunityDetailSheet: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var community: CommunityStore
    @EnvironmentObject var progress: ProgressSync
    @Environment(\.dismiss) var dismiss
    let level: CommunityLevel

    @State var loadingLevel = false
    @State var errorText: String?
    @State var confirmDelete = false
    @State var deleting = false

    private var s: L10n { app.s }
    private var current: CommunityLevel { community.find(level.id) ?? level }

    var body: some View {
        ZStack {
            UIStyle.card.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Spacer()
                        Button(s.done) { dismiss() }
                            .font(UIStyle.font(17, .bold))
                            .foregroundColor(UIStyle.cyan)
                    }
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(UIStyle.green)
                        .shadow(color: UIStyle.green.opacity(0.6), radius: 12)
                    Text(current.title)
                        .font(UIStyle.font(28, .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        Text(s.byAuthor(current.author))
                        if let date = current.createdAt {
                            Text("· " + s.ago(date))
                        }
                    }
                    .font(UIStyle.font(14, .semibold))
                    .foregroundColor(Color.white.opacity(0.6))

                    HStack(spacing: 12) {
                        stat(icon: "eye.fill", text: s.viewsCount(current.views), color: UIStyle.cyan)
                        stat(icon: "heart.fill", text: s.likesCount(current.likes), color: UIStyle.red)
                    }

                    finishedStatus

                    ActionButton(title: s.play, icon: "play.fill", kind: .primary, height: 60) {
                        Task { await play() }
                    }
                    .opacity(loadingLevel ? 0.5 : 1)
                    .disabled(loadingLevel)
                    .overlay(loadingLevel ? ProgressView().tint(.black) : nil)

                    LikeButton(community: community, level: current, accent: UIStyle.cyan)

                    if let error = errorText {
                        Text(error)
                            .font(UIStyle.font(14, .semibold))
                            .foregroundColor(UIStyle.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if community.canDelete(current) {
                        Button {
                            confirmDelete = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: account.isAdmin && current.authorID != account.userID ? "shield.lefthalf.filled" : "trash.fill")
                                Text(s.deleteOnline)
                                if account.isAdmin && current.authorID != account.userID {
                                    Text(s.adminBadge)
                                        .font(UIStyle.font(10, .heavy))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(UIStyle.gold))
                                }
                            }
                            .font(UIStyle.font(16, .bold))
                            .foregroundColor(UIStyle.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(UIStyle.red.opacity(0.12)))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(deleting)
                        .opacity(deleting ? 0.5 : 1)
                    }
                }
                .padding(22)
            }
        }
        .alert(s.deleteOnlineTitle(current.title), isPresented: $confirmDelete) {
            Button(s.delete, role: .destructive) { Task { await delete() } }
            Button(s.cancel, role: .cancel) {}
        } message: {
            Text(s.deleteOnlineMessage)
        }
    }

    private func stat(icon: String, text: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(UIStyle.font(15, .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    /// Whether this player has landed on the level yet (and their best time).
    private var finishedStatus: some View {
        let time = progress.clearTime(current.id)
        return Label(time.map { s.youFinished($0) } ?? s.youHaventFinished,
                     systemImage: time == nil ? "circle.dashed" : "checkmark.seal.fill")
            .font(UIStyle.font(14, .bold))
            .foregroundColor(time == nil ? Color.white.opacity(0.6) : UIStyle.green)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill((time == nil ? Color.white : UIStyle.green).opacity(0.1)))
    }

    private func play() async {
        guard !loadingLevel else { return }
        loadingLevel = true
        errorText = nil
        defer { loadingLevel = false }
        do {
            let editorLevel = try await community.download(current)
            let compiled = LevelCompiler.compile(editorLevel, worldCount: app.worlds.count, title: current.title)
            community.registerView(current.id)
            dismiss()
            app.go(.custom(CustomPlay(level: compiled, origin: .community(current))))
        } catch {
            errorText = s.onlineError(error)
        }
    }

    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await community.delete(current)
            Haptics.success()
            dismiss()
        } catch {
            errorText = s.onlineError(error)
        }
    }
}

/// Heart button with the like count. Asks the player to sign in first if needed.
struct LikeButton: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var account: AccountStore
    @ObservedObject var community: CommunityStore
    let level: CommunityLevel
    let accent: Color
    @State var showAccount = false
    @State var errorText: String?

    var body: some View {
        let liked = community.liked.contains(level.id)
        let likes = community.find(level.id)?.likes ?? level.likes
        VStack(spacing: 6) {
            Button {
                Haptics.light()
                guard account.isSignedIn else {
                    showAccount = true
                    return
                }
                Task {
                    do {
                        errorText = nil
                        try await community.toggleLike(level.id)
                        if community.liked.contains(level.id) { Haptics.success() }
                    } catch {
                        errorText = app.s.onlineError(error)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(liked ? UIStyle.red : .white)
                        .scaleEffect(liked ? 1.15 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: liked)
                    Text(app.s.like)
                    Text("\(likes)")
                        .monospacedDigit()
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .font(UIStyle.font(17, .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(liked ? UIStyle.red.opacity(0.18) : Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(liked ? UIStyle.red.opacity(0.6) : accent.opacity(0.45), lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
            .disabled(community.liking.contains(level.id))
            if let error = errorText {
                Text(error)
                    .font(UIStyle.font(12, .semibold))
                    .foregroundColor(UIStyle.red)
                    .multilineTextAlignment(.center)
            } else if !account.isSignedIn {
                Text(app.s.signInToLike)
                    .font(UIStyle.font(12, .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountSheet()
                .environmentObject(app)
                .environmentObject(account)
                .environmentObject(community)
                .environmentObject(app.progress)
        }
    }
}
