import AppKit
import SwiftUI

@main
struct DisplayApp: App {
    @State private var comment: Comment?
    @State private var status = "Starting..."

    init() {
        Self.loadDotEnv()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Load KEY=VALUE lines from all *.env files in ~/.env/
    private static func loadDotEnv() {
        let envDir = URL(fileURLWithPath: NSString("~/.env").expandingTildeInPath)
        guard let files = try? FileManager.default.contentsOfDirectory(at: envDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "env" {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if ProcessInfo.processInfo.environment[key] == nil {
                    setenv(key, value, 0)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            CommentView(comment: comment, status: status)
                .onAppear { startWatching() }
        }
        .windowResizability(.contentSize)
    }

    private func startWatching() {
        if getenv("ANTHROPIC_API_KEY") == nil {
            status = "⚠️ ANTHROPIC_API_KEY not set"
            print("Error: ANTHROPIC_API_KEY environment variable is not set")
            return
        }

        let args = CommandLine.arguments
        let dir = flag(args, name: "--dir")
            ?? ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? NSString("~/screenshots").expandingTildeInPath

        let dirURL = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        status = "Watching \(dir)"
        print("Watching \(dir)")

        // Single loop: poll for new files and send to Claude
        Task {
            // Seed existing files
            var seen = Set<String>()
            if let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
                for f in files where f.pathExtension == "jpg" {
                    seen.insert(f.lastPathComponent)
                }
            }
            print("Seeded \(seen.count) existing files")

            while true {
                try? await Task.sleep(for: .seconds(2))

                guard let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                else { continue }

                let newFiles = files
                    .filter { $0.pathExtension == "jpg" && !seen.contains($0.lastPathComponent) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }

                guard let newest = newFiles.last else { continue }

                print("New image: \(newest.lastPathComponent) (+\(newFiles.count - 1) others)")
                for f in newFiles { seen.insert(f.lastPathComponent) }

                await MainActor.run { self.status = "Asking Claude..." }

                do {
                    let c = try await Commenter.comment(on: newest)
                    await MainActor.run {
                        self.comment = c
                        self.status = "Watching \(dir)"
                    }
                    print("Comment received")
                } catch {
                    await MainActor.run {
                        self.status = "Error: \(error.localizedDescription)"
                    }
                    print("Comment error: \(error)")
                }
            }
        }
    }

    private func flag(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
