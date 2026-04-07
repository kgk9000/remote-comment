import Foundation

@main
struct CaptureMain {
    static func main() async {
        let args = CommandLine.arguments
        let host = flag(args, name: "--host") ?? "kgk-mini"
        let interval = Int(flag(args, name: "--interval") ?? "60") ?? 60
        let remoteDir = flag(args, name: "--remote-dir") ?? "~/snapshots"
        let localDir = FileManager.default.temporaryDirectory.appendingPathComponent("remote-comment-captures")

        print("Capture starting")
        print("  host: \(host)")
        print("  interval: \(interval)s")
        print("  remote dir: \(remoteDir)")

        do {
            try ensureRemoteDir(host: host, dir: remoteDir)
            print("Remote directory ready")
        } catch {
            print("Warning: could not create remote dir: \(error.localizedDescription)")
        }

        while true {
            if ScreenCapture.isScreenLocked() {
                print("Screen locked, skipping")
            } else {
                do {
                    let screenshot = try ScreenCapture.takeScreenshot(to: localDir)
                    try rsync(files: [screenshot], host: host, remoteDir: remoteDir)
                    print("Sent \(screenshot.lastPathComponent) → \(host)")
                    try? FileManager.default.removeItem(at: screenshot)
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            }
            try? await Task.sleep(for: .seconds(interval))
        }
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
