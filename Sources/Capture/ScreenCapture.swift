import AppKit
import Foundation
import Vision

enum ScreenCapture {
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

    /// Find the frontmost app's main window. Returns its ID and bounds.
    static func frontmostWindow() -> (id: CGWindowID, bounds: CGRect)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat,
                  w > 100 && h > 100
            else { continue }
            return (id: windowID, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
        return nil
    }

    /// Capture the frontmost window as a PNG. Falls back to full screen.
    static func takeScreenshot(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970)

        let capturedImage: CGImage

        if let window = frontmostWindow(),
           let windowImage = CGWindowListCreateImage(
               window.bounds,
               .optionIncludingWindow,
               window.id,
               [.bestResolution]
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

        // Try PNG first (lossless, best for code). Fall back to JPEG if over 5MB.
        let bitmapRep = NSBitmapImageRep(cgImage: capturedImage)
        let pngData = bitmapRep.representation(using: .png, properties: [:])

        if let pngData, pngData.count <= maxImageBytes {
            let path = directory.appendingPathComponent("screenshot_\(timestamp).png")
            try pngData.write(to: path)
            print("Saved PNG (\(pngData.count / 1024)KB)")
            return path
        }

        // PNG too big — use JPEG.
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw CaptureError.screencaptureFailed
        }
        let path = directory.appendingPathComponent("screenshot_\(timestamp).jpg")
        try jpegData.write(to: path)
        print("Saved JPEG (\(jpegData.count / 1024)KB)")
        return path
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
