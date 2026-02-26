import CoreGraphics
import Foundation

// MARK: - Tile

struct Tile: Identifiable {
    let id: UUID
    let node: FileNode
    let rect: CGRect
    let depth: Int
}

// MARK: - Squarified Treemap Layout

enum TreeMapLayout {

    /// Recursively computes tiles for `node` within `rect`, going `depth` levels deep.
    static func layout(node: FileNode, rect: CGRect, depth: Int, maxDepth: Int = 4) -> [Tile] {
        guard rect.width > 1, rect.height > 1 else { return [] }

        let children = node.sortedChildren.filter { $0.totalSize > 0 }
        guard !children.isEmpty else {
            return [Tile(id: node.id, node: node, rect: rect, depth: depth)]
        }

        let totalSize = children.reduce(Int64(0)) { $0 + $1.totalSize }
        guard totalSize > 0 else { return [] }

        // Compute rects for children using the squarified algorithm
        let childRects = squarify(items: children.map { Double($0.totalSize) }, rect: rect)

        var tiles: [Tile] = []
        for (child, childRect) in zip(children, childRects) {
            guard childRect.width > 1, childRect.height > 1 else { continue }

            if child.isDirectory && depth < maxDepth {
                // Add a thin header rect for the directory label, then recurse
                let headerHeight: CGFloat = min(18, childRect.height * 0.15)
                let header = CGRect(x: childRect.minX, y: childRect.minY,
                                    width: childRect.width, height: headerHeight)
                let body = CGRect(x: childRect.minX, y: childRect.minY + headerHeight,
                                  width: childRect.width, height: childRect.height - headerHeight)

                tiles.append(Tile(id: child.id, node: child, rect: header, depth: depth))

                if body.width > 2, body.height > 2 {
                    let subTiles = layout(node: child, rect: body, depth: depth + 1, maxDepth: maxDepth)
                    tiles.append(contentsOf: subTiles)
                }
            } else {
                tiles.append(Tile(id: child.id, node: child, rect: childRect, depth: depth))
            }
        }
        return tiles
    }

    // MARK: Squarify algorithm

    /// Returns one CGRect per item, filling `rect` proportionally to `items` weights.
    static func squarify(items: [Double], rect: CGRect) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        let total = items.reduce(0, +)
        guard total > 0 else { return Array(repeating: .zero, count: items.count) }

        // Pair each value with its original index so we can write back to `result`.
        let indexed: [(Int, Double)] = items.enumerated().map { ($0.offset, $0.element) }
        var result = [CGRect](repeating: .zero, count: items.count)
        squarifyHelper(items: indexed[...], rect: rect, total: total, result: &result)
        return result
    }

    /// Recursively lay out `items` (as an ArraySlice — zero copies) into `rect`.
    ///
    /// Instead of `removeFirst()` (O(n)) we pass a slice and advance `startIndex`;
    /// instead of `currentRow + [next]` (allocates a new array every iteration)
    /// we track the row as a range `[rowStart, rowEnd)` into the slice and compute
    /// aspect ratios incrementally.
    private static func squarifyHelper(
        items: ArraySlice<(Int, Double)>,
        rect: CGRect,
        total: Double,
        result: inout [CGRect]
    ) {
        guard !items.isEmpty, rect.width > 1, rect.height > 1, total > 0 else { return }

        let layoutHorizontal = rect.width >= rect.height
        let layoutLen  = layoutHorizontal ? Double(rect.width)  : Double(rect.height)
        let perpLen    = layoutHorizontal ? Double(rect.height) : Double(rect.width)

        // Build the current row using index range [rowStart, rowEnd) into `items`.
        // We advance rowEnd one element at a time; if adding the next item would
        // worsen the aspect ratio we stop.
        let rowStart = items.startIndex
        var rowEnd   = rowStart          // exclusive upper bound
        var rowTotal = 0.0
        var prevWorst = Double.infinity

        var cursor = items.startIndex
        while cursor < items.endIndex {
            let val      = items[cursor].1
            let testTotal = rowTotal + val
            let testWorst = worstAspect(
                items: items[rowStart..<cursor],
                rowTotal: rowTotal,
                nextVal: val,
                testTotal: testTotal,
                layoutLen: layoutLen,
                perpLen: perpLen,
                outerTotal: total
            )

            if rowEnd == rowStart || testWorst <= prevWorst {
                rowTotal  = testTotal
                prevWorst = testWorst
                rowEnd    = items.index(after: cursor)
                cursor    = rowEnd
            } else {
                break
            }
        }

        // Place all items in [rowStart, rowEnd).
        let rowThickness = (rowTotal / total) * perpLen
        var offset = 0.0
        for i in rowStart..<rowEnd {
            let (origIdx, val) = items[i]
            let length = rowTotal > 0 ? (val / rowTotal) * layoutLen : 0
            result[origIdx] = layoutHorizontal
                ? CGRect(x: rect.minX + offset, y: rect.minY,       width: length,       height: rowThickness)
                : CGRect(x: rect.minX,          y: rect.minY + offset, width: rowThickness, height: length)
            offset += length
        }

        // Recurse with the remaining slice — no copy.
        let tail = items[rowEnd...]
        guard !tail.isEmpty else { return }

        let remainingRect: CGRect = layoutHorizontal
            ? CGRect(x: rect.minX, y: rect.minY + rowThickness,
                     width: rect.width, height: rect.height - rowThickness)
            : CGRect(x: rect.minX + rowThickness, y: rect.minY,
                     width: rect.width - rowThickness, height: rect.height)

        squarifyHelper(items: tail, rect: remainingRect,
                       total: total - rowTotal, result: &result)
    }

    /// Worst aspect ratio if we add `nextVal` to the current row.
    /// Operates on a slice with no allocation.
    private static func worstAspect(
        items: ArraySlice<(Int, Double)>,
        rowTotal: Double,
        nextVal: Double,
        testTotal: Double,
        layoutLen: Double,
        perpLen: Double,
        outerTotal: Double
    ) -> Double {
        guard testTotal > 0, outerTotal > 0 else { return Double.infinity }
        let h = (testTotal / outerTotal) * perpLen
        guard h > 0 else { return Double.infinity }

        var worst = 0.0
        // Existing items (with updated h)
        for (_, val) in items {
            let w = (val / testTotal) * layoutLen
            if w > 0 { worst = max(worst, max(w / h, h / w)) }
        }
        // The new item
        let wNew = (nextVal / testTotal) * layoutLen
        if wNew > 0 { worst = max(worst, max(wNew / h, h / wNew)) }
        return worst
    }
}

// MARK: - Convenience overload with CGSize

extension TreeMapLayout {
    static func squarify(items: [Double], size: CGSize) -> [CGRect] {
        squarify(items: items, rect: CGRect(origin: .zero, size: size))
    }
}
