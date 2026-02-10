import Foundation

struct BundlePackager {
    func package(projectDirectory: URL, packageName: String) throws -> URL {
        let fm = FileManager.default
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = fm.temporaryDirectory
            .appendingPathComponent("\(packageName)-\(timestamp).vibeapp")

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        // On iOS, FileManager.zipItem is not universally available, so we export a packaged directory.
        // The .vibeapp extension still lets users share/import it as a single bundle unit.
        try fm.copyItem(at: projectDirectory, to: destination)
        return destination
    }
}
