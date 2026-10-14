import CoreGraphics
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

@Suite struct VariableRowHeightTests {
    // rows: 0..<30, 30..<90, 90..<120, 120..<180, 180..<200   (heights 30, 60, 30, 60, 20)
    let g = GridGeometry(rowCount: 5, rowHeights: .variable([30, 60, 30, 60, 20]), columnWidths: [100])

    @Test func positionsAreRunningTotals() {
        #expect(g.contentHeight == 200)
        #expect([0, 1, 2, 3, 4].map(g.minY(ofRow:)) == [0, 30, 90, 120, 180])
        #expect([0, 1, 2, 3, 4].map(g.height(ofRow:)) == [30, 60, 30, 60, 20])
    }

    @Test func rowLookupIsExactAtBoundaries() {
        #expect(g.row(atY: 0) == 0)
        #expect(g.row(atY: 29.9) == 0)
        #expect(g.row(atY: 30) == 1)
        #expect(g.row(atY: 89.9) == 1)
        #expect(g.row(atY: 90) == 2)
        #expect(g.row(atY: 199.9) == 4)
        #expect(g.row(atY: 200) == nil)
        #expect(g.row(atY: -1) == nil)
    }

    @Test func visibleRows() {
        #expect(g.visibleRows(minY: 0, height: 50, overscan: 0) == 0..<2)
        #expect(g.visibleRows(minY: 30, height: 60, overscan: 0) == 1..<2)
        #expect(g.visibleRows(minY: 85, height: 40, overscan: 0) == 1..<4)
        #expect(g.visibleRows(minY: 0, height: 10_000, overscan: 0) == 0..<5)
        #expect(g.visibleRows(minY: 150, height: 100, overscan: 0) == 3..<5)
        #expect(g.visibleRows(minY: 85, height: 40, overscan: 1) == 0..<5)
    }

    @Test func overscrollIsClamped() {
        #expect(g.visibleRows(minY: -50, height: 60, overscan: 0) == 0..<1)  // only 10 pt of the band is on the grid
        #expect(g.visibleRows(minY: 500, height: 60, overscan: 0) == 4..<5)
    }

    @Test func fewerHeightsThanRowsRepeatTheLast() {
        let short = GridGeometry(rowCount: 4, rowHeights: .variable([10, 20]), columnWidths: [10])
        #expect(short.contentHeight == 70)  // 10, 20, then the last height (20) twice
        let none = GridGeometry(rowCount: 2, rowHeights: .variable([]), columnWidths: [10])
        #expect(none.contentHeight == 80)
    }

    @Test func nonPositiveHeightsAreClamped() {
        let z = GridGeometry(rowCount: 2, rowHeights: .variable([0, -5]), columnWidths: [10])
        #expect(z.contentHeight == 2)
    }

    @Test func aHundredThousandRowsStayFast() {
        let heights = (0..<100_000).map { CGFloat(30 + $0 % 3 * 10) }
        let big = GridGeometry(rowCount: 100_000, rowHeights: .variable(heights), columnWidths: [100])
        let mid = big.minY(ofRow: 60_000)
        #expect(big.row(atY: mid) == 60_000)
        #expect(big.row(atY: mid - 0.01) == 59_999)
        let v = big.visibleRows(minY: mid, height: 800, overscan: 0)
        #expect(v.lowerBound == 60_000 && v.count > 15 && v.count < 30)
    }

    @Test func literalsMeanEqualHeights() {
        let eq = GridGeometry(rowCount: 10, rowHeights: 44, columnWidths: [10])
        #expect(eq.contentHeight == 440 && eq.height(ofRow: 3) == 44)
    }
}
