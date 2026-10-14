import CoreGraphics

/// How tall the body rows are: all the same, or one height each.
///
/// ```swift
/// DataGrid(rows: 10_000, columnWidths: $widths, rowHeights: 44) { ... }                   // same height
/// DataGrid(rows: heights.count, columnWidths: $widths, rowHeights: .variable(heights)) { ... }
/// ```
///
/// Equal heights are the fast path: a row's position is a multiplication. Variable heights keep one
/// running total, built once and reused until the heights change, and rows are found by binary search.
public struct RowHeights: Equatable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    enum Storage: Equatable, Sendable {
        case uniform(CGFloat)
        case variable([CGFloat])
    }

    let storage: Storage

    /// Every row is `height` tall.
    public static func uniform(_ height: CGFloat) -> RowHeights { RowHeights(storage: .uniform(height)) }

    /// Row `i` is `heights[i]` tall. If there are more rows than heights, the last height repeats
    /// (40 if the array is empty).
    public static func variable(_ heights: [CGFloat]) -> RowHeights { RowHeights(storage: .variable(heights)) }

    public init(integerLiteral value: Int) { storage = .uniform(CGFloat(value)) }
    public init(floatLiteral value: Double) { storage = .uniform(CGFloat(value)) }
    init(storage: Storage) { self.storage = storage }
}
