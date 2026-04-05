import Foundation
import Vision

@main
struct CaptureMain {
    static func main() async {
        let args = CommandLine.arguments
        let host = flag(args, name: "--host") ?? "kgk-mini"
        let interval = Int(flag(args, name: "--interval") ?? "120") ?? 120
        let remoteDir = flag(args, name: "--remote-dir") ?? "~/screenshots"
        let localDir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-comment-captures")

        print("Capture starting")
        print("  host: \(host)")
        print("  interval: \(interval)s")
        print("  remote dir: \(remoteDir)")

        var lastFeaturePrint: VNFeaturePrintObservation?

        while true {
            if ScreenCapture.isScreenLocked() {
                print("Screen locked, skipping")
                try? await Task.sleep(for: .seconds(interval))
                continue
            }

            do {
                let screenshot = try ScreenCapture.takeScreenshot(to: localDir)
                print("Screenshot: \(screenshot.lastPathComponent)")

                // Skip if screen hasn't changed
                if let current = ScreenCapture.featurePrint(for: screenshot),
                   let previous = lastFeaturePrint,
                   ScreenCapture.isSimilar(current, previous) {
                    print("Screen unchanged, skipping")
                    try? FileManager.default.removeItem(at: screenshot)
                    try? await Task.sleep(for: .seconds(interval))
                    continue
                }

                if let fp = ScreenCapture.featurePrint(for: screenshot) {
                    lastFeaturePrint = fp
                }

                // rsync to the Mac Mini
                try rsync(file: screenshot, host: host, remoteDir: remoteDir)
                print("Sent to \(host):\(remoteDir)/")

                // Clean up local file
                try? FileManager.default.removeItem(at: screenshot)
            } catch {
                print("Error: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .seconds(interval))
        }
    }

    static func rsync(file: URL, host: String, remoteDir: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-az", file.path, "\(host):\(remoteDir)/"]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CaptureError.rsyncFailed(stderr)
        }
    }

    static func flag(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
