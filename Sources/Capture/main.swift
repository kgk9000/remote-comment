import Foundation
import Vision

@main
struct CaptureMain {
    static func main() async {
        let args = CommandLine.arguments
        let host = flag(args, name: "--host") ?? "kgk-mini"
        let interval = Int(flag(args, name: "--interval") ?? "60") ?? 60
        let remoteDir = flag(args, name: "--remote-dir") ?? "~/screenshots"
        let localDir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-comment-captures")

        print("Capture starting")
        print("  host: \(host)")
        print("  interval: \(interval)s")
        print("  remote dir: \(remoteDir)")

        // Ensure remote directory exists
        do {
            try ensureRemoteDir(host: host, dir: remoteDir)
            print("Remote directory ready")
        } catch {
            print("Warning: could not create remote dir: \(error.localizedDescription)")
        }

        let maxDuration = Int(flag(args, name: "--max-duration") ?? "3600") ?? 3600
        let startTime = Date()
        print("  max duration: \(maxDuration)s")

        var lastFeaturePrint: VNFeaturePrintObservation?

        while Date().timeIntervalSince(startTime) < Double(maxDuration) {
            if ScreenCapture.isScreenLocked() {
                print("Screen locked, skipping")
                try? await Task.sleep(for: .seconds(interval))
                continue
            }

            do {
                let screenshot = try ScreenCapture.takeScreenshot(to: localDir)
                print("Screenshot: \(screenshot.lastPathComponent)")

                // TODO: re-enable similarity check once end-to-end flow is working
                // if let current = ScreenCapture.featurePrint(for: screenshot),
                //    let previous = lastFeaturePrint,
                //    ScreenCapture.isSimilar(current, previous) {
                //     print("Screen unchanged, skipping")
                //     try? FileManager.default.removeItem(at: screenshot)
                //     try? await Task.sleep(for: .seconds(interval))
                //     continue
                // }
                //
                // if let fp = ScreenCapture.featurePrint(for: screenshot) {
                //     lastFeaturePrint = fp
                // }

                // rsync the image and OCR text, then send a .ready marker
                // so Display knows both files have fully arrived.
                let txtFile = screenshot.deletingPathExtension().appendingPathExtension("txt")
                try rsync(files: [screenshot, txtFile], host: host, remoteDir: remoteDir)

                let readyFile = screenshot.deletingPathExtension().appendingPathExtension("ready")
                try "".write(to: readyFile, atomically: true, encoding: .utf8)
                try rsync(files: [readyFile], host: host, remoteDir: remoteDir)
                print("Sent to \(host):\(remoteDir)/")

                // Clean up local files
                try? FileManager.default.removeItem(at: screenshot)
                try? FileManager.default.removeItem(at: txtFile)
                try? FileManager.default.removeItem(at: readyFile)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .seconds(interval))
        }

        print("Max duration reached (\(maxDuration)s), exiting")
    }

    static func rsync(files: [URL], host: String, remoteDir: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-az"] + files.map(\.path) + ["\(host):\(remoteDir)/"]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CaptureError.rsyncFailed(stderr)
        }
    }

    static func ensureRemoteDir(host: String, dir: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, "mkdir", "-p", dir]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CaptureError.rsyncFailed("ssh mkdir failed")
        }
    }

    static func flag(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
