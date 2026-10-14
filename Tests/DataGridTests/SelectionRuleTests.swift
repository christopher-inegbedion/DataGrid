import Testing
@testable import DataGrid

@Suite struct SelectionRuleTests {
    let a = GridPosition(row: 1, column: 2)
    let b = GridPosition(row: 3, column: 4)

    @Test func singleSelectionReplaces() {
        #expect(GridSelectionRule.single(nil, tapped: a) == a)
        #expect(GridSelectionRule.single(a, tapped: b) == b)
        #expect(GridSelectionRule.single(a, tapped: a) == a)
    }

    @Test func multipleSelectionToggles() {
        var set = Set<GridPosition>()
        set = GridSelectionRule.toggling(set, tapped: a)
        set = GridSelectionRule.toggling(set, tapped: b)
        #expect(set == [a, b])
        set = GridSelectionRule.toggling(set, tapped: a)
        #expect(set == [b])
        set = GridSelectionRule.toggling(set, tapped: b)
        #expect(set.isEmpty)
    }
}
