/// A request to scroll a ``DataGrid`` so a row and/or column is at the top-left of the scrolling area,
/// just inside the pinned header and first column.
///
/// Give either component, or both. A request that leaves out a component keeps the scroll position on
/// that axis. The grid resets the binding to `nil` once it has scrolled, so the same request can be made
/// again.
///
/// ```swift
/// @State private var scrollTo: GridScrollRequest?
/// DataGrid(rows: 100_000, columnWidths: $widths, scrollTo: $scrollTo) { ... }
/// Button("Jump to row 5,000") { scrollTo = GridScrollRequest(row: 4_999) }
/// ```
public struct GridScrollRequest: Equatable, Sendable {
    public var row: Int?
    public var column: Int?

    public init(row: Int? = nil, column: Int? = nil) {
        self.row = row
        self.column = column
    }
}
