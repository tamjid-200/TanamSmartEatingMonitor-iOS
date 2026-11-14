import Foundation
import Combine
import SwiftUI
import AVFoundation
import WebKit

@MainActor
class SessionManager: ObservableObject {
    // Session state
    @Published var state: SessionState = .idle
    @Published var timeUntilNextCheck: TimeInterval = 0
    @Published var graceTimeRemaining: TimeInterval = 0
    @Published var lockReason: LockReason?
    @Published var sessionSummary: SessionSummary?
    @Published var sessionDuration: TimeInterval = 0
    @Published var isVideoPlaying = false

    // Stats
    @Published var passes = 0
    @Published var locks = 0

    // Lock maths question
    @Published var lockQuestion: String = ""
    @Published var lockAnswer: Int = 0

    // Settings
    @Published var config = CheckConfig() {
        didSet { applyDetectorSettings() }
    }

    // Services (their changes are forwarded to this object so SwiftUI refreshes)
    let cameraService = CameraService()
    let mouthDetector = MouthDetector()
    let notificationService = NotificationService()
    let webView: YouTubeWebView

    private var tickTimer: Timer?
    private var sessionStartTime: Date?
    private var lastFaceSeen = Date()
    private var mouthOpenSince: Date?
    private var emptyVotes = 0
    private var foodVotes = 0
    private var cancellables = Set<AnyCancellable>()

    /// How long without a face (while watching) before locking.
    private let noFaceLockSeconds: TimeInterval = 10

    init() {
        webView = YouTubeWebView.make()

        // Forward nested ObservableObject changes (otherwise the UI never updates)
        cameraService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        mouthDetector.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Camera frames → Vision (on the camera's background queue)
        let detector = mouthDetector
        cameraService.onFrame = { pixelBuffer in
            detector.process(pixelBuffer: pixelBuffer)
        }
        // Detection results → check-in logic (main thread)
        mouthDetector.onUpdate = { [weak self] in
            MainActor.assumeIsolated { self?.handleDetectionUpdate() }
        }

        NotificationCenter.default.publisher(for: .videoPlaybackStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                if let playing = note.userInfo?["playing"] as? Bool { self?.isVideoPlaying = playing }
            }
            .store(in: &cancellables)

        // Lock only when the app actually goes to the background
        // (not for permission alerts / Control Centre, which only "resign active").
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.appDidEnterBackground() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.appWillEnterForeground() }
            .store(in: &cancellables)

        applyDetectorSettings()
    }

    private func applyDetectorSettings() {
        mouthDetector.openThreshold = config.mouthOpenThreshold
        mouthDetector.emptyMouthSensitivity = config.emptyMouthSensitivity
        mouthDetector.analyzeMouthContent = config.requireEmptyMouth
    }

    // MARK: - Session control

    func startSession(useYouTubeKids: Bool = false) {
        guard state == .idle else { return }

        config.useYouTubeKids = useYouTubeKids
        passes = 0
        locks = 0
        sessionDuration = 0
        sessionStartTime = Date()
        lastFaceSeen = Date()
        resetOpenTracking()
        mouthDetector.reset()

        UIApplication.shared.isIdleTimerDisabled = true
        cameraService.startSession()
        webView.releasePause()
        webView.loadYouTube(useKids: useYouTubeKids)

        timeUntilNextCheck = config.interval
        state = .watching
        startTicking()
    }

    func stopSession() {
        guard state.isActive else { return }
        let summary = SessionSummary(
            duration: sessionDuration,
            passes: passes,
            locks: locks,
            startDate: sessionStartTime ?? Date(),
            endDate: Date()
        )
        sessionSummary = summary
        cleanup()
        state = .ended(summary)
    }

    func returnHome() {
        state = .idle
    }

    private func cleanup() {
        UIApplication.shared.isIdleTimerDisabled = false
        tickTimer?.invalidate()
        tickTimer = nil
        webView.pauseVideo()
        webView.releasePause()
        cameraService.stopSession()
        mouthDetector.reset()
        resetOpenTracking()
        sessionStartTime = nil
        timeUntilNextCheck = 0
        graceTimeRemaining = 0
        lockReason = nil
    }

    // MARK: - 1-second tick

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        guard state.isActive else { return }
        sessionDuration += 1

        switch state {
        case .watching:
            if timeUntilNextCheck > 1 {
                timeUntilNextCheck -= 1
            } else {
                timeUntilNextCheck = 0
                triggerCheckIn()
            }
        case .checkInDue:
            if graceTimeRemaining > 1 {
                graceTimeRemaining -= 1
                state = .checkInDue(graceRemaining: Int(graceTimeRemaining))
                notificationService.vibrateWarning()
            } else {
                lock(mouthDetector.faceDetected ? .didntOpenInTime : .noFaceDetected)
            }
        default:
            break
        }
    }

    // MARK: - Check-in

    private func triggerCheckIn() {
        guard state == .watching else { return }
        webView.pauseVideo()
        resetOpenTracking()
        graceTimeRemaining = config.gracePeriod
        state = .checkInDue(graceRemaining: Int(graceTimeRemaining))
        notificationService.vibrateWarning()
    }

    /// Called on the main thread after every processed camera frame.
    private func handleDetectionUpdate() {
        let now = Date()
        if mouthDetector.faceDetected { lastFaceSeen = now }

        switch state {
        case .watching:
            if now.timeIntervalSince(lastFaceSeen) > noFaceLockSeconds {
                lock(.noFaceDetected)
            }

        case .checkInDue:
            guard mouthDetector.faceDetected, mouthDetector.isMouthOpen else {
                resetOpenTracking()   // must hold the mouth open continuously
                return
            }
            if mouthOpenSince == nil { mouthOpenSince = now }
            if let empty = mouthDetector.mouthLooksEmpty {
                if empty { emptyVotes += 1 } else { foodVotes += 1 }
            }
            if let since = mouthOpenSince, now.timeIntervalSince(since) >= config.mouthOpenDuration {
                evaluateCheckIn()
            }

        default:
            break
        }
    }

    private func evaluateCheckIn() {
        if config.requireEmptyMouth && foodVotes > emptyVotes {
            lock(.mouthNotEmpty)
        } else {
            checkInPassed()
        }
    }

    private func checkInPassed() {
        passes += 1
        resetOpenTracking()
        notificationService.playSuccessSound()
        notificationService.vibrateSuccess()
        webView.releasePause()
        webView.playVideo()
        timeUntilNextCheck = config.interval
        lastFaceSeen = Date()
        state = .watching
    }

    private func resetOpenTracking() {
        mouthOpenSince = nil
        emptyVotes = 0
        foodVotes = 0
    }

    // MARK: - Lock

    private func lock(_ reason: LockReason) {
        guard state.isActive else { return }
        if case .locked = state { return }
        locks += 1
        resetOpenTracking()
        webView.pauseVideo()
        webView.enforcePaused()
        notificationService.playErrorSound()
        notificationService.vibrateError()
        lockReason = reason
        generateMathQuestion()
        state = .locked(reason)
    }

    private func generateMathQuestion() {
        let range = config.mathDifficulty.range
        let a = Int.random(in: range)
        let b = Int.random(in: range)
        if Bool.random() {
            lockQuestion = "\(a) + \(b) = ?"
            lockAnswer = a + b
        } else {
            lockQuestion = "\(max(a, b)) − \(min(a, b)) = ?"
            lockAnswer = max(a, b) - min(a, b)
        }
    }

    /// Returns true if the answer was correct.
    @discardableResult
    func submitLockAnswer(_ answer: String) -> Bool {
        guard let value = Int(answer), value == lockAnswer else {
            notificationService.vibrateWarning()
            generateMathQuestion()
            return false
        }
        unlock()
        return true
    }

    private func unlock() {
        lockReason = nil
        lastFaceSeen = Date()
        resetOpenTracking()
        if config.requireRecheckOnUnlock {
            // Video stays paused until the mouth check passes again
            graceTimeRemaining = config.gracePeriod
            state = .checkInDue(graceRemaining: Int(graceTimeRemaining))
        } else {
            webView.releasePause()
            webView.playVideo()
            timeUntilNextCheck = config.interval
            state = .watching
        }
    }

    // MARK: - App lifecycle

    private func appDidEnterBackground() {
        guard state.isActive else { return }
        lock(.backgrounded)
    }

    private func appWillEnterForeground() {
        if state.isActive {
            lastFaceSeen = Date()
            cameraService.startSession()
        }
    }

    // MARK: - YouTube

    func signOutOfYouTube() {
        webView.signOut(reloadKids: config.useYouTubeKids)
    }

    var isSessionActive: Bool { state.isActive }
}
