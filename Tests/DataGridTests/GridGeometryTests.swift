import Testing
@testable import DataGrid

@Suite struct GridGeometryTests {
    let g = GridGeometry(rowCount: 100_000, rowHeight: 40, columnWidths: [100, 150, 80, 120])

    @Test func sizes() {
        #expect(g.contentWidth == 450)
        #expect(g.contentHeight == 4_000_000)
        #expect(g.columnCount == 4)
        #expect(g.minX(ofColumn: 0) == 0)
        #expect(g.minX(ofColumn: 2) == 250)
        #expect(g.minY(ofRow: 3) == 120)
    }

    @Test func columnLookupIsExactAtBoundaries() {
        #expect(g.column(atX: 0) == 0)
        #expect(g.column(atX: 99.9) == 0)
        #expect(g.column(atX: 100) == 1)
        #expect(g.column(atX: 249.9) == 1)
        #expect(g.column(atX: 250) == 2)
        #expect(g.column(atX: 449.9) == 3)
        #expect(g.column(atX: 450) == nil)
        #expect(g.column(atX: -1) == nil)
    }

    @Test func rowLookup() {
        #expect(g.row(atY: 0) == 0)
        #expect(g.row(atY: 39.9) == 0)
        #expect(g.row(atY: 40) == 1)
        #expect(g.row(atY: 3_999_999) == 99_999)
        #expect(g.row(atY: 4_000_000) == nil)
        #expect(g.row(atY: -0.1) == nil)
    }

    @Test func visibleRowsAtTop() {
        // 800 pt viewport = 20 rows, plus 2 overscan below; nothing above row 0
        #expect(g.visibleRows(minY: 0, height: 800) == 0..<22)
    }

    @Test func visibleRowsInTheMiddleAndAtTheEnd() {
        #expect(g.visibleRows(minY: 40_000, height: 800) == 998..<1022)
        // scrolled to the bottom: clamped to the row count
        #expect(g.visibleRows(minY: 4_000_000 - 800, height: 800) == 99_978..<100_000)
    }

    @Test func partialRowsAreIncluded() {
        // a viewport starting mid-row 5 and ending mid-row 7 sees rows 5, 6 and 7
        #expect(g.visibleRows(minY: 5 * 40 + 10, height: 2 * 40, overscan: 0) == 5..<8)
    }

    @Test func overscrollAboveTheTopIsClamped() {
        #expect(g.visibleRows(minY: -120, height: 400, overscan: 0) == 0..<7)
    }

    @Test func visibleColumns() {
        #expect(g.visibleColumns(minX: 0, width: 120, overscan: 0) == 0..<2)
        #expect(g.visibleColumns(minX: 100, width: 150, overscan: 0) == 1..<2)
        #expect(g.visibleColumns(minX: 90, width: 20, overscan: 0) == 0..<2)
        #expect(g.visibleColumns(minX: 0, width: 5_000, overscan: 0) == 0..<4)
        #expect(g.visibleColumns(minX: 0, width: 120, overscan: 1) == 0..<3)
    }

    @Test func emptyGridsAreSafe() {
        let none = GridGeometry(rowCount: 0, rowHeight: 40, columnWidths: [])
        #expect(none.visibleRows(minY: 0, height: 800) == 0..<0)
        #expect(none.visibleColumns(minX: 0, width: 800) == 0..<0)
        #expect(none.contentWidth == 0 && none.column(atX: 0) == nil && none.row(atY: 0) == nil)
        let noRows = GridGeometry(rowCount: 0, rowHeight: 40, columnWidths: [50])
        #expect(noRows.visibleRows(minY: 0, height: 100) == 0..<0)
    }

    @Test func zeroWidthColumnsAreSkipped() {
        let z = GridGeometry(rowCount: 1, rowHeight: 10, columnWidths: [50, 0, 50])
        #expect(z.column(atX: 49) == 0)
        #expect(z.column(atX: 50) == 2)
    }

    @Test func negativeInputsAreClamped() {
        let n = GridGeometry(rowCount: -5, rowHeight: -3, columnWidths: [-10, 20])
        #expect(n.rowCount == 0 && n.rowHeight == 1 && n.columnWidths == [0, 20])
    }
}
