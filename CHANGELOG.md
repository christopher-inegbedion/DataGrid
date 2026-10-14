# Changelog

## 0.2.0
- Variable row heights: `rowHeights: .variable([...])` (a plain number still means equal heights).
  **Breaking:** the main initializer's `rowHeight:` is now `rowHeights:`; the fixed-column convenience
  initializers keep `rowHeight:`.
- Multi-selection: a `selection:` binding of `Set<GridPosition>` toggles cells on tap.
- Scroll to a cell: `scrollTo:` binding of `GridScrollRequest` (row and/or column).

## 0.1.0
- First release: lazy 2D grid with pinned header row, first column and corner; resizable columns; tap selection.
