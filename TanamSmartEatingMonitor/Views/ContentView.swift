import SwiftUI
import WebKit
import AVFoundation

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()
    @State private var showingSettings = false
    @State private var showingYouTubeKidsOption = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if sessionManager.state == .idle {
                    StartScreenView(sessionManager: sessionManager,
                                    showYouTubeKidsOption: $showingYouTubeKidsOption,
                                    showingSettings: $showingSettings)
                } else if case .ended(let summary) = sessionManager.state {
                    EndScreenView(summary: summary, sessionManager: sessionManager)
                } else {
                    // Active session: status bar + YouTube + info bar
                    StatusBarView(sessionManager: sessionManager)
                    ActiveSessionView(sessionManager: sessionManager)
                }
            }

            // Lock overlay sits ON TOP of everything (blocks all touches on the video)
            if case .locked(let reason) = sessionManager.state {
                LockOverlayView(sessionManager: sessionManager, reason: reason)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(sessionManager: sessionManager)
        }
        .sheet(isPresented: $showingYouTubeKidsOption) {
            YouTubeKidsOptionView(sessionManager: sessionManager, isPresented: $showingYouTubeKidsOption)
        }
        .onAppear {
            sessionManager.notificationService.requestAuthorization()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessionManager.state)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        HStack(spacing: 14) {
            // Live camera thumbnail so the child can see they're in frame
            CameraPreviewView(session: sessionManager.cameraService.captureSession)
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(sessionManager.mouthDetector.faceDetected ? Color.green : Color.red, lineWidth: 2)
                )

            // Next Check Countdown
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT CHECK")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                Text("\(Int(sessionManager.timeUntilNextCheck))s")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Divider()
                .frame(height: 32)

            // Mouth State
            HStack(spacing: 6) {
                Image(systemName: sessionManager.mouthDetector.isMouthOpen ? "mouth.fill" : "mouth")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(sessionManager.mouthDetector.isMouthOpen ? .green : .secondary)
                    .symbolEffect(.bounce, value: sessionManager.mouthDetector.isMouthOpen)
                Text(sessionManager.mouthDetector.isMouthOpen ? "OPEN" : "CLOSED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(sessionManager.mouthDetector.isMouthOpen ? .green : .secondary)
                    .tracking(0.5)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        )
    }
}

/// Live front-camera preview (mirrored, like a selfie).
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Start Screen

struct StartScreenView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showYouTubeKidsOption: Bool
    @Binding var showingSettings: Bool
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Logo/Title
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.pulse, options: .repeating, value: animateIn)

                VStack(spacing: 4) {
                    Text("TANAM")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .tracking(4)
                    Text("Smart Eating Monitor")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .tracking(2)
                }
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)

            Spacer()

            // Description
            VStack(spacing: 16) {
                FeatureRow(icon: "video.fill", title: "Watch YouTube", description: "Enjoy videos while we monitor your eating cycles")
                FeatureRow(icon: "camera.fill", title: "Face Detection", description: "Front camera tracks mouth openness in real-time")
                FeatureRow(icon: "checkmark.circle.fill", title: "Periodic Checks", description: "Open your mouth when prompted to continue watching")
                FeatureRow(icon: "lock.fill", title: "Smart Lock", description: "Solve a quick math question to unlock if you miss a check")
            }
            .padding(.horizontal, 24)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)

            Spacer()

            if let error = sessionManager.cameraService.cameraError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else if !sessionManager.cameraService.isFrontCameraAvailable {
                Text("No front camera found on this device.")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }

            // Start Button
            Button(action: {
                showYouTubeKidsOption = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.semibold))
                    Text("Start Session")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                animateIn = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - YouTube Kids Option

struct YouTubeKidsOptionView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "figure.and.child.holdinghands")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange.gradient)

                VStack(spacing: 8) {
                    Text("Which YouTube?")
                        .font(.title2.weight(.bold))
                    Text("Choose your viewing experience")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    Button(action: {
                        isPresented = false
                        sessionManager.startSession(useYouTubeKids: false)
                    }) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YouTube")
                                    .font(.headline)
                                Text("Standard YouTube (m.youtube.com)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        isPresented = false
                        sessionManager.startSession(useYouTubeKids: true)
                    }) {
                        HStack {
                            Image(systemName: "figure.and.child.holdinghands")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("YouTube Kids")
                                    .font(.headline)
                                Text("Child-friendly content (youtubekids.com)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Select YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showCheckInBanner = false
    @State private var checkInBannerText = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // YouTube WebView (the same instance for the whole app run)
                YouTubePlayerView(webView: sessionManager.webView)

                // Check-in banner over the video
                if case .checkInDue(let graceRemaining) = sessionManager.state {
                    CheckInBannerView(graceRemaining: graceRemaining, sessionManager: sessionManager)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Session info bar under the video (doesn't cover YouTube's controls)
            SessionInfoBar(sessionManager: sessionManager)
        }
    }
}

struct YouTubePlayerView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct CheckInBannerView: View {
    let graceRemaining: Int
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.orange.gradient)
                        .frame(width: 44, height: 44)

                    Image(systemName: "mouth.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, options: .repeating)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MOUTH CHECK")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .tracking(1)
                    Text("Open your mouth wide to continue watching")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: CGFloat(graceRemaining) / CGFloat(sessionManager.config.gracePeriod))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: graceRemaining)

                    Text("\(graceRemaining)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.orange.gradient)
                    .shadow(color: .orange.opacity(0.4), radius: 16, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Mouth openness indicator
            if sessionManager.mouthDetector.faceDetected {
                MouthOpennessIndicator(openness: sessionManager.mouthDetector.mouthOpenness, isOpen: sessionManager.mouthDetector.isMouthOpen)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
    }
}

struct MouthOpennessIndicator: View {
    let openness: Float
    let isOpen: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MOUTH OPENNESS")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Text("\(Int(openness * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(isOpen ? .green : .orange)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOpen ? Color.green : Color.orange)
                        .frame(width: geo.size.width * CGFloat(openness), height: 12)
                        .animation(.easeOut(duration: 0.15), value: openness)
                }
            }
            .frame(height: 12)

            HStack {
                Text("CLOSED")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("OPEN")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
}

struct SessionInfoBar: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showSignOut = false
    @State private var showStopConfirm = false

    var body: some View {
        HStack(spacing: 16) {
            // Session duration
            VStack(alignment: .leading, spacing: 2) {
                Text("SESSION")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Text(formatDuration(sessionManager.sessionDuration))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Divider()
                .frame(height: 36)

            // Passes
            VStack(alignment: .leading, spacing: 2) {
                Text("PASSES")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Text("\(sessionManager.passes)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                    .monospacedDigit()
            }

            Divider()
                .frame(height: 36)

            // Locks
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCKS")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Text("\(sessionManager.locks)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }

            Spacer()

            // Stop Button
            Button(action: {
                showStopConfirm = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("END")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(12)
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        )
        .confirmationDialog("Finished eating?", isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { sessionManager.stopSession() }
            Button("Keep Watching", role: .cancel) {}
        } message: {
            Text("This stops the camera and the video.")
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Lock Overlay

struct LockOverlayView: View {
    @ObservedObject var sessionManager: SessionManager
    let reason: LockReason
    @State private var shake = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 28) {
                // Lock Icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange.gradient)
                    .symbolEffect(.bounce, value: shake)

                // Reason Text
                VStack(spacing: 8) {
                    Text(lockTitle)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(lockMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Math Question
                VStack(spacing: 16) {
                    Text(sessionManager.lockQuestion)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .tracking(8)

                    // Number Pad
                    NumberPadView(sessionManager: sessionManager, shake: $shake)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 32, y: 16)
            )
            .padding(.horizontal, 24)
            .offset(x: shake ? 10 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.3), value: shake)
        }
    }

    var lockTitle: String {
        switch reason {
        case .didntOpenInTime: return "Missed Check"
        case .mouthNotEmpty: return "Mouth Not Empty"
        case .noFaceDetected: return "No Face Detected"
        case .backgrounded: return "App Backgrounded"
        case .sessionEnded: return "Session Ended"
        }
    }

    var lockMessage: String {
        switch reason {
        case .didntOpenInTime: return "You didn't open your mouth in time. Solve the math to continue."
        case .mouthNotEmpty: return "Food detected in your mouth. Finish chewing and solve the math to continue."
        case .noFaceDetected: return "Your face wasn't visible. Position yourself in front of the camera and solve the math."
        case .backgrounded: return "You left the app. Solve the math to resume your session."
        case .sessionEnded: return "Your session has ended."
        }
    }
}

// Need to add LockReason cases that were added to the enum
extension LockReason {
    var allCases: [LockReason] {
        [.mouthNotEmpty, .noFaceDetected, .didntOpenInTime, .backgrounded, .sessionEnded]
    }
}

struct NumberPadView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var shake: Bool
    @State private var input = ""

    let columns = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["⌫", "0", "✓"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Input Display
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 56)

                Text(input.isEmpty ? " " : input)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
            .frame(width: 200)

            // Keypad
            VStack(spacing: 10) {
                ForEach(columns, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            NumberKey(key: key, action: { handleKey(key) })
                        }
                    }
                }
            }
        }
    }

    func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !input.isEmpty {
                input.removeLast()
            }
        case "✓":
            submitAnswer()
        default:
            if input.count < 4 {
                input.append(key)
            }
        }
    }

    func submitAnswer() {
        let correct = sessionManager.submitLockAnswer(input)
        if !correct {
            // Wrong answer - shake
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                    shake = false
                }
            }
            input = ""
        } else {
            input = ""
        }
    }
}

struct NumberKey: View {
    let key: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.08)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.08)) { pressed = false }
            }
            action()
        }) {
            Text(key)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(keyColor)
                .frame(width: 64, height: 64)
                .background(keyBackground)
                .cornerRadius(16)
                .scaleEffect(pressed ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.08), value: pressed)
        }
        .buttonStyle(.plain)
    }

    var keyColor: Color {
        if key == "⌫" || key == "✓" { return .primary }
        return .primary
    }

    var keyBackground: Color {
        if key == "✓" { return Color.green.opacity(0.2) }
        if key == "⌫" { return Color(.systemGray5) }
        return Color(.systemGray6)
    }
}

// MARK: - End Screen

struct EndScreenView: View {
    let summary: SessionSummary
    @ObservedObject var sessionManager: SessionManager
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: animateIn)

            VStack(spacing: 8) {
                Text("Session Complete")
                    .font(.title.weight(.bold))
                Text("Great job staying mindful!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)

            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                StatCard(title: "Duration", value: formatDuration(summary.duration), icon: "clock.fill", color: .blue)
                StatCard(title: "Passes", value: "\(summary.passes)", icon: "checkmark.circle.fill", color: .green)
                StatCard(title: "Locks", value: "\(summary.locks)", icon: "lock.fill", color: .orange)
                StatCard(title: "Success Rate", value: summary.passes > 0 ? "\(Int(Double(summary.passes) / Double(summary.passes + summary.locks) * 100))%" : "—", icon: "chart.line.uptrend.xyaxis", color: .purple)
            }
            .padding(.horizontal, 24)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)

            Spacer()

            Button(action: {
                sessionManager.state = .idle
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3.weight(.semibold))
                    Text("New Session")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                animateIn = true
            }
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color.gradient)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Check-in Settings") {
                    Stepper("Check Interval: \(Int(sessionManager.config.interval))s", value: Binding(
                        get: { Int(sessionManager.config.interval) },
                        set: { sessionManager.config.interval = TimeInterval($0) }
                    ), in: 20...600, step: 10)

                    Stepper("Grace Period: \(Int(sessionManager.config.gracePeriod))s", value: Binding(
                        get: { Int(sessionManager.config.gracePeriod) },
                        set: { sessionManager.config.gracePeriod = TimeInterval($0) }
                    ), in: 5...60, step: 5)

                    Toggle("Require Empty Mouth Check", isOn: $sessionManager.config.requireEmptyMouth)

                    if sessionManager.config.requireEmptyMouth {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Empty Mouth Sensitivity")
                                Spacer()
                                Text(String(format: "%.0f%%", sessionManager.config.emptyMouthSensitivity * 100))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $sessionManager.config.emptyMouthSensitivity, in: 0...1)
                                .tint(.blue)
                        }
                    }
                }

                Section("Lock Settings") {
                    Picker("Math Difficulty", selection: $sessionManager.config.mathDifficulty) {
                        ForEach(CheckConfig.MathDifficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.displayName).tag(difficulty)
                        }
                    }

                    Toggle("Re-check on Unlock", isOn: $sessionManager.config.requireRecheckOnUnlock)
                }

                Section("YouTube Settings") {
                    Toggle("Use YouTube Kids by Default", isOn: $sessionManager.config.useYouTubeKids)
                }

                Section("Keep the child inside the app") {
                    Text("Turn on Guided Access: iPhone Settings → Accessibility → Guided Access. Then open TANAM and triple-click the side button to start. Triple-click again and enter your passcode to leave.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("iOS Native")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button("Sign Out of YouTube", role: .destructive) {
                        sessionManager.signOutOfYouTube()
                    }

                    Button("Reset All Settings", role: .destructive) {
                        sessionManager.config = CheckConfig()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

