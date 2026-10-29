import SwiftUI

/// Sign up, sign in, see who you are, and (for server owners) point the game at a server.
struct AccountSheet: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var account: AccountStore
    @EnvironmentObject var community: CommunityStore
    @Environment(\.dismiss) var dismiss

    @State var creating = true
    @State var username = ""
    @State var email = ""
    @State var password = ""
    @State var busy = false
    @State var errorText: String?
    @State var infoText: String?
    @State var code = ""
    @State var showServer = false
    @State var serverURL = ""
    @State var serverKey = ""
    @State var serverNote: String?

    private var s: L10n { app.s }

    var body: some View {
        ZStack {
            UIStyle.card.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(s.accountTitle)
                            .font(UIStyle.font(26))
                            .foregroundColor(.white)
                        Spacer()
                        Button(s.done) { dismiss() }
                            .font(UIStyle.font(17, .bold))
                            .foregroundColor(UIStyle.cyan)
                    }

                    if !account.isConfigured {
                        note(s.notConfiguredBody, icon: "server.rack", color: UIStyle.gold)
                    } else if account.isSignedIn {
                        profileCard
                    } else if let pending = account.pending {
                        codeStep(pending)
                    } else {
                        form
                    }

                    serverSection
                        .padding(.top, 10)
                }
                .padding(22)
            }
        }
        .onAppear {
            serverURL = account.usingCustomServer ? (account.config?.url ?? "") : ""
            serverKey = account.usingCustomServer ? (account.config?.anonKey ?? "") : ""
            showServer = !account.isConfigured
            if account.isSignedIn { Task { await account.refreshProfile() } }
        }
    }

    // MARK: - Signed in

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(UIStyle.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(account.profile?.username ?? "…")
                            .font(UIStyle.font(22))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if account.isAdmin {
                            Text(s.adminBadge)
                                .font(UIStyle.font(11, .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(UIStyle.gold))
                        }
                    }
                    if let mail = account.session?.email {
                        Text(mail)
                            .font(UIStyle.font(13, .medium))
                            .foregroundColor(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            if account.isAdmin {
                note(s.adminNote, icon: "shield.lefthalf.filled", color: UIStyle.gold)
            }
            Button {
                Task {
                    await account.signOut()
                    community.reset()
                }
            } label: {
                Label(s.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                    .font(UIStyle.font(16, .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Sign up / sign in

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(s.accountPitch)
                .font(UIStyle.font(15, .medium))
                .foregroundColor(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if creating {
                field(s.usernameLabel, footnote: s.usernameRules) {
                    TextField(s.usernameLabel, text: $username)
                        .textContentType(.username)
                }
            }
            field(s.emailLabel, footnote: nil) {
                TextField(s.emailLabel, text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }
            field(s.passwordLabel, footnote: creating ? s.passwordRules : nil) {
                SecureField(s.passwordLabel, text: $password)
                    .textContentType(creating ? .newPassword : .password)
            }

            if let error = errorText {
                Text(error)
                    .font(UIStyle.font(14, .semibold))
                    .foregroundColor(UIStyle.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ActionButton(title: creating ? s.signUp : s.signIn, icon: creating ? "person.badge.plus" : "person.fill",
                         kind: .primary) {
                Task { await submit() }
            }
            .disabled(busy || !canSubmit)
            .opacity(busy || !canSubmit ? 0.5 : 1)
            .overlay(busy ? ProgressView().tint(.black) : nil)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    creating.toggle()
                    errorText = nil
                }
            } label: {
                Text(creating ? s.haveAccount : s.needAccount)
                    .font(UIStyle.font(15, .bold))
                    .foregroundColor(UIStyle.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private var canSubmit: Bool {
        let mailOK = email.contains("@") && email.contains(".")
        let passOK = password.count >= 6
        if creating { return mailOK && passOK && AccountStore.isValidUsername(username.trimmingCharacters(in: .whitespaces)) }
        return mailOK && !password.isEmpty
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            if creating {
                let signedIn = try await account.signUp(username: username, email: email, password: password)
                password = ""
                guard signedIn else {
                    // The server emailed a code; the code step shows next.
                    code = ""
                    infoText = nil
                    return
                }
            } else {
                try await account.signIn(email: email, password: password)
            }
            password = ""
            community.reset()
            Haptics.success()
        } catch OnlineError.confirmEmail {
            password = ""
            code = ""
            infoText = s.onlineError(OnlineError.confirmEmail)
        } catch {
            errorText = s.onlineError(error)
        }
    }

    // MARK: - Code from the confirmation email

    private func codeStep(_ pending: AccountStore.PendingSignUp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 28))
                    .foregroundColor(UIStyle.cyan)
                Text(s.checkEmailTitle)
                    .font(UIStyle.font(22))
                    .foregroundColor(.white)
            }
            Text(s.codeSentTo(pending.email))
                .font(UIStyle.font(15, .medium))
                .foregroundColor(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            field(s.codeLabel, footnote: s.codeHint) {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .onChange(of: code) { typed in
                        let clean = AccountStore.cleanCode(typed)
                        if clean != typed { code = clean }
                    }
            }

            if let info = infoText {
                Text(info)
                    .font(UIStyle.font(14, .semibold))
                    .foregroundColor(UIStyle.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = errorText {
                Text(error)
                    .font(UIStyle.font(14, .semibold))
                    .foregroundColor(UIStyle.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let ready = AccountStore.isCompleteCode(code)
            ActionButton(title: s.confirmCode, icon: "checkmark.seal.fill", kind: .primary) {
                Task { await confirm() }
            }
            .disabled(busy || !ready)
            .opacity(busy || !ready ? 0.5 : 1)
            .overlay(busy ? ProgressView().tint(.black) : nil)

            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let wait = account.resendWait(now: context.date)
                Button {
                    Task { await resend() }
                } label: {
                    Text(wait > 0 ? s.resendIn(wait) : s.resendCode)
                        .font(UIStyle.font(15, .bold))
                        .foregroundColor(wait > 0 ? Color.white.opacity(0.4) : UIStyle.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .disabled(busy || wait > 0)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    email = pending.email
                    account.cancelPending()
                    code = ""
                    errorText = nil
                    infoText = nil
                }
            } label: {
                Text(s.startOver)
                    .font(UIStyle.font(15, .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private func confirm() async {
        guard !busy, AccountStore.isCompleteCode(code) else { return }
        busy = true
        errorText = nil
        infoText = nil
        defer { busy = false }
        do {
            try await account.confirmEmail(code: code)
            code = ""
            creating = false
            community.reset()
            Haptics.success()
        } catch {
            errorText = s.onlineError(error)
            Haptics.failure()
        }
    }

    private func resend() async {
        guard !busy else { return }
        busy = true
        errorText = nil
        infoText = nil
        defer { busy = false }
        do {
            try await account.resendCode()
            code = ""
            infoText = s.codeResent
        } catch {
            errorText = s.onlineError(error)
        }
    }

    private func field<Input: View>(_ title: String, footnote: String?,
                                    @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(UIStyle.font(11, .heavy))
                .tracking(1.1)
                .foregroundColor(Color.white.opacity(0.5))
            input()
                .font(UIStyle.font(17, .semibold))
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            if let footnote = footnote {
                Text(footnote)
                    .font(UIStyle.font(12, .medium))
                    .foregroundColor(Color.white.opacity(0.45))
            }
        }
    }

    private func note(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(text)
                .foregroundColor(Color.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(UIStyle.font(14, .semibold))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.1)))
    }

    // MARK: - Server

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showServer.toggle() }
            } label: {
                HStack {
                    Image(systemName: "server.rack")
                    Text(s.serverTitle)
                    Spacer()
                    Text(account.usingCustomServer ? s.serverCustom : (account.hasBundledServer ? s.serverBuiltIn : s.serverNone))
                        .font(UIStyle.font(12, .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineLimit(1)
                    Image(systemName: showServer ? "chevron.up" : "chevron.down")
                }
                .font(UIStyle.font(15, .bold))
                .foregroundColor(.white)
            }
            if showServer {
                Text(s.serverHelp)
                    .font(UIStyle.font(12, .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                field(s.serverURL, footnote: nil) {
                    TextField("https://", text: $serverURL)
                        .keyboardType(.URL)
                }
                field(s.serverKey, footnote: nil) {
                    TextField("eyJ…", text: $serverKey)
                }
                if let note = serverNote {
                    Text(note)
                        .font(UIStyle.font(13, .semibold))
                        .foregroundColor(UIStyle.gold)
                }
                HStack(spacing: 10) {
                    ActionButton(title: s.serverSave, icon: "checkmark", height: 44) {
                        if account.setServer(url: serverURL, key: serverKey) {
                            serverNote = nil
                            community.reset()
                            Haptics.success()
                        } else {
                            serverNote = s.serverInvalid
                            Haptics.failure()
                        }
                    }
                    if account.usingCustomServer && account.hasBundledServer {
                        ActionButton(title: s.useBuiltIn, icon: "arrow.uturn.backward", height: 44) {
                            account.useBuiltInServer()
                            serverURL = ""
                            serverKey = ""
                            community.reset()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}
