import SwiftUI

// MARK: - TreeMapView

struct TreeMapView: View {
    let node: FileNode
    @Binding var selectedNode: FileNode?
    @Binding var hoveredNode: FileNode?

    /// Cached layout — only recomputed when `node` identity or container
    /// size changes, NOT when selectedNode / hoveredNode change.
    @State private var tiles: [Tile] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Transparent fill so GeometryReader always reports the full size.
                Color.clear

                ForEach(tiles) { tile in
                    TileView(
                        tile: tile,
                        isSelected: selectedNode?.id == tile.node.id,
                        isHovered: hoveredNode?.id == tile.node.id
                    )
                    // .equatable() lets SwiftUI skip body re-execution for tiles
                    // whose isSelected / isHovered flags haven't changed.
                    .equatable()
                    .frame(width: tile.rect.width, height: tile.rect.height)
                    .offset(x: tile.rect.minX, y: tile.rect.minY)
                    .onTapGesture {
                        guard tile.node.totalSize >= 1_000_000 else { return }
                        selectedNode = tile.node
                    }
                    .onHover { inside in
                        guard tile.node.totalSize >= 1_000_000 else { return }
                        hoveredNode = inside ? tile.node : nil
                    }
                }
            }
            .onAppear {
                tiles = TreeMapLayout.layout(
                    node: node, rect: CGRect(origin: .zero, size: geo.size), depth: 0)
            }
            .onChange(of: node.id) { _ in
                tiles = TreeMapLayout.layout(
                    node: node, rect: CGRect(origin: .zero, size: geo.size), depth: 0)
            }
            .onChange(of: geo.size) { newSize in
                tiles = TreeMapLayout.layout(
                    node: node, rect: CGRect(origin: .zero, size: newSize), depth: 0)
            }
        }
    }
}

// MARK: - TileView

private struct TileView: View, Equatable {
    let tile: Tile
    let isSelected: Bool
    let isHovered: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tile.id == rhs.tile.id &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isHovered  == rhs.isHovered
    }

    private var isDirectory: Bool { tile.node.isDirectory }

    // Directories get a slightly different treatment than files
    private var fillColor: Color {
        if isDirectory {
            return depthColor(tile.depth).opacity(0.85)
        }
        return tile.node.color
    }

    private var strokeColor: Color {
        if isSelected { return .white }
        if isHovered { return .white.opacity(0.7) }
        return .black.opacity(0.25)
    }

    private var strokeWidth: CGFloat {
        isSelected ? 2 : (isHovered ? 1.5 : 0.5)
    }

    var body: some View {
        let w = tile.rect.width
        let h = tile.rect.height

        ZStack {
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )

            // Only show label if the tile is big enough to be readable
            if w > 40 && h > 14 {
                labelView(width: w, height: h)
            }
        }
        .scaleEffect(isHovered && !isDirectory ? 1.0 : 1.0) // could animate
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    @ViewBuilder
    private func labelView(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(tile.node.name)
                .font(.system(size: clamp(min: 9, val: width / 8, max: 13)))
                .fontWeight(isDirectory ? .semibold : .regular)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2)

            if height > 28 && !isDirectory {
                Text(tile.node.formattedSize)
                    .font(.system(size: clamp(min: 8, val: width / 10, max: 11)))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private func clamp(min: CGFloat, val: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(val, max))
    }

    private func depthColor(_ depth: Int) -> Color {
        // Cycle through a palette for directories at different depths
        let palette: [Color] = [
            Color(red: 0.22, green: 0.40, blue: 0.65),
            Color(red: 0.20, green: 0.55, blue: 0.45),
            Color(red: 0.55, green: 0.30, blue: 0.60),
            Color(red: 0.60, green: 0.45, blue: 0.15),
            Color(red: 0.25, green: 0.50, blue: 0.60),
        ]
        return palette[depth % palette.count]
    }
}

// MARK: - Tooltip Overlay

struct TooltipView: View {
    let node: FileNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.name)
                .font(.headline)
                .foregroundColor(.primary)

            Text(node.url.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Divider()

            HStack {
                Label(node.formattedSize, systemImage: node.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.subheadline)

                if node.isDirectory {
                    Text("•  \(node.children.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        .frame(maxWidth: 320)
    }
}
