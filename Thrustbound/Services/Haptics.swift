import UIKit

@MainActor
enum Haptics {
    static var enabled = true

    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let notifyGen = UINotificationFeedbackGenerator()

    static func light() {
        guard enabled else { return }
        lightGen.impactOccurred()
    }

    static func medium() {
        guard enabled else { return }
        mediumGen.impactOccurred()
    }

    static func heavy() {
        guard enabled else { return }
        heavyGen.impactOccurred()
    }

    static func impact(_ intensity: CGFloat) {
        guard enabled else { return }
        mediumGen.impactOccurred(intensity: max(0.2, min(1, intensity)))
    }

    static func success() {
        guard enabled else { return }
        notifyGen.notificationOccurred(.success)
    }

    static func failure() {
        guard enabled else { return }
        notifyGen.notificationOccurred(.error)
    }
}
