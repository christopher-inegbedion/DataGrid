# DataGrid

A SwiftUI grid with a **pinned header row and pinned first column** that stays smooth at **100,000+ rows**.

<p align="center"><img src="docs/screenshot.png" width="300" alt="DataGrid scrolled to row 6: the header row and row numbers stay pinned, one cell is selected"></p>

SwiftUI has no lazy table that pins in both directions. `LazyVGrid` only pins section headers, `Grid`
builds every cell up front, and `Table` collapses to one column on iPhone. The usual workaround is two
scroll views kept in sync by hand, which drifts. DataGrid is one scroll view:

- **Lazy.** Only the cells in and just around the viewport exist. A 100,000-row grid builds a screenful of
  cells, not 100,000 rows' worth.
- **Pinned, with no lag.** The header row, the first column and the corner are repositioned with
  `visualEffect` inside the scroll content, in the same render pass as the scroll, instead of following it
  with state a frame late.
- **Index-based.** You say how many rows and columns there are and draw a cell for `(row, column)`. There is
  no array to build, so it suits spreadsheets, schedules, logs and comparison tables.
- **Variable row heights**, one height for every row or one each, still with lazy rendering.
- **Selection**: a single cell, or several (tap toggles each cell in a set).
- **Scroll to a cell** from code, such as a "jump to row" button.
- **Resizable columns** and VoiceOver row and column hints.

Requires iOS 18, macOS 15 or visionOS 2 (it uses `onScrollGeometryChange`).

## Use it

```swift
import DataGrid

struct SalesView: View {
    @State private var widths: [CGFloat] = [130, 110, 110, 110]
    @State private var selection: GridPosition?

    var body: some View {
        DataGrid(rows: 100_000, columnWidths: $widths, selection: $selection) { row, column in
            Text(value(row, column))                     // any view
        } columnHeader: { column in
            Text(titles[column]).bold()
        } rowHeader: { row in
            Text("\(row + 1)").foregroundStyle(.secondary)
        } corner: {
            Image(systemName: "tablecells")
        }
    }
}
```

Fixed columns and no pinned first column is shorter:

```swift
DataGrid(rows: 5_000, columns: 8, columnWidth: 120) { row, column in
    Text("\(row),\(column)")
} columnHeader: { column in
    Text("Column \(column)")
}
```

Add the package in Xcode (**File → Add Package Dependencies**) with
`https://github.com/christopher-inegbedion/DataGrid`, or in `Package.swift`:

```swift
.package(url: "https://github.com/christopher-inegbedion/DataGrid", from: "0.1.0")
```

Variable row heights, several selected cells, and jumping to a row:

```swift
@State private var selection = Set<GridPosition>()
@State private var scrollTo: GridScrollRequest?

DataGrid(rows: heights.count, columnWidths: $widths, rowHeights: .variable(heights),
         selection: $selection, scrollTo: $scrollTo) { row, column in
    Text(value(row, column))
} columnHeader: { column in
    Text(titles[column]).bold()
} rowHeader: { row in
    Text("\(row + 1)")
} corner: {
    EmptyView()
}

Button("Jump to row 5,000") { scrollTo = GridScrollRequest(row: 4_999) }
```

### Options

| | |
|---|---|
| `rows` | Number of body rows |
| `columnWidths` | A `Binding<[CGFloat]>`, one width per column. Dragging a header's trailing edge changes it |
| `rowHeights` | `40` (every row) or `.variable([CGFloat])`. With fewer heights than rows, the last repeats |
| `headerHeight` | Height of the pinned header row (default 40) |
| `rowHeaderWidth` | Width of the pinned first column; `0` for none (default 56) |
| `minimumColumnWidth` | Narrowest a column can be dragged to (default 48) |
| `selection` | `Binding<GridPosition?>` (tap selects one cell) or `Binding<Set<GridPosition>>` (tap toggles a cell) |
| `scrollTo` | `Binding<GridScrollRequest?>`: set a `row` and/or `column` to scroll it just inside the pinned header and column; the grid resets it to `nil` |

## How it works

`GridGeometry` holds the layout maths and has no SwiftUI in it. With equal row heights a row's position is a
multiplication and the visible rows are a division. Variable heights and column widths keep a running total
(built once, reused until the sizes change) and are searched by binary search. `onScrollGeometryChange` maps the scroll
position to the set of visible rows and columns, and only fires when that set changes, so the view updates a
few times a second while scrolling, not once per frame.

## Tested

- Layout maths: 21 unit tests (`swift test`): boundaries, overscroll, empty grids, zero-width columns, variable
  heights (including 100,000 rows) and the selection rules.
- The real view on an iOS simulator, with a 100,000-row grid: header, row header and corner stay put by pixel
  colour at the top, in the middle and at the bottom; only a screenful of cells is built, also with variable heights;
  the last row and column are reachable.
- Scroll-to-cell on the simulator: both axes, one axis at a time (the other keeps its place), repeating the same
  request after scrolling away, and out-of-range requests (clamped).

Not covered by automated tests: column resizing by drag, the tap gesture itself (the selection rules are unit-tested),
VoiceOver behaviour, and macOS and visionOS appearance (they build on macOS; visionOS was not built).

## Limits

- No sorting, editing, range or drag selection, or drag-and-drop.
- Only rows near the viewport exist, so VoiceOver reads those rather than the whole table.
- The grid is read-only data display; it does not own your data.

## Contributing

Issues and pull requests welcome. Run `swift test` and the simulator tests before sending one.

MIT licensed.
