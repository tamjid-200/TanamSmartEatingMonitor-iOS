import Foundation

enum SessionState: Equatable {
    case idle
    case watching
    case checkInDue(graceRemaining: Int)
    case locked(LockReason)
    case ended(SessionSummary)

    var isActive: Bool {
        switch self {
        case .watching, .checkInDue, .locked: return true
        case .idle, .ended: return false
        }
    }
}

enum LockReason: Equatable {
    case mouthNotEmpty
    case noFaceDetected
    case didntOpenInTime
    case backgrounded
    case sessionEnded

    var message: String {
        switch self {
        case .mouthNotEmpty: return "Finish chewing — mouth not empty!"
        case .noFaceDetected: return "Come back to the camera!"
        case .didntOpenInTime: return "Time to take a bite!"
        case .backgrounded: return "Welcome back! Verify to continue."
        case .sessionEnded: return "Session ended."
        }
    }
}

struct SessionSummary: Equatable {
    let duration: TimeInterval
    let passes: Int
    let locks: Int
    let startDate: Date
    let endDate: Date
}

struct CheckConfig: Equatable {
    var interval: TimeInterval = 50
    var gracePeriod: TimeInterval = 10
    var mouthOpenThreshold: Float = 0.35
    var mouthOpenDuration: TimeInterval = 1.0
    var requireEmptyMouth: Bool = true
    var emptyMouthSensitivity: Float = 0.6
    var mathDifficulty: MathDifficulty = .medium
    var requireRecheckOnUnlock: Bool = false
    var useYouTubeKids: Bool = false

    enum MathDifficulty: String, CaseIterable, Equatable {
        case easy = "Easy (1-10)"
        case medium = "Medium (10-50)"
        case hard = "Hard (50-100)"

        var range: ClosedRange<Int> {
            switch self {
            case .easy: return 1...10
            case .medium: return 10...50
            case .hard: return 50...100
            }
        }

        var displayName: String {
            return self.rawValue
        }
    }
}