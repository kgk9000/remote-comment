import Foundation

/// Watches a directory for new .jpg files arriving.
@Observable
final class Watcher {
    var latestImage: URL?

    private let directory: URL
    private var seen: Set<String> = []

    init(directory: URL) {
        self.directory = directory
    }

    func start() {
        // Seed with existing files so we don't process old ones
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let jpgs = files.filter { $0.pathExtension == "jpg" }
            for f in jpgs {
                seen.insert(f.lastPathComponent)
            }
            print("Watcher: seeded \(jpgs.count) existing files")
        }

        print("Watcher: polling \(directory.path) every 2s")

        // Use async loop instead of Timer (more reliable without a RunLoop)
        Task {
            while true {
                try? await Task.sleep(for: .seconds(2))
                check()
            }
        }
    }

    private func check() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }

        let jpgs = files
            .filter { $0.pathExtension == "jpg" && !seen.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } // timestamp in name = chronological

        if let newest = jpgs.last {
            print("Watcher: new image! \(newest.lastPathComponent) (+\(jpgs.count - 1) others)")
            for f in jpgs { seen.insert(f.lastPathComponent) }
            self.latestImage = newest
        }
    }
}
