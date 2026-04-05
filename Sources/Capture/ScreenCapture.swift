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

    /// Run OCR on an image and return all recognized text.
    /// Groups text fragments on the same line, preserving code layout.
    static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else { return "" }

        // Each observation has a bounding box in normalized coordinates (0-1).
        // Group fragments whose vertical centers are close enough to be on the same line.
        // Use the average height of observations as the threshold.
        let avgHeight = observations.map { $0.boundingBox.height }.reduce(0, +) / Float(observations.count)
        let lineThreshold = avgHeight * 0.5

        struct Fragment {
            let text: String
            let x: CGFloat
            let y: CGFloat  // vertical center
        }

        let fragments = observations.compactMap { obs -> Fragment? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let box = obs.boundingBox
            return Fragment(
                text: text,
                x: CGFloat(box.origin.x),
                y: CGFloat(box.origin.y + box.height / 2)
            )
        }

        // Sort by Y descending (top of screen first), then group into lines.
        let sortedByY = fragments.sorted { $0.y > $1.y }
        var lines: [[Fragment]] = []
        for frag in sortedByY {
            if let lastIdx = lines.lastIndex(where: {
                abs($0[0].y - frag.y) < CGFloat(lineThreshold)
            }) {
                lines[lastIdx].append(frag)
            } else {
                lines.append([frag])
            }
        }

        // Within each line, sort left-to-right and join with spaces.
        return lines.map { line in
            line.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
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
