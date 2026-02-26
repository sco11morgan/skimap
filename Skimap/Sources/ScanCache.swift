import Foundation

// MARK: - CacheEntry

private struct CacheEntry: Codable {
    let scannedPath: String
    let scanDate: Date
    let root: FileNode
}

// MARK: - ScanCache

/// Thread-safe disk cache for scan results, stored as JSON under
/// ~/Library/Caches/com.skimap.app/<hash>.skimap.json
actor ScanCache {

    static let shared = ScanCache()

    private let cacheDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("com.skimap.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Public API

    /// Returns the cached tree and the date it was saved, or nil if no cache exists.
    func load(for url: URL) -> (node: FileNode, date: Date)? {
        let file = cacheFile(for: url)
        guard
            let data = try? Data(contentsOf: file),
            let entry = try? decoder.decode(CacheEntry.self, from: data)
        else { return nil }
        return (entry.root, entry.scanDate)
    }

    /// Saves a scan result to disk. Call from a background context.
    func save(_ node: FileNode, for url: URL) {
        let entry = CacheEntry(scannedPath: url.path, scanDate: Date(), root: node)
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: cacheFile(for: url), options: .atomic)
    }

    /// Removes the cached entry for a given URL (e.g. after a rescan).
    func invalidate(for url: URL) {
        try? FileManager.default.removeItem(at: cacheFile(for: url))
    }

    /// Size of the cache file on disk, or nil if none.
    func cacheSize(for url: URL) -> Int64? {
        let file = cacheFile(for: url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        return attrs?[.size] as? Int64
    }

    // MARK: Private

    private func cacheFile(for url: URL) -> URL {
        // Simple FNV-1a-style hash of the path string → 16 hex chars
        let key = stableKey(url.path)
        return cacheDir.appendingPathComponent("\(key).skimap.json")
    }

    private func stableKey(_ path: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in Data(path.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - CacheInfo (passed to the UI layer)

struct CacheInfo {
    let node: FileNode
    let date: Date
    let url: URL

    /// Human-readable age string, e.g. "3 min ago", "2 hours ago"
    var ageDescription: String {
        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<60:       return "just now"
        case 60..<3_600:  return "\(seconds / 60) min ago"
        case 3_600..<86_400: return "\(seconds / 3_600) hr ago"
        default:          return "\(seconds / 86_400) days ago"
        }
    }
}
