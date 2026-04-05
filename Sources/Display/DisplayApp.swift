import SwiftUI

@main
struct DisplayApp: App {
    @State private var comment: Comment?
    @State private var status = "Starting..."
    @State private var watcher: Watcher?

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
