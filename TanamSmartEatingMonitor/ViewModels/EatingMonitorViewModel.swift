import Foundation
import Combine
import SwiftUI

class EatingMonitorViewModel: ObservableObject {
    @Published var cycleDuration: Int = 90
    @Published var countdownStart: Int = 50
    @Published var enableScreenLock: Bool = false
    @Published var soundEnabled: Bool = true
    @Published var vibrationEnabled: Bool = true
    @Published var showOverlayTimer: Bool = true

    @Published var isMonitoring = false
    @Published var currentCycleSeconds: Int = 0
    @Published var isInCountdown = false
    @Published var countdownSeconds: Int = 0
    @Published var isMouthOpen = false
    @Published var mouthOpenness: Float = 0.0
    @Published var lastCycleSuccess: Bool?
    @Published var cyclesCompleted: Int = 0

    @Published var cameraError: String?
    @Published var detectionError: String?

    private var cycleTimer: Timer?
    private var countdownTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let preferences = PreferencesManager.shared
    weak var notificationService: NotificationService?

    init() {
        loadPreferences()
        setupBindings()
    }

    func loadPreferences() {
        cycleDuration = preferences.cycleDuration
        countdownStart = preferences.countdownStart
        enableScreenLock = preferences.enableScreenLock
        soundEnabled = preferences.soundEnabled
        vibrationEnabled = preferences.vibrationEnabled
        showOverlayTimer = preferences.showOverlayTimer
    }

    private func setupBindings() {
        $cycleDuration.dropFirst().sink { [weak self] value in self?.preferences.cycleDuration = value }.store(in: &cancellables)
        $countdownStart.dropFirst().sink { [weak self] value in self?.preferences.countdownStart = value }.store(in: &cancellables)
        $enableScreenLock.dropFirst().sink { [weak self] value in self?.preferences.enableScreenLock = value }.store(in: &cancellables)
        $soundEnabled.dropFirst().sink { [weak self] value in self?.preferences.soundEnabled = value }.store(in: &cancellables)
        $vibrationEnabled.dropFirst().sink { [weak self] value in self?.preferences.vibrationEnabled = value }.store(in: &cancellables)
        $showOverlayTimer.dropFirst().sink { [weak self] value in self?.preferences.showOverlayTimer = value }.store(in: &cancellables)
        $isMonitoring.dropFirst().sink { [weak self] value in self?.preferences.isMonitoringActive = value }.store(in: &cancellables)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        currentCycleSeconds = cycleDuration
        isInCountdown = false
        countdownSeconds = countdownStart
        lastCycleSuccess = nil

        startCycleTimer()
    }

    func stopMonitoring() {
        isMonitoring = false
        cycleTimer?.invalidate()
        cycleTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        isInCountdown = false
    }

    private func startCycleTimer() {
        cycleTimer?.invalidate()
        currentCycleSeconds = cycleDuration

        cycleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            if self.currentCycleSeconds > 0 {
                self.currentCycleSeconds -= 1

                if self.currentCycleSeconds == self.countdownStart && !self.isInCountdown {
                    self.startCountdown()
                }
            } else {
                self.onCycleComplete()
            }
        }

        RunLoop.main.add(cycleTimer!, forMode: .common)
    }

    private func startCountdown() {
        isInCountdown = true
        countdownSeconds = countdownStart

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            if self.countdownSeconds > 0 {
                self.countdownSeconds -= 1

                if self.soundEnabled {
                    self.notificationService?.playCountdownSound(remaining: self.countdownSeconds)
                }

                if self.vibrationEnabled && self.countdownSeconds <= 5 {
                    self.notificationService?.vibrateWarning()
                }
            } else {
                self.onCountdownComplete()
            }
        }

        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    private func onCountdownComplete() {
        isInCountdown = false
        countdownTimer?.invalidate()
        countdownTimer = nil

        let success = isMouthOpen
        lastCycleSuccess = success

        if success {
            cyclesCompleted += 1
            if soundEnabled { notificationService?.playSuccessSound() }
            if vibrationEnabled { notificationService?.vibrateSuccess() }
            notificationService?.sendCycleCompleteNotification(success: true)
        } else {
            if soundEnabled { notificationService?.playErrorSound() }
            if vibrationEnabled { notificationService?.vibrateError() }
            notificationService?.sendCycleCompleteNotification(success: false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startCycleTimer()
        }
    }

    private func onCycleComplete() {
        cycleTimer?.invalidate()
        cycleTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startCycleTimer()
        }
    }

    func updateMouthState(isOpen: Bool, openness: Float) {
        isMouthOpen = isOpen
        mouthOpenness = openness
    }

    var progress: Double {
        guard cycleDuration > 0 else { return 0 }
        return 1.0 - (Double(currentCycleSeconds) / Double(cycleDuration))
    }

    var countdownProgress: Double {
        guard countdownStart > 0 else { return 0 }
        return 1.0 - (Double(countdownSeconds) / Double(countdownStart))
    }

    var cycleStatusText: String {
        if !isMonitoring { return "Ready to start" }
        else if isInCountdown { return "Countdown: \(countdownSeconds)s" }
        else { return "Cycle: \(currentCycleSeconds)s" }
    }
}