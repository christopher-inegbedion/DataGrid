import SwiftUI

/// A scrolling grid with a pinned header row and a pinned first column, that stays cheap at any size.
///
/// Only the cells in (and just around) the viewport exist, so a grid of 100,000 rows costs what a
/// screenful costs. The header row and the row-header column are pinned with ``SwiftUI/View/visualEffect(_:)``
/// inside the scroll content, so they are repositioned at render time, in the same pass as the scroll,
/// rather than chasing it with state.
///
/// ```swift
/// DataGrid(rows: 100_000, columns: 12, columnWidth: 120) { row, column in
///     Text("R\(row) C\(column)")
/// } columnHeader: { column in
///     Text("Column \(column)").bold()
/// } rowHeader: { row in
///     Text("\(row + 1)")
/// }
/// ```
public struct DataGrid<Cell: View, ColumnHeader: View, RowHeader: View, Corner: View>: View {
    private let rowCount: Int
    private let rowHeights: RowHeights
    private let headerHeight: CGFloat
    private let rowHeaderWidth: CGFloat
    private let minimumColumnWidth: CGFloat
    private let resizable: Bool
    private let cell: (Int, Int) -> Cell
    private let columnHeader: (Int) -> ColumnHeader
    private let rowHeader: (Int) -> RowHeader
    private let corner: Corner

    private let isSelected: (GridPosition) -> Bool
    private let didTap: (GridPosition) -> Void

    @Binding private var columnWidths: [CGFloat]
    @Binding private var scrollRequest: GridScrollRequest?
    @State private var window = GridWindow.initial
    @State private var resizeStart: (column: Int, width: CGFloat)?
    @State private var position = ScrollPosition()
    @State private var geometryCache = GeometryCache()
    @State private var offsetTracker = OffsetTracker()

    /// - Parameters:
    ///   - rows: Number of body rows.
    ///   - columnWidths: One width per column. Dragging a column header's trailing edge changes it.
    ///   - rowHeights: One height for every row (`rowHeights: 44`), or `.variable([...])` for one each.
    ///   - headerHeight: Height of the pinned header row.
    ///   - rowHeaderWidth: Width of the pinned first column; 0 for none.
    ///   - minimumColumnWidth: The narrowest a column can be dragged to.
    ///   - selection: The selected cell. Tapping a cell selects it.
    ///   - scrollTo: Set to scroll the grid to a row and/or column; reset to `nil` afterwards.
    public init(
        rows: Int,
        columnWidths: Binding<[CGFloat]>,
        rowHeights: RowHeights = 40,
        headerHeight: CGFloat = 40,
        rowHeaderWidth: CGFloat = 56,
        minimumColumnWidth: CGFloat = 48,
        selection: Binding<GridPosition?> = .constant(nil),
        scrollTo: Binding<GridScrollRequest?> = .constant(nil),
        @ViewBuilder cell: @escaping (_ row: Int, _ column: Int) -> Cell,
        @ViewBuilder columnHeader: @escaping (_ column: Int) -> ColumnHeader,
        @ViewBuilder rowHeader: @escaping (_ row: Int) -> RowHeader,
        @ViewBuilder corner: () -> Corner
    ) {
        self.init(
            rows: rows, columnWidths: columnWidths, rowHeights: rowHeights, headerHeight: headerHeight,
            rowHeaderWidth: rowHeaderWidth, minimumColumnWidth: minimumColumnWidth,
            isSelected: { selection.wrappedValue == $0 },
            didTap: { selection.wrappedValue = GridSelectionRule.single(selection.wrappedValue, tapped: $0) },
            scrollTo: scrollTo, cell: cell, columnHeader: columnHeader, rowHeader: rowHeader, corner: corner()
        )
    }

    /// A grid where tapping a cell toggles it in a set, for selecting several cells.
    public init(
        rows: Int,
        columnWidths: Binding<[CGFloat]>,
        rowHeights: RowHeights = 40,
        headerHeight: CGFloat = 40,
        rowHeaderWidth: CGFloat = 56,
        minimumColumnWidth: CGFloat = 48,
        selection: Binding<Set<GridPosition>>,
        scrollTo: Binding<GridScrollRequest?> = .constant(nil),
        @ViewBuilder cell: @escaping (_ row: Int, _ column: Int) -> Cell,
        @ViewBuilder columnHeader: @escaping (_ column: Int) -> ColumnHeader,
        @ViewBuilder rowHeader: @escaping (_ row: Int) -> RowHeader,
        @ViewBuilder corner: () -> Corner
    ) {
        self.init(
            rows: rows, columnWidths: columnWidths, rowHeights: rowHeights, headerHeight: headerHeight,
            rowHeaderWidth: rowHeaderWidth, minimumColumnWidth: minimumColumnWidth,
            isSelected: { selection.wrappedValue.contains($0) },
            didTap: { selection.wrappedValue = GridSelectionRule.toggling(selection.wrappedValue, tapped: $0) },
            scrollTo: scrollTo, cell: cell, columnHeader: columnHeader, rowHeader: rowHeader, corner: corner()
        )
    }

    private init(
        rows: Int, columnWidths: Binding<[CGFloat]>, rowHeights: RowHeights, headerHeight: CGFloat,
        rowHeaderWidth: CGFloat, minimumColumnWidth: CGFloat,
        isSelected: @escaping (GridPosition) -> Bool, didTap: @escaping (GridPosition) -> Void,
        scrollTo: Binding<GridScrollRequest?>,
        cell: @escaping (Int, Int) -> Cell, columnHeader: @escaping (Int) -> ColumnHeader,
        rowHeader: @escaping (Int) -> RowHeader, corner: Corner
    ) {
        self.rowCount = max(0, rows)
        self._columnWidths = columnWidths
        self.rowHeights = rowHeights
        self.headerHeight = headerHeight
        self.rowHeaderWidth = rowHeaderWidth
        self.minimumColumnWidth = minimumColumnWidth
        self.resizable = true
        self.isSelected = isSelected
        self.didTap = didTap
        self._scrollRequest = scrollTo
        self.cell = cell
        self.columnHeader = columnHeader
        self.rowHeader = rowHeader
        self.corner = corner
    }

    public var body: some View {
        let geometry = geometryCache.geometry(rowCount: rowCount, rowHeights: rowHeights, columnWidths: columnWidths)
        let totalWidth = rowHeaderWidth + geometry.contentWidth
        let totalHeight = headerHeight + geometry.contentHeight
        let rows = window.rows.clamped(to: 0..<rowCount)
        let columns = window.columns.clamped(to: 0..<geometry.columnCount)

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                bodyCells(rows: rows, columns: columns, geometry: geometry)
                columnHeaders(columns: columns, geometry: geometry, width: totalWidth)
                    .zIndex(1)
                if rowHeaderWidth > 0 {
                    rowHeaders(rows: rows, geometry: geometry, height: totalHeight)
                        .zIndex(1)
                    cornerCell
                        .zIndex(2)
                }
            }
            .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
        }
        .onScrollGeometryChange(for: GridWindow.self) { scroll in
            // The window only changes when a row or column enters or leaves, so the view
            // updates a few times a second while scrolling, not once per frame.
            let rect = scroll.visibleRect
            return GridWindow(
                rows: geometry.visibleRows(minY: rect.minY - headerHeight, height: rect.height),
                columns: geometry.visibleColumns(minX: rect.minX - rowHeaderWidth, width: rect.width)
            )
        } action: { _, new in
            window = new
        }
        .onScrollGeometryChange(for: CGPoint.self) { geo in
            // ScrollPosition measures from the content's own origin, the geometry's offset from the
            // inset edge: add the insets back so the two agree
            CGPoint(x: geo.contentOffset.x + geo.contentInsets.leading, y: geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, new in
            offsetTracker.offset = new  // not state: remembering it must not re-render the grid
        }
        .scrollPosition($position)
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            scroll(to: request, geometry: geometry)
            scrollRequest = nil
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private func bodyCells(rows: Range<Int>, columns: Range<Int>, geometry: GridGeometry) -> some View {
        ForEach(rows, id: \.self) { row in
            ForEach(columns, id: \.self) { column in
                bodyCell(row: row, column: column, geometry: geometry)
            }
        }
    }

    private func bodyCell(row: Int, column: Int, geometry: GridGeometry) -> some View {
        let position = GridPosition(row: row, column: column)
        let isSelected = isSelected(position)
        let x = rowHeaderWidth + geometry.minX(ofColumn: column)
        let y = headerHeight + geometry.minY(ofRow: row)
        return cell(row, column)
            .frame(width: geometry.columnWidths[column], height: geometry.height(ofRow: row))
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .gridLines()
            .contentShape(Rectangle())
            .onTapGesture { didTap(position) }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Row \(row + 1), column \(column + 1)")
            .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
            .offset(x: x, y: y)
    }

    private func columnHeaders(columns: Range<Int>, geometry: GridGeometry, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(columns, id: \.self) { column in
                columnHeader(column)
                    .frame(width: geometry.columnWidths[column], height: headerHeight)
                    .headerBackground()
                    .overlay(alignment: .trailing) { resizeHandle(column: column) }
                    .accessibilityAddTraits(.isHeader)
                    .offset(x: rowHeaderWidth + geometry.minX(ofColumn: column))
            }
        }
        .frame(width: width, height: headerHeight, alignment: .topLeading)
        .visualEffect { content, proxy in
            content.offset(y: max(0, -proxy.frame(in: .scrollView).minY))
        }
    }

    private func rowHeaders(rows: Range<Int>, geometry: GridGeometry, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows, id: \.self) { row in
                rowHeader(row)
                    .frame(width: rowHeaderWidth, height: geometry.height(ofRow: row))
                    .headerBackground()
                    .accessibilityAddTraits(.isHeader)
                    .offset(y: headerHeight + geometry.minY(ofRow: row))
            }
        }
        .frame(width: rowHeaderWidth, height: height, alignment: .topLeading)
        .visualEffect { content, proxy in
            content.offset(x: max(0, -proxy.frame(in: .scrollView).minX))
        }
    }

    private var cornerCell: some View {
        corner
            .frame(width: rowHeaderWidth, height: headerHeight)
            .headerBackground()
            .visualEffect { content, proxy in
                let frame = proxy.frame(in: .scrollView)
                return content.offset(x: max(0, -frame.minX), y: max(0, -frame.minY))
            }
    }

    /// Puts the requested row and column just inside the pinned header and first column.
    ///
    /// Always scrolls to an explicit point: SwiftUI's one-axis `scrollTo(x:)` and `scrollTo(y:)` move the
    /// other axis back to zero, so the axis a request leaves out is filled in from the live offset.
    private func scroll(to request: GridScrollRequest, geometry: GridGeometry) {
        guard request.row != nil || request.column != nil else { return }
        var target = offsetTracker.offset
        if let column = request.column { target.x = geometry.minX(ofColumn: clamp(column, geometry.columnCount)) }
        if let row = request.row { target.y = geometry.minY(ofRow: clamp(row, geometry.rowCount)) }
        // SwiftUI ignores a position equal to the one it last applied, so repeating a request after
        // the user scrolled away would do nothing. A target one floating-point step off is a different
        // value to SwiftUI and the same pixel to the eye.
        if target == offsetTracker.lastRequested { target.y = target.y.nextUp }
        offsetTracker.lastRequested = target
        position.scrollTo(point: target)
    }

    private func clamp(_ index: Int, _ count: Int) -> Int { max(0, min(index, max(0, count - 1))) }

    private func resizeHandle(column: Int) -> some View {
        Color.clear
            .frame(width: 10)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = resizeStart?.column == column ? resizeStart!.width : columnWidths[column]
                        resizeStart = (column, start)
                        columnWidths[column] = max(minimumColumnWidth, start + drag.translation.width)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .accessibilityHidden(true)
    }
}

// MARK: Conveniences

extension DataGrid where RowHeader == EmptyView, Corner == EmptyView {
    /// A grid with fixed-width columns and no pinned first column.
    public init(
        rows: Int,
        columns: Int,
        columnWidth: CGFloat = 120,
        rowHeight: CGFloat = 40,
        headerHeight: CGFloat = 40,
        selection: Binding<GridPosition?> = .constant(nil),
        @ViewBuilder cell: @escaping (_ row: Int, _ column: Int) -> Cell,
        @ViewBuilder columnHeader: @escaping (_ column: Int) -> ColumnHeader
    ) {
        self.init(
            rows: rows,
            columnWidths: .constant(Array(repeating: columnWidth, count: max(0, columns))),
            rowHeights: .uniform(rowHeight),
            headerHeight: headerHeight,
            rowHeaderWidth: 0,
            selection: selection,
            cell: cell,
            columnHeader: columnHeader,
            rowHeader: { _ in EmptyView() },
            corner: { EmptyView() }
        )
    }
}

extension DataGrid where Corner == EmptyView {
    /// A grid with fixed-width columns, a pinned first column and an empty corner.
    public init(
        rows: Int,
        columns: Int,
        columnWidth: CGFloat = 120,
        rowHeight: CGFloat = 40,
        headerHeight: CGFloat = 40,
        rowHeaderWidth: CGFloat = 56,
        selection: Binding<GridPosition?> = .constant(nil),
        @ViewBuilder cell: @escaping (_ row: Int, _ column: Int) -> Cell,
        @ViewBuilder columnHeader: @escaping (_ column: Int) -> ColumnHeader,
        @ViewBuilder rowHeader: @escaping (_ row: Int) -> RowHeader
    ) {
        self.init(
            rows: rows,
            columnWidths: .constant(Array(repeating: columnWidth, count: max(0, columns))),
            rowHeights: .uniform(rowHeight),
            headerHeight: headerHeight,
            rowHeaderWidth: rowHeaderWidth,
            selection: selection,
            cell: cell,
            columnHeader: columnHeader,
            rowHeader: rowHeader,
            corner: { EmptyView() }
        )
    }
}

// MARK: Internals

/// Remembers the last geometry so a grid with variable row heights does not rebuild its running
/// totals (O(rows)) every time the view updates. Equal inputs are detected by array identity first,
/// so the common case, nothing changed, is a pointer comparison.
/// The live scroll offset, kept outside `@State` so tracking it never re-renders the grid.
final class OffsetTracker {
    var offset = CGPoint.zero
    var lastRequested: CGPoint?
}

final class GeometryCache {
    private var rowCount = -1
    private var rowHeights = RowHeights.uniform(0)
    private var columnWidths: [CGFloat] = []
    private var cached = GridGeometry(rowCount: 0, rowHeight: 1, columnWidths: [])

    func geometry(rowCount: Int, rowHeights: RowHeights, columnWidths: [CGFloat]) -> GridGeometry {
        if rowCount != self.rowCount || rowHeights != self.rowHeights || columnWidths != self.columnWidths {
            cached = GridGeometry(rowCount: rowCount, rowHeights: rowHeights, columnWidths: columnWidths)
            self.rowCount = rowCount
            self.rowHeights = rowHeights
            self.columnWidths = columnWidths
        }
        return cached
    }
}

/// The rows and columns that currently exist. Equatable so `onScrollGeometryChange` only
/// fires when the set changes.
struct GridWindow: Equatable {
    var rows: Range<Int>
    var columns: Range<Int>

    /// Before the first scroll report: enough to fill a large screen.
    static let initial = GridWindow(rows: 0..<40, columns: 0..<12)
}

private extension View {
    func gridLines() -> some View {
        overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(.separator).frame(height: 0.5)
                Rectangle().fill(.separator).frame(width: 0.5)
            }
        }
    }

    func headerBackground() -> some View {
        background {
            ZStack {
                Rectangle().fill(.background)
                Rectangle().fill(Color.secondary.opacity(0.12))
            }
        }
        .gridLines()
    }
}

#Preview {
    DataGrid(rows: 100_000, columns: 12, columnWidth: 120) { row, column in
        Text("R\(row) C\(column)")
    } columnHeader: { column in
        Text("Column \(column)").bold()
    } rowHeader: { row in
        Text("\(row + 1)")
    }
}
