import AppKit
import Foundation
import Vision

enum ScreenCapture {
    /// Claude's vision API downscales anything over 1568px on the long edge.
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

    /// Find the window ID of the frontmost application's main window.
    /// Returns nil if no suitable window is found.
    static func frontmostWindowID() -> CGWindowID? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find the first on-screen window belonging to the frontmost app.
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  w > 100 && h > 100  // skip tiny windows (toolbars, popovers)
            else { continue }
            return windowID
        }
        return nil
    }

    /// Capture a screenshot. Takes a full-screen image for visual context, and
    /// OCRs just the frontmost window for accurate code reading.
    static func takeScreenshot(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970)

        // Full-screen capture for the image sent to Claude as visual context.
        guard let fullScreen = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.screencaptureFailed
        }

        // OCR just the frontmost window for clean text extraction.
        let ocrText: String
        if let windowID = frontmostWindowID(),
           let windowImage = CGWindowListCreateImage(
               CGRect.null,
               .optionIncludingWindow,
               windowID,
               [.bestResolution, .boundsIgnoreFraming]
           ) {
            ocrText = recognizeText(in: windowImage)
            print("OCR: frontmost window (\(windowImage.width)x\(windowImage.height))")
        } else {
            // Fall back to full-screen OCR if we can't get the window.
            ocrText = recognizeText(in: fullScreen)
            print("OCR: full screen (no frontmost window found)")
        }

        let txtPath = directory.appendingPathComponent("screenshot_\(timestamp).txt")
        try ocrText.write(to: txtPath, atomically: true, encoding: .utf8)

        // Downscale full-screen image for visual context.
        let width = CGFloat(fullScreen.width)
        let height = CGFloat(fullScreen.height)
        let scale = min(maxDimension / width, maxDimension / height, 1.0)
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        guard let colorSpace = fullScreen.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
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
        ctx.draw(fullScreen, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedImage = ctx.makeImage() else {
            throw CaptureError.screencaptureFailed
        }

        let bitmapRep = NSBitmapImageRep(cgImage: resizedImage)
        let imagePath = directory.appendingPathComponent("screenshot_\(timestamp).jpg")
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) else {
            throw CaptureError.screencaptureFailed
        }
        try jpegData.write(to: imagePath)

        return imagePath
    }

    /// Run OCR on an image and return all recognized text.
    /// Uses "accurate" recognition with language correction disabled
    /// so it doesn't mangle variable names and code syntax.
    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])

        guard let observations = request.results else { return "" }

        // Sort top-to-bottom, then left-to-right to preserve reading order.
        let sorted = observations.sorted { a, b in
            if abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.01 {
                return a.boundingBox.origin.y > b.boundingBox.origin.y
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
