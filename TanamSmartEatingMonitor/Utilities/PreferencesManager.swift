import Foundation
import Combine

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let userDefaults = UserDefaults.standard

    private enum Keys {
        static let cycleDuration = "cycleDuration"
        static let countdownStart = "countdownStart"
        static let enableScreenLock = "enableScreenLock"
        static let isMonitoringActive = "isMonitoringActive"
        static let soundEnabled = "soundEnabled"
        static let vibrationEnabled = "vibrationEnabled"
        static let showOverlayTimer = "showOverlayTimer"
    }

    @Published var cycleDuration: Int {
        didSet { userDefaults.set(cycleDuration, forKey: Keys.cycleDuration) }
    }

    @Published var countdownStart: Int {
        didSet { userDefaults.set(countdownStart, forKey: Keys.countdownStart) }
    }

    @Published var enableScreenLock: Bool {
        didSet { userDefaults.set(enableScreenLock, forKey: Keys.enableScreenLock) }
    }

    @Published var isMonitoringActive: Bool {
        didSet { userDefaults.set(isMonitoringActive, forKey: Keys.isMonitoringActive) }
    }

    @Published var soundEnabled: Bool {
        didSet { userDefaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    @Published var vibrationEnabled: Bool {
        didSet { userDefaults.set(vibrationEnabled, forKey: Keys.vibrationEnabled) }
    }

    @Published var showOverlayTimer: Bool {
        didSet { userDefaults.set(showOverlayTimer, forKey: Keys.showOverlayTimer) }
    }

    private init() {
        self.cycleDuration = userDefaults.object(forKey: Keys.cycleDuration) as? Int ?? 90
        self.countdownStart = userDefaults.object(forKey: Keys.countdownStart) as? Int ?? 50
        self.enableScreenLock = userDefaults.object(forKey: Keys.enableScreenLock) as? Bool ?? false
        self.isMonitoringActive = userDefaults.object(forKey: Keys.isMonitoringActive) as? Bool ?? false
        self.soundEnabled = userDefaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        self.vibrationEnabled = userDefaults.object(forKey: Keys.vibrationEnabled) as? Bool ?? true
        self.showOverlayTimer = userDefaults.object(forKey: Keys.showOverlayTimer) as? Bool ?? true
    }

    func resetToDefaults() {
        cycleDuration = 90
        countdownStart = 50
        enableScreenLock = false
        isMonitoringActive = false
        soundEnabled = true
        vibrationEnabled = true
        showOverlayTimer = true
    }
}