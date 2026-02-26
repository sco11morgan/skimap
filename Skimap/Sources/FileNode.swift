import Foundation
import SwiftUI

// MARK: - FileNode

final class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var allocatedSize: Int64
    var children: [FileNode]

    weak var parent: FileNode?

    // -1 = not yet computed. Memoized on first access so the layout
    // algorithm doesn't re-walk the subtree on every call.
    private var _cachedTotalSize: Int64 = -1

    init(url: URL, name: String, isDirectory: Bool, allocatedSize: Int64 = 0, children: [FileNode] = []) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.allocatedSize = allocatedSize
        self.children = children
    }

    // Recursive total size — computed once, then cached.
    var totalSize: Int64 {
        if _cachedTotalSize >= 0 { return _cachedTotalSize }
        let v = children.isEmpty
            ? allocatedSize
            : children.reduce(Int64(0)) { $0 + $1.totalSize }
        _cachedTotalSize = v
        return v
    }

    // Sorted children by size descending
    var sortedChildren: [FileNode] {
        children.sorted { $0.totalSize > $1.totalSize }
    }

    // File extension for coloring
    var fileExtension: String {
        guard !isDirectory else { return "" }
        return url.pathExtension.lowercased()
    }

    // Human-readable size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    // Color based on file type / extension
    var color: Color {
        if isDirectory {
            return .blue.opacity(0.6)
        }
        return FileNode.colorForExtension(fileExtension)
    }

    static func colorForExtension(_ ext: String) -> Color {
        switch ext {
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm":
            return Color(red: 0.85, green: 0.33, blue: 0.33) // red — video
        case "mp3", "aac", "flac", "wav", "m4a", "ogg", "wma":
            return Color(red: 0.93, green: 0.58, blue: 0.22) // orange — audio
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff", "svg":
            return Color(red: 0.95, green: 0.77, blue: 0.20) // yellow — images
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "pkg":
            return Color(red: 0.60, green: 0.40, blue: 0.80) // purple — archives
        case "pdf":
            return Color(red: 0.90, green: 0.45, blue: 0.35) // salmon — documents
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key":
            return Color(red: 0.30, green: 0.65, blue: 0.90) // light blue — office docs
        case "swift", "py", "js", "ts", "go", "rs", "cpp", "c", "h", "java", "kt", "rb":
            return Color(red: 0.25, green: 0.75, blue: 0.55) // teal — source code
        case "app", "framework", "dylib", "o", "a":
            return Color(red: 0.50, green: 0.50, blue: 0.90) // indigo — binaries
        case "sqlite", "db", "sql":
            return Color(red: 0.70, green: 0.55, blue: 0.35) // brown — databases
        default:
            return Color(red: 0.55, green: 0.65, blue: 0.55) // gray-green — other
        }
    }
}

// MARK: - Path ancestry

extension FileNode {
    /// Returns the chain from root down to this node
    func pathComponents() -> [FileNode] {
        var chain: [FileNode] = [self]
        var current = self
        while let p = current.parent {
            chain.insert(p, at: 0)
            current = p
        }
        return chain
    }
}

// MARK: - Codable (for disk cache — parent link excluded to avoid cycles)

extension FileNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case url, name, isDirectory, allocatedSize, children
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            url: try c.decode(URL.self, forKey: .url),
            name: try c.decode(String.self, forKey: .name),
            isDirectory: try c.decode(Bool.self, forKey: .isDirectory),
            allocatedSize: try c.decode(Int64.self, forKey: .allocatedSize),
            children: try c.decode([FileNode].self, forKey: .children)
        )
        // Re-stitch parent pointers after decode
        for child in children { child.parent = self }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encode(name, forKey: .name)
        try c.encode(isDirectory, forKey: .isDirectory)
        try c.encode(allocatedSize, forKey: .allocatedSize)
        try c.encode(children, forKey: .children)
    }
}
