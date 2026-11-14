import Vision
import CoreImage
import Combine
import UIKit

/// Runs Vision face landmarks on camera frames (called on the camera's video queue)
/// and publishes face / mouth state on the main thread.
class MouthDetector: ObservableObject {
    @Published var faceDetected = false
    @Published var mouthOpenness: Float = 0.0      // 0 = closed, 1 = wide open
    @Published var isMouthOpen = false
    /// Result of the empty-mouth analysis for the latest open-mouth frame (nil = not analysed).
    @Published var mouthLooksEmpty: Bool?
    @Published var detectionError: String?
    @Published var faceBounds: CGRect = .zero

    /// Called on the main thread after every processed frame.
    var onUpdate: (() -> Void)?

    // Settings (written from main, read on the video queue; simple values)
    var openThreshold: Float = 0.35
    var analyzeMouthContent = false
    var emptyMouthSensitivity: Float = 0.6

    private let sequenceHandler = VNSequenceRequestHandler()
    private let contentAnalyzer = MouthContentAnalyzer()
    private var opennessHistory: [Float] = []
    private let historySize = 4

    /// Process one upright (portrait, mirrored) frame. Call on a background queue.
    func process(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceLandmarksRequest()
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            publish(face: false, openness: 0, bounds: .zero, empty: nil, error: error.localizedDescription)
            return
        }

        guard let face = (request.results)?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              face.boundingBox.width > 0.12 else {
            opennessHistory.removeAll()
            publish(face: false, openness: 0, bounds: .zero, empty: nil, error: nil)
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageSize = CGSize(width: width, height: height)

        guard let landmarks = face.landmarks,
              let inner = landmarks.innerLips,
              let outer = landmarks.outerLips else {
            publish(face: true, openness: 0, bounds: face.boundingBox, empty: nil, error: nil)
            return
        }

        // Pixel coordinates (Vision / CoreImage space: origin bottom-left)
        let innerPts = inner.pointsInImage(imageSize: imageSize)
        let outerPts = outer.pointsInImage(imageSize: imageSize)
        guard innerPts.count >= 3, outerPts.count >= 3 else {
            publish(face: true, openness: 0, bounds: face.boundingBox, empty: nil, error: nil)
            return
        }

        // Mouth aspect ratio: inner-lip gap height / outer mouth width
        let innerYs = innerPts.map { $0.y }
        let outerXs = outerPts.map { $0.x }
        let gap = (innerYs.max() ?? 0) - (innerYs.min() ?? 0)
        let mouthWidth = max((outerXs.max() ?? 0) - (outerXs.min() ?? 0), 1)
        let ratio = Float(gap / mouthWidth)

        // closed ≈ 0.0–0.12, wide open ≈ 0.5+  →  map to 0…1
        let raw = min(max((ratio - 0.08) / 0.45, 0), 1)
        opennessHistory.append(raw)
        if opennessHistory.count > historySize { opennessHistory.removeFirst() }
        let smoothed = opennessHistory.reduce(0, +) / Float(opennessHistory.count)

        // Empty-mouth check only while the mouth is clearly open
        var empty: Bool?
        if analyzeMouthContent && smoothed > openThreshold {
            let xs = innerPts.map { $0.x }
            let region = CGRect(
                x: xs.min() ?? 0,
                y: innerYs.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: gap
            )
            contentAnalyzer.sensitivity = emptyMouthSensitivity
            empty = contentAnalyzer.isMouthEmpty(pixelBuffer: pixelBuffer, innerLipRect: region)
        }

        publish(face: true, openness: smoothed, bounds: face.boundingBox, empty: empty, error: nil)
    }

    private func publish(face: Bool, openness: Float, bounds: CGRect, empty: Bool?, error: String?) {
        let threshold = openThreshold
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.faceDetected != face { self.faceDetected = face }
            // Only publish visible changes to avoid re-rendering every frame
            let rounded = (openness * 50).rounded() / 50
            if abs(self.mouthOpenness - rounded) > 0.001 { self.mouthOpenness = rounded }
            let open = face && openness > threshold
            if self.isMouthOpen != open { self.isMouthOpen = open }
            if self.mouthLooksEmpty != empty { self.mouthLooksEmpty = empty }
            if self.detectionError != error { self.detectionError = error }
            self.faceBounds = bounds
            self.onUpdate?()
        }
    }

    func reset() {
        opennessHistory.removeAll()
        isMouthOpen = false
        mouthOpenness = 0
        faceDetected = false
        mouthLooksEmpty = nil
        faceBounds = .zero
        detectionError = nil
    }
}
