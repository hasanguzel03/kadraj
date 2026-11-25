import Foundation
import UIKit
import AudioToolbox

@MainActor
final class HapticAndSoundHelper {
    static let shared = HapticAndSoundHelper()

    var hapticsEnabled: Bool = true
    var shutterSoundEnabled: Bool = true

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        selectionFeedback.prepare()
        lightImpact.prepare()
        mediumImpact.prepare()
    }

    func triggerModeSwitch() {
        guard hapticsEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    func triggerFocusLock() {
        guard hapticsEnabled else { return }
        mediumImpact.impactOccurred(intensity: 0.75)
        mediumImpact.prepare()
    }

    func triggerHorizonLevelTick() {
        guard hapticsEnabled else { return }
        lightImpact.impactOccurred(intensity: 0.6)
        lightImpact.prepare()
    }

    func triggerNeutralSnapTick() {
        guard hapticsEnabled else { return }
        lightImpact.impactOccurred(intensity: 0.45)
    }

    func triggerShutterPress() {
        guard hapticsEnabled else { return }
        heavyImpact.impactOccurred(intensity: 0.85)
    }

    func triggerCaptureConfirmation() {
        guard hapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()
    }

    func playShutterClick() {
        guard shutterSoundEnabled else { return }
        AudioServicesPlaySystemSound(1108)
    }

    func playRecordStart() {
        guard shutterSoundEnabled else { return }
        AudioServicesPlaySystemSound(1117)
    }

    func playRecordStop() {
        guard shutterSoundEnabled else { return }
        AudioServicesPlaySystemSound(1118)
    }
}
