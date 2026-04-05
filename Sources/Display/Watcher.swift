import Foundation

/// Watches a directory for new .jpg files arriving.
@Observable
final class Watcher {
    var latestImage: URL?

    private let directory: URL
    private var seen: Set<String> = []
    private var timer: Timer?

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

        // Poll every 2 seconds for new files
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
        else { return }

        let jpgs = files
            .filter { $0.pathExtension == "jpg" && !seen.contains($0.lastPathComponent) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }

        if let newest = jpgs.last {
            print("Watcher: new image! \(newest.lastPathComponent) (+\(jpgs.count - 1) others)")
            for f in jpgs { seen.insert(f.lastPathComponent) }
            DispatchQueue.main.async {
                self.latestImage = newest
            }
        }
    }
}
