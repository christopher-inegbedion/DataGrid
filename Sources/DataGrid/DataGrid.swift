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
    private let rowHeight: CGFloat
    private let headerHeight: CGFloat
    private let rowHeaderWidth: CGFloat
    private let minimumColumnWidth: CGFloat
    private let resizable: Bool
    private let cell: (Int, Int) -> Cell
    private let columnHeader: (Int) -> ColumnHeader
    private let rowHeader: (Int) -> RowHeader
    private let corner: Corner

    @Binding private var columnWidths: [CGFloat]
    @Binding private var selection: GridPosition?
    @State private var window = GridWindow.initial
    @State private var resizeStart: (column: Int, width: CGFloat)?

    /// - Parameters:
    ///   - rows: Number of body rows.
    ///   - columnWidths: One width per column. Dragging a column header's trailing edge changes it.
    ///   - rowHeight: Height of every body row.
    ///   - headerHeight: Height of the pinned header row.
    ///   - rowHeaderWidth: Width of the pinned first column; 0 for none.
    ///   - minimumColumnWidth: The narrowest a column can be dragged to.
    ///   - selection: The selected cell. Tapping a cell selects it.
    public init(
        rows: Int,
        columnWidths: Binding<[CGFloat]>,
        rowHeight: CGFloat = 40,
        headerHeight: CGFloat = 40,
        rowHeaderWidth: CGFloat = 56,
        minimumColumnWidth: CGFloat = 48,
        selection: Binding<GridPosition?> = .constant(nil),
        @ViewBuilder cell: @escaping (_ row: Int, _ column: Int) -> Cell,
        @ViewBuilder columnHeader: @escaping (_ column: Int) -> ColumnHeader,
        @ViewBuilder rowHeader: @escaping (_ row: Int) -> RowHeader,
        @ViewBuilder corner: () -> Corner
    ) {
        self.rowCount = max(0, rows)
        self._columnWidths = columnWidths
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.rowHeaderWidth = rowHeaderWidth
        self.minimumColumnWidth = minimumColumnWidth
        self.resizable = true
        self._selection = selection
        self.cell = cell
        self.columnHeader = columnHeader
        self.rowHeader = rowHeader
        self.corner = corner()
    }

    public var body: some View {
        let geometry = GridGeometry(rowCount: rowCount, rowHeight: rowHeight, columnWidths: columnWidths)
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
                    rowHeaders(rows: rows, height: totalHeight)
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
        let isSelected = selection == position
        let x = rowHeaderWidth + geometry.minX(ofColumn: column)
        let y = headerHeight + geometry.minY(ofRow: row)
        return cell(row, column)
            .frame(width: geometry.columnWidths[column], height: rowHeight)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .gridLines()
            .contentShape(Rectangle())
            .onTapGesture { selection = position }
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

    private func rowHeaders(rows: Range<Int>, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows, id: \.self) { row in
                rowHeader(row)
                    .frame(width: rowHeaderWidth, height: rowHeight)
                    .headerBackground()
                    .accessibilityAddTraits(.isHeader)
                    .offset(y: headerHeight + CGFloat(row) * rowHeight)
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
            rowHeight: rowHeight,
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
            rowHeight: rowHeight,
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
