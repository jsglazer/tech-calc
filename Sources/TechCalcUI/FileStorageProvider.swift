import Foundation
import TechCalcCore

/// The file-backed `StorageProvider`.
///
/// It lives here, not in TechCalcCore, because the core does no file I/O: this is the shell side
/// of the injection seam. Writes are atomic so a crash mid-save cannot truncate `state.json`.
public final class FileStorageProvider: StorageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/TechCalc/state.json`.
    public static func applicationSupport(bundleFolder: String = "TechCalc") throws -> FileStorageProvider {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent(bundleFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return FileStorageProvider(url: folder.appendingPathComponent("state.json"))
    }

    public func loadDocumentData() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func saveDocumentData(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try data.write(to: url, options: .atomic)
    }
}
