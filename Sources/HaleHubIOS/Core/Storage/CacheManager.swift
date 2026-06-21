import CryptoKit
import Foundation

/// File-based JSON cache. Each key maps to a JSON file in the app's Documents/HaleHubCache directory.
actor CacheManager {
    static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var cacheDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("HaleHubCache", isDirectory: true)
    }

    init() {
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { dec in
            let str = try dec.singleValueContainer().decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmt.date(from: str) { return d }
            let fb = ISO8601DateFormatter(); fb.formatOptions = [.withFullDate]
            if let d = fb.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                                                   debugDescription: "Cannot parse date: \(str)")
        }
    }

    func save<T: Encodable>(_ value: T, key: String) {
        ensureCacheDirExists()
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(key))
    }

    func load<T: Decodable>(key: String) -> T? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func cacheDate(key: String) -> Date? {
        let url = fileURL(key)
        return (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func clear(key: String) {
        try? fileManager.removeItem(at: fileURL(key))
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
    }

    private func fileURL(_ key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }

    private func ensureCacheDirExists() {
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
}

/// On-disk cache for downloaded images (e.g. letter photos) so they render
/// offline. Files live in Documents/HaleHubImages, named by a stable hash of
/// the source URL.
actor OfflineImageStore {
    static let shared = OfflineImageStore()

    private let fileManager = FileManager.default

    private var dir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("HaleHubImages", isDirectory: true)
    }

    private func fileURL(for remoteURL: String) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name)
    }

    /// Whether the image for this URL has already been saved to disk.
    func isCached(_ remoteURL: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: remoteURL).path)
    }

    /// Previously-downloaded bytes for an image, or nil if not cached.
    func data(for remoteURL: String) -> Data? {
        try? Data(contentsOf: fileURL(for: remoteURL))
    }

    /// Persist freshly-fetched bytes (used when a view downloads on first view).
    func store(_ data: Data, for remoteURL: String) {
        ensureDirExists()
        try? data.write(to: fileURL(for: remoteURL))
    }

    /// Fetch and persist an image unless it is already on disk. Returns whether
    /// the image is available on disk afterwards.
    @discardableResult
    func download(_ remoteURL: String) async -> Bool {
        if isCached(remoteURL) { return true }
        guard let url = URL(string: remoteURL) else { return false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            store(data, for: remoteURL)
            return true
        } catch {
            return false
        }
    }

    func clearAll() {
        try? fileManager.removeItem(at: dir)
    }

    private func ensureDirExists() {
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
