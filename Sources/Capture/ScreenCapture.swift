import AppKit
import Foundation
import Vision

enum ScreenCapture {
    static let similarityThreshold: Float = 0.05

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return true
        }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Int, locked == 1 { return true }
        return false
    }

    /// Find the frontmost app's main window ID.
    static func frontmostWindowID() -> CGWindowID? {
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
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  w > 100 && h > 100
            else { continue }
            return windowID
        }
        return nil
    }

    /// Capture a screenshot using the `screencapture` CLI tool.
    /// Uses `-l <windowID>` to capture just the frontmost window.
    /// Falls back to full screen if no frontmost window is found.
    static func takeScreenshot(to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = fmt.string(from: Date())
        let path = directory.appendingPathComponent("\(timestamp).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

        guard let windowID = frontmostWindowID() else {
            throw CaptureError.noWindow
        }

        // Capture just the frontmost window: -l windowID, -o no shadow, -x no sound
        process.arguments = ["-l", "\(windowID)", "-o", "-x", path.path]
        print("Capturing window \(windowID)")

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: path.path) else {
            throw CaptureError.screencaptureFailed
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int) ?? 0
        print("Saved \(path.lastPathComponent) (\(fileSize / 1024)KB)")
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
    case noWindow
    case rsyncFailed(String)

    var errorDescription: String? {
        switch self {
        case .screencaptureFailed:
            return "Screenshot failed. Grant Screen Recording permission in System Settings."
        case .noWindow:
            return "No window to capture"
        case .rsyncFailed(let msg):
            return "rsync failed: \(msg)"
        }
    }
}
