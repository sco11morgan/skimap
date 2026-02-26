import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()

    // Navigation stack — the current "root" displayed in the treemap
    @State private var navigationStack: [FileNode] = []
    @State private var selectedNode: FileNode?
    @State private var hoveredNode: FileNode?

    // Tooltip position
    @State private var mouseLocation: CGPoint = .zero

    private var displayRoot: FileNode? {
        navigationStack.last ?? scanner.rootNode
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let info = scanner.cachedInfo {
                cacheBanner(info: info)
                Divider()
            }
            mainContent
        }
        .frame(minWidth: 800, minHeight: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(tooltipOverlay, alignment: .topLeading)
        .onAppear {
            // Start tracking mouse globally for tooltip placement
        }
    }

    // MARK: - Cache banner

    private func cacheBanner(info: CacheInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.secondary)

            Text("Showing cached scan from **\(info.ageDescription)**")
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                scanner.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(scanner.isScanning)

            Button {
                scanner.cachedInfo = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Open button
            Button {
                chooseFolder()
            } label: {
                Label("Open…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanner.isScanning)

            // Home directories shortcuts
            Menu {
                Button("Home (~)") { scanURL(URL(fileURLWithPath: NSHomeDirectory())) }
                Button("Downloads") { scanURL(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")) }
                Button("Documents") { scanURL(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")) }
                Button("Desktop") { scanURL(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")) }
                Divider()
                Button("Applications") { scanURL(URL(fileURLWithPath: "/Applications")) }
                Button("System Library") { scanURL(URL(fileURLWithPath: "/Library")) }
            } label: {
                Label("Quick Open", systemImage: "bolt.fill")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 120)
            .disabled(scanner.isScanning)

            Divider().frame(height: 20)

            // Breadcrumb navigation
            breadcrumb

            Spacer()

            // Status
            statusArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 2) {
            if let root = scanner.rootNode {
                breadcrumbButton(node: root, isFirst: true)

                ForEach(navigationStack, id: \.id) { node in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    breadcrumbButton(node: node, isFirst: false)
                }
            }
        }
    }

    private func breadcrumbButton(node: FileNode, isFirst: Bool) -> some View {
        let isCurrent = navigationStack.last?.id == node.id || (navigationStack.isEmpty && isFirst)

        return Button {
            if isFirst {
                navigationStack.removeAll()
            } else {
                // Pop back to this node
                if let idx = navigationStack.firstIndex(where: { $0.id == node.id }) {
                    navigationStack = Array(navigationStack.prefix(through: idx))
                }
            }
            selectedNode = nil
        } label: {
            Text(node.name)
                .font(.subheadline)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundColor(isCurrent ? .primary : .accentColor)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status area

    private var statusArea: some View {
        HStack(spacing: 8) {
            if scanner.isScanning {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)

                Button("Stop") { scanner.cancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(scanner.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 280, alignment: .trailing)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if scanner.isScanning && scanner.rootNode == nil {
            // Scanning placeholder
            VStack(spacing: 16) {
                ProgressView()
                Text(scanner.statusMessage)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let root = displayRoot {
            HSplitView {
                // Treemap
                treemapPanel(root: root)
                    .frame(minWidth: 500)

                // Detail panel
                detailPanel
                    .frame(width: 220)
            }
        } else {
            emptyState
        }
    }

    private func treemapPanel(root: FileNode) -> some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)

            TreeMapView(node: root, selectedNode: $selectedNode, hoveredNode: $hoveredNode)
                .padding(4)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc): mouseLocation = loc
                    case .ended: hoveredNode = nil
                    }
                }
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                // Double-tap to drill down into selected directory
                if let sel = selectedNode, sel.isDirectory {
                    drillDown(sel)
                }
            }
        )
    }

    // MARK: - Detail panel

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Details")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Divider()

            ScrollView {
                if let node = selectedNode ?? hoveredNode {
                    nodeDetail(node)
                } else if let root = displayRoot {
                    nodeDetail(root)
                } else {
                    Text("Select an item")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }

            Divider()

            // Drill-down / up buttons
            HStack {
                if !navigationStack.isEmpty {
                    Button {
                        navigationStack.removeLast()
                        selectedNode = nil
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                if let sel = selectedNode, sel.isDirectory {
                    Button {
                        drillDown(sel)
                    } label: {
                        Label("Zoom In", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func nodeDetail(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon + name
            HStack(spacing: 8) {
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(node))
                    .foregroundColor(node.isDirectory ? .accentColor : Color(nsColor: NSColor.systemOrange))
                    .font(.title2)

                Text(node.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)
            }

            Divider()

            detailRow("Size", node.formattedSize)

            if node.isDirectory {
                detailRow("Items", "\(node.children.count) direct")
                detailRow("Total items", "\(countAll(node))")
            } else {
                detailRow("Type", node.fileExtension.isEmpty ? "File" : ".\(node.fileExtension)")
            }

            detailRow("Path", node.url.deletingLastPathComponent().path)
                .help(node.url.path)

            Divider()

            // Top 5 children
            if node.isDirectory && !node.children.isEmpty {
                Text("Largest items")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(node.sortedChildren.prefix(8)) { child in
                    HStack(spacing: 6) {
                        Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundColor(child.isDirectory ? .accentColor : .secondary)
                            .font(.caption)
                            .frame(width: 14)
                        Text(child.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(child.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            Text("Disk Usage")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select a folder to visualize disk usage as a treemap.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 12) {
                Button("Open Folder…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button("Scan Home") { scanURL(URL(fileURLWithPath: NSHomeDirectory())) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tooltip overlay

    @ViewBuilder
    private var tooltipOverlay: some View {
        if let hovered = hoveredNode {
            TooltipView(node: hovered)
                .offset(
                    x: mouseLocation.x + 14,
                    y: max(mouseLocation.y - 10, 10)
                )
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.1), value: hoveredNode?.id)
                .zIndex(100)
        }
    }

    // MARK: - Helpers

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to analyze disk usage"
        if panel.runModal() == .OK, let url = panel.url {
            scanURL(url)
        }
    }

    private func scanURL(_ url: URL) {
        navigationStack.removeAll()
        selectedNode = nil
        scanner.prepareToScan(url: url)
    }

    private func drillDown(_ node: FileNode) {
        guard node.isDirectory else { return }
        navigationStack.append(node)
        selectedNode = nil
    }

    private func fileIcon(_ node: FileNode) -> String {
        switch node.fileExtension {
        case "mp4", "mov", "avi", "mkv", "m4v": return "film"
        case "mp3", "aac", "flac", "wav", "m4a": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "zip", "tar", "gz", "bz2", "dmg", "pkg": return "archivebox"
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "ts", "go", "rs", "cpp", "c": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func countAll(_ node: FileNode) -> Int {
        node.children.reduce(0) { total, child in
            total + 1 + (child.isDirectory ? countAll(child) : 0)
        }
    }
}

// MARK: - Legend View (shown in detail panel bottom)

struct LegendView: View {
    private let items: [(String, Color)] = [
        ("Video", Color(red: 0.85, green: 0.33, blue: 0.33)),
        ("Audio", Color(red: 0.93, green: 0.58, blue: 0.22)),
        ("Images", Color(red: 0.95, green: 0.77, blue: 0.20)),
        ("Archives", Color(red: 0.60, green: 0.40, blue: 0.80)),
        ("Documents", Color(red: 0.90, green: 0.45, blue: 0.35)),
        ("Code", Color(red: 0.25, green: 0.75, blue: 0.55)),
        ("Binaries", Color(red: 0.50, green: 0.50, blue: 0.90)),
        ("Other", Color(red: 0.55, green: 0.65, blue: 0.55)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Types")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(items, id: \.0) { label, color in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 10, height: 10)
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(8)
    }
}
