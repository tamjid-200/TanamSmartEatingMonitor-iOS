import UserNotifications
import AVFoundation
import AudioToolbox
import Combine
import UIKit

class NotificationService: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationError: String?

    init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    self?.authorizationError = error.localizedDescription
                }
            }
        }
    }

    func sendCycleStartNotification(cycleDuration: Int) {
        let content = UNMutableNotificationContent()
        content.title = "TANAM Eating Monitor"
        content.body = "Eating cycle started - \(cycleDuration) seconds"
        content.sound = .none
        content.categoryIdentifier = "CYCLE_START"

        let request = UNNotificationRequest(
            identifier: "cycle_start_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    func sendCountdownNotification(remaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "TANAM Countdown"
        content.body = "\(remaining)s - Open your mouth!"
        content.sound = .default
        content.categoryIdentifier = "COUNTDOWN"

        let request = UNNotificationRequest(
            identifier: "countdown_\(remaining)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    func sendCycleCompleteNotification(success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = success ? "TANAM - Success!" : "TANAM - Try Again"
        content.body = success ? "Mouth was open at cycle end. Great job!" : "Mouth was closed at cycle end. Try again next cycle."
        content.sound = success ? .default : .defaultCritical
        content.categoryIdentifier = "CYCLE_COMPLETE"

        let request = UNNotificationRequest(
            identifier: "cycle_complete_\(success)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    func playCountdownSound(remaining: Int) {
        guard remaining <= 10 && remaining > 0 else { return }

        let soundID: SystemSoundID
        switch remaining {
        case 10: soundID = 1103
        case 9: soundID = 1104
        case 8: soundID = 1105
        case 7: soundID = 1106
        case 6: soundID = 1107
        case 5: soundID = 1108
        case 4: soundID = 1109
        case 3: soundID = 1110
        case 2: soundID = 1111
        case 1: soundID = 1112
        default: soundID = 1103
        }
        AudioServicesPlaySystemSound(soundID)
    }

    func playSuccessSound() {
        AudioServicesPlaySystemSound(1025)
    }

    func playErrorSound() {
        AudioServicesPlaySystemSound(1006)
    }

    func vibrateSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func vibrateError() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    func vibrateWarning() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}