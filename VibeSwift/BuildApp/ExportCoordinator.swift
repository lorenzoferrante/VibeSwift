import Foundation

final class ExportCoordinator {
    private var retainedURLs: [URL] = []

    @discardableResult
    func register(packageURL: URL) -> URL {
        retainedURLs.append(packageURL)
        return packageURL
    }

    func cleanupRetainedPackages() {
        let fm = FileManager.default
        for url in retainedURLs {
            try? fm.removeItem(at: url)
        }
        retainedURLs.removeAll()
    }
}
