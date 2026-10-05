import SwiftUI

struct HowToPlayView: View {
    @EnvironmentObject var app: AppModel

    private struct Tip {
        let icon: String
        let color: Color
        let title: String
        let text: String
    }

    private static let tips: [Tip] = [
        Tip(icon: "gamecontroller.fill", color: UIStyle.cyan, title: "Steer",
            text: "Drag the stick on the left. Your rocket turns to point its nose the way you push."),
        Tip(icon: "flame.fill", color: UIStyle.orange, title: "Gas",
            text: "Hold GAS on the right to fire the engine. Gravity always pulls you down, so tap it in short bursts to hover."),
        Tip(icon: "arrow.down.to.line", color: UIStyle.green, title: "Land",
            text: "Touch down on the green pad slowly and upright. Keep the speed meter out of the red and hold still for a moment."),
        Tip(icon: "star.fill", color: UIStyle.gold, title: "Stars",
            text: "Each level hides three stars. Grab them and land to keep them. Can you get all 120?"),
        Tip(icon: "fuelpump.fill", color: UIStyle.orange, title: "Fuel",
            text: "Your tank is limited. Orange cans give you more fuel. Rotating is free, only thrust burns fuel."),
        Tip(icon: "exclamationmark.triangle.fill", color: UIStyle.red, title: "Danger",
            text: "Anything red destroys your rocket: spikes, mines, spinning blades and lasers. Hitting rock too fast is fatal too."),
        Tip(icon: "wind", color: Color(hex: "#8FD3FF"), title: "Wind",
            text: "Streaming blue zones push your rocket around. Lean into the wind or let it carry you."),
        Tip(icon: "key.fill", color: Color(hex: "#FFC23D"), title: "Keys",
            text: "Doors block the way until you collect the key with the same colour.")
    ]

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "How to Play") { app.go(.menu) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ControlsDiagram()
                            .padding(.bottom, 6)
                        ForEach(Self.tips, id: \.title) { tip in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: tip.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(tip.color)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(tip.color.opacity(0.15)))
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
                        ActionButton(title: "LET'S FLY", icon: "play.fill", kind: .primary) {
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
                        Text("GAS").font(UIStyle.font(15)).foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 18)
                HStack {
                    Text("STEER").frame(width: 72)
                    Spacer()
                    Text("THRUST").frame(width: 72)
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
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings") { app.go(.menu) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        SettingToggle(icon: "speaker.wave.2.fill", title: "Sound effects",
                                      subtitle: "Engine, pickups and explosions", isOn: $app.soundOn)
                        SettingToggle(icon: "iphone.radiowaves.left.and.right", title: "Haptics",
                                      subtitle: "Vibration on landings, bumps and crashes", isOn: $app.hapticsOn)
                        SettingToggle(icon: "arrow.left.arrow.right", title: "Left-handed controls",
                                      subtitle: "Put GAS on the left and the stick on the right", isOn: $app.swapControls)
                        SettingToggle(icon: "lock.open.fill", title: "Unlock all levels",
                                      subtitle: "Play any level without finishing the previous one", isOn: $app.unlockAll)

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
                                    Text("Reset progress").font(UIStyle.font(17)).foregroundColor(.white)
                                    Text("Clears stars and best times").font(UIStyle.font(13, .medium))
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
                            Text("Version \(appVersion) · \(app.levels.count) levels")
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
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { app.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your stars and best times will be erased. This can't be undone.")
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
