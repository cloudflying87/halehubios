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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { dec in
            let str = try dec.singleValueContainer().decode(String.self)
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
