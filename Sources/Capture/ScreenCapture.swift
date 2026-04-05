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

        // Capture the frontmost window for both the image and OCR.
        // Falls back to full screen if no frontmost window is found.
        let capturedImage: CGImage
        if let windowID = frontmostWindowID(),
           let windowImage = CGWindowListCreateImage(
               CGRect.null,
               .optionIncludingWindow,
               windowID,
               [.bestResolution, .boundsIgnoreFraming]
           ) {
            capturedImage = windowImage
            print("Captured frontmost window (\(windowImage.width)x\(windowImage.height))")
        } else if let fullScreen = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) {
            capturedImage = fullScreen
            print("Captured full screen (no frontmost window found)")
        } else {
            throw CaptureError.screencaptureFailed
        }

        // Save as high-quality PNG — lossless so Claude can read code text.
        let bitmapRep = NSBitmapImageRep(cgImage: capturedImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw CaptureError.screencaptureFailed
        }

        let imagePath = directory.appendingPathComponent("screenshot_\(timestamp).png")
        try pngData.write(to: imagePath)

        return imagePath
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
