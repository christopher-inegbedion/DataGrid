import CoreGraphics

/// The layout maths of a grid: where each column starts, and which rows and columns a
/// viewport can see. Pure value logic with no SwiftUI in it, so it is unit-tested directly.
///
/// Rows share one height, so a row's position is a multiplication and the visible rows are a
/// division. Columns have their own widths, so their positions are a running total and the
/// visible columns are found by binary search. Neither needs to look at every cell, which is
/// what keeps a grid of 100,000 rows as cheap as a grid of 100.
public struct GridGeometry: Equatable, Sendable {
    public let rowCount: Int
    public let rowHeight: CGFloat
    public let columnWidths: [CGFloat]
    /// `columnOffsets[c]` is the x of column `c`'s left edge; the last entry is the total width.
    private let columnOffsets: [CGFloat]

    public init(rowCount: Int, rowHeight: CGFloat, columnWidths: [CGFloat]) {
        self.rowCount = max(0, rowCount)
        self.rowHeight = max(1, rowHeight)
        self.columnWidths = columnWidths.map { max(0, $0) }
        var offsets = [CGFloat](repeating: 0, count: columnWidths.count + 1)
        for (i, w) in self.columnWidths.enumerated() { offsets[i + 1] = offsets[i] + w }
        self.columnOffsets = offsets
    }

    public var columnCount: Int { columnWidths.count }
    public var contentWidth: CGFloat { columnOffsets.last ?? 0 }
    public var contentHeight: CGFloat { CGFloat(rowCount) * rowHeight }

    public func minX(ofColumn column: Int) -> CGFloat { columnOffsets[column] }
    public func minY(ofRow row: Int) -> CGFloat { CGFloat(row) * rowHeight }

    /// The column containing `x`, or nil outside the grid.
    public func column(atX x: CGFloat) -> Int? {
        guard x >= 0, x < contentWidth else { return nil }
        // last offset <= x
        var low = 0, high = columnCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if columnOffsets[mid] <= x { low = mid } else { high = mid - 1 }
        }
        // zero-width columns share an offset with their neighbour: skip to one that has width
        var c = low
        while c < columnCount - 1, columnWidths[c] == 0 { c += 1 }
        return c
    }

    /// The row containing `y`, or nil outside the grid.
    public func row(atY y: CGFloat) -> Int? {
        guard y >= 0, y < contentHeight else { return nil }
        return min(rowCount - 1, Int(y / rowHeight))
    }

    /// Rows touching the band `[minY, minY + height)`, widened by `overscan` rows each side.
    public func visibleRows(minY: CGFloat, height: CGFloat, overscan: Int = 2) -> Range<Int> {
        guard rowCount > 0, height > 0 else { return 0..<0 }
        let first = Int((max(0, minY) / rowHeight).rounded(.down))
        let last = Int(((minY + height) / rowHeight).rounded(.up))
        let lo = min(rowCount, max(0, first - overscan))
        let hi = min(rowCount, max(lo, last + overscan))
        return lo..<hi
    }

    /// Columns touching the band `[minX, minX + width)`, widened by `overscan` columns each side.
    public func visibleColumns(minX: CGFloat, width: CGFloat, overscan: Int = 1) -> Range<Int> {
        guard columnCount > 0, width > 0, contentWidth > 0 else { return 0..<0 }
        let left = min(max(0, minX), contentWidth.nextDown)
        let right = min(max(0, minX + width), contentWidth)
        guard let first = column(atX: left) else { return 0..<0 }
        var last = column(atX: max(left, right.nextDown)) ?? columnCount - 1
        if right >= contentWidth { last = columnCount - 1 }
        let lo = max(0, first - overscan)
        let hi = min(columnCount, last + 1 + overscan)
        return lo..<max(lo, hi)
    }
}
