import Foundation

// MARK: - DiskScanner

@MainActor
final class DiskScanner: ObservableObject {

    @Published var rootNode: FileNode?
    @Published var isScanning = false
    @Published var statusMessage = "Choose a folder to scan"
    @Published var scanProgress: Int = 0
    @Published var error: String?

    /// Set when a cached result is found during prepareToScan.
    /// The UI shows a banner with "Use Cached / Rescan" while this is non-nil.
    @Published var cachedInfo: CacheInfo?

    /// The URL most recently requested (used for Rescan button).
    private(set) var pendingURL: URL?

    // MARK: - Public API

    /// Checks the cache for `url` first.
    /// - If a cache exists: loads it immediately (shows treemap right away) and sets `cachedInfo`.
    /// - If no cache: starts a fresh scan.
    func prepareToScan(url: URL) {
        guard !isScanning else { return }
        pendingURL = url
        rootNode = nil
        cachedInfo = nil
        error = nil
        scanProgress = 0
        statusMessage = "Checking cache…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let cached = await ScanCache.shared.load(for: url)

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let (node, date) = cached {
                    // Show cached data immediately; let user decide whether to rescan
                    self.rootNode = node
                    self.cachedInfo = CacheInfo(node: node, date: date, url: url)
                    self.statusMessage = "Cached • \(node.formattedSize)"
                } else {
                    // No cache — scan fresh
                    self.startScan(url: url)
                }
            }
        }
    }

    /// Discards the current cached view and runs a fresh scan of `pendingURL`.
    func rescan() {
        guard let url = pendingURL, !isScanning else { return }
        cachedInfo = nil
        rootNode = nil
        startScan(url: url)
    }

    func cancel() {
        isScanning = false
        statusMessage = "Cancelled"
    }

    // MARK: - Internal scan

    private func startScan(url: URL) {
        isScanning = true
        scanProgress = 0
        statusMessage = "Scanning…"

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                var count = 0
                let node = try Self.buildTree(url: url, progress: { c in
                    count = c
                    if c % 200 == 0 {
                        let msg = "Scanned \(c.formatted()) items…"
                        Task { @MainActor [weak self] in
                            self?.scanProgress = c
                            self?.statusMessage = msg
                        }
                    }
                })

                // Persist to cache in the background (non-blocking)
                Task.detached(priority: .background) {
                    await ScanCache.shared.save(node, for: url)
                }

                Task { @MainActor [weak self] in
                    self?.rootNode = node
                    self?.cachedInfo = nil         // fresh data — no banner needed
                    self?.isScanning = false
                    self?.statusMessage = "\(count.formatted()) items • \(node.formattedSize)"
                    self?.scanProgress = count
                }
            } catch {
                let msg = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.error = msg
                    self?.isScanning = false
                    self?.statusMessage = "Error: \(msg)"
                }
            }
        }
    }

    // MARK: - Tree builder (off-main-thread)

    private nonisolated static func buildTree(url: URL, progress: (Int) -> Void) throws -> FileNode {
        var visited = 0
        return try buildNode(url: url, visited: &visited, progress: progress)
    }

    private nonisolated static func buildNode(url: URL, visited: inout Int, progress: (Int) -> Void) throws -> FileNode {
        try Task.checkCancellation()

        let fm = FileManager.default

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        // Skip symlinks to avoid cycles / double-counting
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        if attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
            let size = attrs?[.size] as? Int64 ?? 0
            visited += 1
            progress(visited)
            return FileNode(url: url, name: url.lastPathComponent, isDirectory: false, allocatedSize: size)
        }

        if isDir.boolValue {
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey],
                options: [.skipsPackageDescendants]
            )) ?? []

            var children: [FileNode] = []
            for childURL in contents {
                if Task.isCancelled { break }
                let child = try buildNode(url: childURL, visited: &visited, progress: progress)
                children.append(child)
            }

            let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: true, allocatedSize: 0, children: children)
            for c in children { c.parent = node }

            visited += 1
            progress(visited)
            return node
        } else {
            let resourceValues = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            let size = Int64(
                resourceValues?.totalFileAllocatedSize ??
                resourceValues?.fileAllocatedSize ??
                resourceValues?.fileSize ?? 0
            )

            visited += 1
            progress(visited)
            return FileNode(url: url, name: url.lastPathComponent, isDirectory: false, allocatedSize: size)
        }
    }
}
