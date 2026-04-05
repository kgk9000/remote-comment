import AppKit
import SwiftUI

@main
struct DisplayApp: App {
    @State private var comment: Comment?
    @State private var status = "Starting..."
    @State private var watcher: Watcher?

    init() {
        Self.loadDotEnv()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Load KEY=VALUE lines from ~/.env if it exists
    private static func loadDotEnv() {
        let path = NSString("~/.env").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            // Don't override existing env vars
            if ProcessInfo.processInfo.environment[key] == nil {
                setenv(key, value, 0)
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
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] == nil {
            status = "⚠️ ANTHROPIC_API_KEY not set"
            print("Error: ANTHROPIC_API_KEY environment variable is not set")
            return
        }

        let args = CommandLine.arguments
        let dir = flag(args, name: "--dir")
            ?? ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
            ?? NSString("~/screenshots").expandingTildeInPath

        let dirURL = URL(fileURLWithPath: dir)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let w = Watcher(directory: dirURL)
        self.watcher = w
        status = "Watching \(dir)"
        w.start()

        // Observe new images from the watcher
        Task {
            var lastProcessed: URL?
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard let imageURL = w.latestImage, imageURL != lastProcessed else { continue }
                lastProcessed = imageURL
                status = "Asking Claude..."
                do {
                    let c = try await Commenter.comment(on: imageURL)
                    await MainActor.run {
                        self.comment = c
                        self.status = "Watching \(dir)"
                    }
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
