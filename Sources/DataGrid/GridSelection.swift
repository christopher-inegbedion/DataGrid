/// How taps change the selection. Pure logic, separate from the view so it can be tested.
enum GridSelectionRule {
    /// Tapping a cell selects it alone; tapping the selected cell again leaves it selected.
    static func single(_ current: GridPosition?, tapped: GridPosition) -> GridPosition? { tapped }

    /// Tapping a cell toggles it in or out of the set.
    static func toggling(_ current: Set<GridPosition>, tapped: GridPosition) -> Set<GridPosition> {
        var next = current
        if !next.insert(tapped).inserted { next.remove(tapped) }
        return next
    }
}
