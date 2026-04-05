import AppKit
import SwiftUI

@main
struct DisplayApp: App {
    @State private var comment: Comment?
    @State private var status = "Starting..."

    init() {
        Self.loadDotEnv()
        // Required to show a window when launched as a bare CLI executable.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            CommentView(comment: comment, status: status)
                .onAppear { startPolling() }
        }
        .windowResizability(.contentSize)
    }

    // MARK: - Screenshot polling

    /// Main loop: find new screenshots, send each to Claude, display the result.
    private func startPolling() {
        guard getenv("ANTHROPIC_API_KEY") != nil else {
            status = "⚠️ ANTHROPIC_API_KEY not set"
            print("Error: ANTHROPIC_API_KEY environment variable is not set")
            return
        }

        let dir = resolveScreenshotDir()
        let dirURL = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        status = "Watching \(dir)"
        print("Watching \(dir)")

        Task {
            var seen = Set<String>()

            // On startup, process the most recent existing screenshot immediately.
            let existing = listScreenshots(in: dirURL)
            for f in existing { seen.insert(f.lastPathComponent) }
            print("Found \(existing.count) existing files")

            if let latest = existing.last {
                await processScreenshot(latest, dir: dir)
            }

            // Poll for new arrivals.
            while true {
                try? await Task.sleep(for: .seconds(2))

                let all = listScreenshots(in: dirURL)
                let unseen = all.filter { !seen.contains($0.lastPathComponent) }
                guard let newest = unseen.last else { continue }

                // Mark all unseen as processed so we skip straight to the latest.
                for f in unseen { seen.insert(f.lastPathComponent) }
                print("New image: \(newest.lastPathComponent) (+\(unseen.count - 1) skipped)")

                await processScreenshot(newest, dir: dir)
            }
        }
    }

    /// Send a screenshot to Claude and update the UI with the comment.
    private func processScreenshot(_ imageURL: URL, dir: String) async {
        await MainActor.run { self.status = "Asking Claude..." }
        do {
            let c = try await Commenter.comment(on: imageURL)
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

    // MARK: - Helpers

    /// List completed screenshots by looking for .ready marker files.
    /// The .ready file is sent in a separate rsync after the image and OCR text,
    /// so its presence guarantees both files have fully arrived.
    /// Returns the corresponding image URLs (.ready → .jpg).
    private func listScreenshots(in dir: URL) -> [URL] {
        let readyFiles = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "ready" && $0.lastPathComponent.hasPrefix("screenshot_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            ?? []
        return readyFiles.map { $0.deletingPathExtension().appendingPathExtension("jpg") }
    }

    /// Resolve the screenshot directory from CLI args, env, or default.
    private func resolveScreenshotDir() -> String {
        let args = CommandLine.arguments
        return flag(args, name: "--dir")
            ?? ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? NSString("~/screenshots").expandingTildeInPath
    }

    private func flag(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    // MARK: - Environment loading

    /// Load KEY=VALUE lines from all *.env files in ~/.env/.
    /// Won't override variables already set in the environment.
    private static func loadDotEnv() {
        let envDir = URL(fileURLWithPath: NSString("~/.env").expandingTildeInPath)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: envDir, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "env" {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)

                // Strip surrounding quotes ("val" or 'val' → val)
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
}
