import AppKit
import Foundation
import Vision

enum ScreenCapture {
    /// Claude's vision API downscales anything over 1568px on the long edge,
    /// so there's no benefit to sending larger images.
    static let maxDimension: CGFloat = 1568
    static let maxImageBytes = 5 * 1024 * 1024  // 5MB API limit
    static let similarityThreshold: Float = 0.05

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return true
        }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Int, locked == 1 { return true }
        return false
    }

    /// Capture a screenshot, resize to fit Claude's vision limits, and save as PNG.
    /// PNG is lossless — much better than JPEG for reading code text.
    static func takeScreenshot(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970)
        let pngPath = directory.appendingPathComponent("screenshot_\(timestamp).png")

        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.screencaptureFailed
        }

        // Scale down to maxDimension on the long edge.
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxDimension / width, maxDimension / height, 1.0)
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CaptureError.screencaptureFailed
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedImage = ctx.makeImage() else {
            throw CaptureError.screencaptureFailed
        }

        let bitmapRep = NSBitmapImageRep(cgImage: resizedImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw CaptureError.screencaptureFailed
        }

        // If PNG is over the API limit, fall back to high-quality JPEG.
        if pngData.count > maxImageBytes {
            let jpegPath = directory.appendingPathComponent("screenshot_\(timestamp).jpg")
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.90]) else {
                throw CaptureError.screencaptureFailed
            }
            try jpegData.write(to: jpegPath)
            return jpegPath
        }

        try pngData.write(to: pngPath)
        return pngPath
    }

    static func featurePrint(for imageURL: URL) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: imageURL)
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    static func isSimilar(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Bool {
        var distance: Float = 0
        try? a.computeDistance(&distance, to: b)
        return distance < similarityThreshold
    }
}

enum CaptureError: LocalizedError {
    case screencaptureFailed
    case rsyncFailed(String)

    var errorDescription: String? {
        switch self {
        case .screencaptureFailed:
            return "Screenshot failed. Grant Screen Recording permission in System Settings."
        case .rsyncFailed(let msg):
            return "rsync failed: \(msg)"
        }
    }
}
