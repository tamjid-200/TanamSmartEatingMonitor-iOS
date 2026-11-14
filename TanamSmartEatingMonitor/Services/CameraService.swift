import AVFoundation
import CoreImage
import UIKit
import Combine

/// Front camera capture. Frames are delivered upright (portrait, mirrored) on a
/// background queue through `onFrame`, so Vision can use orientation `.up`.
class CameraService: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var cameraError: String?
    @Published var isAuthorized = false

    /// True if the device has a front camera (checked synchronously, no permission needed).
    let isFrontCameraAvailable: Bool

    /// Called on the video output queue for every frame (throttled).
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue", qos: .userInitiated)
    private var isConfigured = false

    // Throttle Vision to ~12 fps to save battery
    private var lastFrameTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 12.0

    override init() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        isFrontCameraAvailable = !discovery.devices.isEmpty
        super.init()
    }

    var captureSession: AVCaptureSession { session }

    /// Asks for camera permission if needed, configures once, then starts running.
    func startSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setAuthorized(true)
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.setAuthorized(granted)
                if granted {
                    self?.configureAndRun()
                } else {
                    self?.setError("Camera access denied. Turn it on in Settings → TANAM → Camera.")
                }
            }
        default:
            setAuthorized(false)
            setError("Camera access denied. Turn it on in Settings → TANAM → Camera.")
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            guard self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isSessionRunning = running
                if running { self.cameraError = nil }
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .vga640x480 // plenty for face landmarks, light on battery
        session.automaticallyConfiguresApplicationAudioSession = false

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        guard let camera = discovery.devices.first else {
            setError("Front camera not available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                setError("Could not use the front camera")
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: videoOutputQueue)
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

            guard session.canAddOutput(output) else {
                setError("Could not read camera frames")
                return
            }
            session.addOutput(output)

            // Deliver upright, mirrored portrait frames -> Vision orientation is `.up`
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            isConfigured = true
        } catch {
            setError("Camera setup failed: \(error.localizedDescription)")
        }
    }

    private func setError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.cameraError = message }
    }

    private func setAuthorized(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isAuthorized = value }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
