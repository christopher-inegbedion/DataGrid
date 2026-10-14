#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import DataGrid

/// Runs the real view in a window on the simulator, scrolls it, and checks what is on screen by
/// the colour of pixels: header red, row header blue, corner green, body cells white.
@MainActor
final class HostedGridTests: XCTestCase {
    final class Probe: @unchecked Sendable {
        var built = Set<GridPosition>()
        var requestScroll: ((GridScrollRequest) -> Void)?
    }

    /// A grid whose scroll request can be set from the test, as an app's button would.
    struct ScrollHost: View {
        let probe: Probe
        let rows: Int
        let heights: RowHeights
        @State private var request: GridScrollRequest?

        var body: some View {
            DataGrid(rows: rows, columnWidths: .constant(Array(repeating: 100, count: 40)),
                     rowHeights: heights, scrollTo: $request) { r, c in
                Color.white.overlay(Text("\(r),\(c)").font(.caption))
                    .onAppear { probe.built.insert(GridPosition(row: r, column: c)) }
            } columnHeader: { _ in
                Color.red
            } rowHeader: { _ in
                Color.blue
            } corner: {
                Color.blue
            }
            .onAppear { probe.requestScroll = { request = $0 } }
        }
    }

    private func host(rows: Int, heights: RowHeights = 40, probe: Probe) -> UIWindow {
        let controller = UIHostingController(rootView: ScrollHost(probe: probe, rows: rows, heights: heights)
            .environment(\.colorScheme, .light))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle()
        return window
    }

    private let size = CGSize(width: 390, height: 700)

    private func makeWindow(rows: Int, probe: Probe, corner: Color = .blue) -> UIWindow {
        let grid = DataGrid(rows: rows, columnWidths: .constant(Array(repeating: 100, count: 40))) { r, c in
            Color.white.overlay(Text("\(r),\(c)").font(.caption))
                .onAppear { probe.built.insert(GridPosition(row: r, column: c)) }
        } columnHeader: { _ in
            Color.red
        } rowHeader: { _ in
            Color.blue
        } corner: {
            corner
        }
        let controller = UIHostingController(rootView: grid.environment(\.colorScheme, .light))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle()
        return window
    }

    private func settle(_ seconds: TimeInterval = 0.6) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let s = view as? UIScrollView { return s }
        for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
        return nil
    }

    private func capture(_ window: UIWindow, format: UIGraphicsImageRendererFormat) -> UIImage {
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            window.layer.render(in: ctx.cgContext)
        }
    }

    private enum Paint { case red, blue, white, other }

    /// The colour of the pixel at a point (in points), read from a capture of the window.
    private func paint(of window: UIWindow) -> (CGPoint) -> Paint {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let cg = capture(window, format: format).cgImage!
        let data = cg.dataProvider!.data! as Data
        let bgra = cg.byteOrderInfo == .order32Little
        return { p in
            let i = Int(p.y) * cg.bytesPerRow + Int(p.x) * 4
            let (r, b) = bgra ? (Int(data[i + 2]), Int(data[i])) : (Int(data[i]), Int(data[i + 2]))
            let g = Int(data[i + 1])
            if r > 235, g > 235, b > 235 { return .white }
            if r > 200, g < 110, b < 110 { return .red }      // Color.red
            if b > 200, r < 80, g < 170 { return .blue }      // Color.blue
            return .other
        }
    }

    func testPinnedHeaderAndColumnStayPutWhileScrolling() throws {
        let probe = Probe()
        let window = makeWindow(rows: 100_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        // The header pins at the top of the safe area, like any sticky header
        let top = window.safeAreaInsets.top

        let offsets: [CGPoint] = [.zero, CGPoint(x: 700, y: 123_456), CGPoint(x: 1_500, y: 3_999_000)]
        for target in offsets {
            scroll.setContentOffset(target, animated: false)
            settle()
            let at = paint(of: window)
            XCTAssertEqual(at(CGPoint(x: 250, y: top + 20)), .red, "header not pinned at \(target)")
            XCTAssertEqual(at(CGPoint(x: 28, y: top + 300)), .blue, "row header not pinned at \(target)")
            XCTAssertEqual(at(CGPoint(x: 330, y: top + 400)), .white, "body cells missing at \(target)")
        }
    }

    func testTheCornerStaysInTheCorner() throws {
        let probe = Probe()
        let window = makeWindow(rows: 1_000, probe: probe, corner: Color.red)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let top = window.safeAreaInsets.top
        scroll.setContentOffset(CGPoint(x: 800, y: 20_000), animated: false)
        settle()
        XCTAssertEqual(paint(of: window)(CGPoint(x: 28, y: top + 20)), .red, "corner moved")
    }

    func testOnlyAScreenfulOfCellsExistInAHundredThousandRowGrid() throws {
        let probe = Probe()
        let window = makeWindow(rows: 100_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        scroll.setContentOffset(CGPoint(x: 0, y: 2_000_000), animated: false)
        settle()
        XCTAssertTrue(probe.built.contains { $0.row >= 49_990 && $0.row <= 50_010 }, "the rows at the offset should exist")
        // far fewer than 100,000 x 40 cells were ever built, even counting every window passed through
        XCTAssertLessThan(probe.built.count, 2_000, "built \(probe.built.count) cells")
        XCTAssertFalse(probe.built.contains { $0.row == 99_999 })
    }

    func testTheLastRowAndColumnAreReachable() throws {
        let probe = Probe()
        let window = makeWindow(rows: 500, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let maxOffset = CGPoint(x: scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right,
                                y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(maxOffset, animated: false)
        settle()
        XCTAssertTrue(probe.built.contains(GridPosition(row: 499, column: 39)), "the bottom-right cell should be built")
    }

    // MARK: v0.2

    func testVariableRowHeightsPinAndVirtualize() throws {
        let probe = Probe()
        let heights = (0..<100_000).map { CGFloat(30 + $0 % 3 * 20) }
        let window = host(rows: 100_000, heights: .variable(heights), probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let geometry = GridGeometry(rowCount: 100_000, rowHeights: .variable(heights), columnWidths: [100])
        let y: CGFloat = 1_000_000
        scroll.setContentOffset(CGPoint(x: 250, y: y), animated: false)
        settle()
        let expected = try XCTUnwrap(geometry.row(atY: y))
        XCTAssertTrue(probe.built.contains { abs($0.row - expected) <= 12 }, "rows near \(expected) should exist")
        XCTAssertLessThan(probe.built.count, 2_000)
        let top = window.safeAreaInsets.top
        let at = paint(of: window)
        XCTAssertEqual(at(CGPoint(x: 250, y: top + 20)), .red)
        XCTAssertEqual(at(CGPoint(x: 28, y: top + 300)), .blue)
        XCTAssertEqual(scroll.contentSize.height, 40 + geometry.contentHeight, accuracy: 1)
    }

    func testScrollToACell() throws {
        let probe = Probe()
        let window = host(rows: 100_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let inset = scroll.adjustedContentInset

        probe.requestScroll?(GridScrollRequest(row: 50_000, column: 20))
        settle()
        XCTAssertEqual(scroll.contentOffset.x + inset.left, 20 * 100, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.y + inset.top, 50_000 * 40, accuracy: 1)
        XCTAssertTrue(probe.built.contains(GridPosition(row: 50_000, column: 20)))
    }

    func testScrollingOneAxisKeepsTheOther() throws {
        let probe = Probe()
        let window = host(rows: 100_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let inset = scroll.adjustedContentInset
        probe.requestScroll?(GridScrollRequest(row: 1_000, column: 10))
        settle()
        probe.requestScroll?(GridScrollRequest(row: 2_000))
        settle()
        XCTAssertEqual(scroll.contentOffset.x + inset.left, 1_000, accuracy: 1, "column should not move")
        XCTAssertEqual(scroll.contentOffset.y + inset.top, 80_000, accuracy: 1)
        probe.requestScroll?(GridScrollRequest(column: 25))
        settle()
        XCTAssertEqual(scroll.contentOffset.x + inset.left, 2_500, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.y + inset.top, 80_000, accuracy: 1, "row should not move")
    }

    func testTheSameRequestWorksAgainAfterScrollingAway() throws {
        let probe = Probe()
        let window = host(rows: 100_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        let inset = scroll.adjustedContentInset
        probe.requestScroll?(GridScrollRequest(row: 500))
        settle()
        scroll.setContentOffset(CGPoint(x: 0, y: 9_000_000 - inset.top), animated: false)
        settle()
        probe.requestScroll?(GridScrollRequest(row: 500))
        settle()
        XCTAssertEqual(scroll.contentOffset.y + inset.top, 20_000, accuracy: 1)
    }

    func testOutOfRangeRequestsClampInsteadOfCrashing() throws {
        let probe = Probe()
        let window = host(rows: 1_000, probe: probe)
        let scroll = try XCTUnwrap(scrollView(in: window))
        probe.requestScroll?(GridScrollRequest(row: 10_000_000, column: 9_999))
        settle()
        XCTAssertTrue(probe.built.contains(GridPosition(row: 999, column: 39)), "the last cell should be reachable")
        XCTAssertLessThanOrEqual(scroll.contentOffset.y, scroll.contentSize.height)
        probe.requestScroll?(GridScrollRequest(row: -5, column: -5))
        settle()
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 0, accuracy: 1)
    }

    /// Writes docs/screenshot.png when SNAPSHOT_DIR is set (used for the README); otherwise a no-op.
    func testReadmeScreenshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let names = ["Alice", "Bruno", "Chen", "Dalia", "Eli", "Farah", "Gus", "Hana"]
        let grid = DataGrid(rows: 100_000, columnWidths: .constant([130, 110, 110, 110, 110, 110, 110, 110, 110, 110]),
                            selection: .constant(GridPosition(row: 9, column: 2))) { r, c in
            Text(c == 0 ? names[r % names.count] : "\(((r + 1) * (c + 3) * 37) % 1000)")
                .font(.system(.body, design: .rounded)).monospacedDigit()
        } columnHeader: { c in
            Text(c == 0 ? "Name" : "Q\(c)").font(.subheadline.bold())
        } rowHeader: { r in
            Text("\(r + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        } corner: {
            Image(systemName: "tablecells").foregroundStyle(.secondary)
        }
        let window = UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        let screen = VStack(spacing: 0) {
            Text("Quarterly sales").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                .padding(.top, 54).background(Color(white: 0.97))
            Divider()
            grid
        }
        .ignoresSafeArea(edges: .top)
        window.rootViewController = UIHostingController(rootView: screen.environment(\.colorScheme, .light))
        window.makeKeyAndVisible()
        settle()
        let scroll = try XCTUnwrap(scrollView(in: window))
        scroll.setContentOffset(CGPoint(x: 0, y: 40 * 5), animated: false)
        settle()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        try capture(window, format: format).pngData()!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screenshot.png"))
    }
}
#endif
