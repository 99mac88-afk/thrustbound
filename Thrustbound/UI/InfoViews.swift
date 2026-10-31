import SwiftUI

struct HowToPlayView: View {
    @EnvironmentObject var app: AppModel

    /// Icon colours for the tips, in the order L10n.tips lists them.
    private static let colors: [Color] = [
        UIStyle.cyan, UIStyle.orange, UIStyle.green, UIStyle.gold,
        UIStyle.orange, UIStyle.red, Color(hex: "#8FD3FF"), Color(hex: "#FFC23D")
    ]

    var body: some View {
        let s = app.s
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: s.howToTitle) { app.go(.menu) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ControlsDiagram(s: s)
                            .padding(.bottom, 6)
                        ForEach(Array(s.tips.enumerated()), id: \.offset) { index, tip in
                            let color = Self.colors[index % Self.colors.count]
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: tip.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(color)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(color.opacity(0.15)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tip.title)
                                        .font(UIStyle.font(18))
                                        .foregroundColor(.white)
                                    Text(tip.text)
                                        .font(UIStyle.font(14, .medium))
                                        .foregroundColor(Color.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
                        }
                        ActionButton(title: s.letsFly, icon: "play.fill", kind: .primary) {
                            app.go(.game(app.continueIndex))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

/// Little picture of the phone layout: stick on the left, gas on the right.
private struct ControlsDiagram: View {
    let s: L10n

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
            VStack {
                RocketGlyph()
                    .frame(width: 50, height: 70)
                    .rotationEffect(.degrees(-18))
                Spacer()
                HStack {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 2).frame(width: 72, height: 72)
                        Circle().fill(Color.white.opacity(0.85)).frame(width: 30, height: 30).offset(x: -12, y: -10)
                    }
                    Spacer()
                    ZStack {
                        Circle().fill(UIStyle.cyan.opacity(0.25)).frame(width: 66, height: 66)
                        Circle().stroke(UIStyle.cyan, lineWidth: 2).frame(width: 66, height: 66)
                        Text(s.gas).font(UIStyle.font(15)).foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 18)
                HStack {
                    Text(s.steer).frame(width: 72)
                    Spacer()
                    Text(s.thrust).frame(width: 72)
                }
                .font(UIStyle.font(11, .bold))
                .foregroundColor(Color.white.opacity(0.55))
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 16)
        }
        .frame(height: 250)
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State var confirmReset = false

    var body: some View {
        let s = app.s
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: s.settingsTitle) { app.go(.menu) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        LanguagePicker()
                        SettingToggle(icon: "speaker.wave.2.fill", title: s.soundEffects,
                                      subtitle: s.soundEffectsDetail, isOn: $app.soundOn)
                        SettingToggle(icon: "iphone.radiowaves.left.and.right", title: s.haptics,
                                      subtitle: s.hapticsDetail, isOn: $app.hapticsOn)
                        SettingToggle(icon: "arrow.left.arrow.right", title: s.leftHanded,
                                      subtitle: s.leftHandedDetail, isOn: $app.swapControls)
                        SettingToggle(icon: "lock.open.fill", title: s.unlockAll,
                                      subtitle: s.unlockAllDetail, isOn: $app.unlockAll)

                        Button {
                            SoundManager.shared.play(.click, volume: 0.6)
                            confirmReset = true
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(UIStyle.red)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(UIStyle.red.opacity(0.15)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.resetProgress).font(UIStyle.font(17)).foregroundColor(.white)
                                    Text(s.resetProgressDetail).font(UIStyle.font(13, .medium))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
                        }
                        .buttonStyle(PressableStyle())

                        VStack(spacing: 4) {
                            Text("THRUSTBOUND")
                                .font(UIStyle.font(16, .black))
                                .tracking(2)
                                .foregroundColor(UIStyle.cyan)
                            Text(s.version(appVersion, levels: app.levels.count))
                                .font(UIStyle.font(13, .medium))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(app.s.resetConfirmTitle, isPresented: $confirmReset) {
            Button(app.s.reset, role: .destructive) { app.resetProgress() }
            Button(app.s.cancel, role: .cancel) {}
        } message: {
            Text(app.account.isSignedIn ? app.s.resetConfirmMessage + " " + app.s.resetAlsoAccount : app.s.resetConfirmMessage)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct SettingToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(UIStyle.cyan)
                .frame(width: 40, height: 40)
                .background(Circle().fill(UIStyle.cyan.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UIStyle.font(17)).foregroundColor(.white)
                Text(subtitle).font(UIStyle.font(13, .medium)).foregroundColor(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(UIStyle.cyan)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

/// Language choice: follow the iPhone, or force English / Russian.
private struct LanguagePicker: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.s
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(UIStyle.cyan)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(UIStyle.cyan.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.languageTitle).font(UIStyle.font(17)).foregroundColor(.white)
                    Text(app.language == .system ? s.languageAuto(Lang.detect()) : s.languageManual)
                        .font(UIStyle.font(13, .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                chip(s.languageSystem, .system)
                chip("English", .english)
                chip("Русский", .russian)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func chip(_ title: String, _ option: AppLanguage) -> some View {
        let selected = app.language == option
        return Button {
            guard !selected else { return }
            SoundManager.shared.play(.click, volume: 0.6)
            Haptics.light()
            withAnimation(.easeInOut(duration: 0.2)) { app.language = option }
        } label: {
            Text(title)
                .font(UIStyle.font(15, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundColor(selected ? Color.black.opacity(0.85) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? UIStyle.cyan : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Color.white.opacity(0.5) : UIStyle.cyan.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle())
    }
}
