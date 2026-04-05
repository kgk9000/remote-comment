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

    /// Capture a screenshot. Saves a resized image (for visual context) and
    /// an OCR text file (for accurate code reading) with matching timestamps.
    static func takeScreenshot(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970)

        guard let cgImage = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.screencaptureFailed
        }

        // OCR the full-resolution image before downscaling.
        let ocrText = recognizeText(in: cgImage)
        let txtPath = directory.appendingPathComponent("screenshot_\(timestamp).txt")
        try ocrText.write(to: txtPath, atomically: true, encoding: .utf8)

        // Downscale for the image file (used as visual context, not for reading code).
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

        // Save as JPEG — the image is just for visual context now, not code reading.
        let bitmapRep = NSBitmapImageRep(cgImage: resizedImage)
        let imagePath = directory.appendingPathComponent("screenshot_\(timestamp).jpg")
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) else {
            throw CaptureError.screencaptureFailed
        }
        try jpegData.write(to: imagePath)

        return imagePath
    }

    /// Run OCR on the full-resolution screenshot and return all recognized text.
    /// Uses the "accurate" recognition level for best results with code.
    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // don't "fix" variable names

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])

        guard let observations = request.results else { return "" }

        // Sort top-to-bottom, then left-to-right to preserve reading order.
        let sorted = observations.sorted { a, b in
            if abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.01 {
                return a.boundingBox.origin.y > b.boundingBox.origin.y  // top first (y is flipped)
            }
            return a.boundingBox.origin.x < b.boundingBox.origin.x
        }

        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
