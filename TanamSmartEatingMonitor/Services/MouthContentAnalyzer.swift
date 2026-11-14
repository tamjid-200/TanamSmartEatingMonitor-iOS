import CoreImage
import CoreVideo
import UIKit

/// Best-guess check of whether an open mouth looks empty.
/// An empty open mouth is mostly dark cavity, red/pink tongue and white teeth.
/// Anything else (brown, green, yellow, beige mush…) counts as "food-like".
/// This is a colour heuristic, not a perfect detector — tune `sensitivity` in Settings.
class MouthContentAnalyzer {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 0.0 = strict (little food-like colour allowed), 1.0 = lenient.
    var sensitivity: Float = 0.6

    /// - Parameters:
    ///   - innerLipRect: inner-lip bounding box in pixel coordinates, bottom-left origin
    ///     (same space as `VNFaceLandmarkRegion2D.pointsInImage` and CoreImage).
    func isMouthEmpty(pixelBuffer: CVPixelBuffer, innerLipRect: CGRect) -> Bool {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        // Shrink a little so lips themselves are excluded
        let region = innerLipRect.insetBy(dx: innerLipRect.width * 0.15, dy: innerLipRect.height * 0.15)
            .intersection(image.extent)
        guard region.width >= 6, region.height >= 4 else { return true } // too small to judge

        // Downscale crop to a small bitmap
        let targetWidth: CGFloat = 32
        let scale = min(1, targetWidth / region.width)
        let cropped = image.cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let w = max(Int(region.width * scale), 1)
        let h = max(Int(region.height * scale), 1)

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        ciContext.render(cropped,
                         toBitmap: &pixels,
                         rowBytes: w * 4,
                         bounds: CGRect(x: 0, y: 0, width: w, height: h),
                         format: .RGBA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        var mouthLike = 0
        var foodLike = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i]), g = Float(pixels[i + 1]), b = Float(pixels[i + 2])
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            let maxC = max(r, g, b), minC = min(r, g, b)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0

            let isDark = lum < 60                                   // throat / cavity
            let isRedPink = r > g * 1.25 && r > b * 1.1             // tongue, gums
            let isWhite = lum > 170 && sat < 0.18                   // teeth
            if isDark || isRedPink || isWhite {
                mouthLike += 1
            } else {
                foodLike += 1
            }
        }

        let total = Float(mouthLike + foodLike)
        guard total > 0 else { return true }
        let foodRatio = Float(foodLike) / total

        // strict: allow 20% food-like pixels … lenient: allow 70%
        let allowed = 0.2 + sensitivity * 0.5
        return foodRatio <= allowed
    }
}
