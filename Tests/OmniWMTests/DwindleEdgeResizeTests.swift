// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

/// Layout under test (screen 1600x900): `L` fills the left half; the right half has `T` on top and a
/// row of `A`, `B` and `C` below it. `B` was grouped into `A` and extracted again, so `B` and `A`
/// share `A`'s former slot: extracting right gives `A | B | C`, extracting left gives `B | A | C`.
final class DwindleEdgeResizeTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    // MARK: - Growing pushes the right edge

    func testGrowTakesFromTheRightAndLeavesTheLeftAlone() throws {
        let fixture = try makeFixture(extract: .right)
        let before = frames(fixture)
        XCTAssertLessThan(before.a.maxX, before.b.minX, "A sits left of B")

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.a, before.a)
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertEqual(after.b.width - before.b.width, before.c.width - after.c.width, accuracy: 1)
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
        XCTAssertEqual(after.l, before.l)
        XCTAssertEqual(after.t, before.t)
    }

    func testGrowHorizontallyMatchesGrowFocusedWindow() throws {
        let fixture = try makeFixture(extract: .right)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeSelected(by: 0.1, orientation: .horizontal, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.a, before.a)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
    }

    func testGrowTakesFromNearestRightNeighborFirst() throws {
        let fixture = try makeFixture(extract: .left, aMinWidth: 1)
        let before = frames(fixture)
        XCTAssertLessThan(before.b.maxX, before.a.minX, "B sits left of A")

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertLessThan(after.a.width, before.a.width - 20)
        XCTAssertEqual(after.c, before.c)
    }

    func testGrowSkipsNeighborAtItsMinimumAndTakesFromTheNextOne() throws {
        let fixture = try makeFixture(extract: .left)
        let before = frames(fixture)
        XCTAssertEqual(before.a.width, Self.aMinWidth, accuracy: 1)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertEqual(after.a.width, before.a.width, accuracy: 1)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
    }

    func testGrowFallsBackToTheLeftOnlyWhenTheRightHasNothingLeft() throws {
        let aMinWidth: CGFloat = 150
        let fixture = try makeFixture(extract: .right, aMinWidth: aMinWidth)
        var previous = frames(fixture)
        XCTAssertGreaterThan(previous.a.width, aMinWidth + 20, "A starts with room to give")
        var changedWindows: [String] = []
        var steps = 0
        while fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws), steps < 50 {
            let current = frames(fixture)
            XCTAssertGreaterThan(current.b.width, previous.b.width, "step \(steps)")
            if abs(current.a.width - previous.a.width) > 0.5 {
                XCTAssertEqual(current.c.width, Self.cMinWidth, accuracy: 1, "A gives only once C is at its minimum")
                changedWindows.append("A")
            }
            if abs(current.l.width - previous.l.width) > 0.5 {
                XCTAssertEqual(current.a.width, aMinWidth, accuracy: 1, "L gives only once A is at its minimum")
                changedWindows.append("L")
            }
            if abs(current.c.width - previous.c.width) > 0.5 {
                XCTAssertFalse(changedWindows.contains("A") || changedWindows.contains("L"), "C gives first")
                changedWindows.append("C")
            }
            previous = current
            steps += 1
        }

        XCTAssertLessThan(steps, 50)
        XCTAssertEqual(changedWindows.first, "C")
        XCTAssertTrue(changedWindows.contains("A"))
        XCTAssertTrue(changedWindows.contains("L"))
        XCTAssertEqual(previous.c.width, Self.cMinWidth, accuracy: 1)
        XCTAssertEqual(previous.a.width, aMinWidth, accuracy: 1)
    }

    // MARK: - Shrinking pulls the right edge in

    func testShrinkGivesSpaceToTheRightAndLeavesTheLeftAlone() throws {
        let fixture = try makeFixture(extract: .right)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: -0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.a, before.a)
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertLessThan(after.b.width, before.b.width)
        XCTAssertEqual(before.b.width - after.b.width, after.c.width - before.c.width, accuracy: 1)
    }

    // MARK: - Fallbacks and other axes

    func testRightmostWindowGrowsLeftTakingFromNearestNeighborFirst() throws {
        let fixture = try makeFixture(extract: .right)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.c, in: fixture.ws), in: fixture.ws)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(after.c.width, before.c.width + 20)
        XCTAssertLessThan(after.b.width, before.b.width - 20)
        XCTAssertEqual(after.a, before.a)
    }

    func testHeightGrowPushesTheBottomEdgeFirst() throws {
        let fixture = try makeFixture(extract: .right)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.t, in: fixture.ws), in: fixture.ws)
        let before = frames(fixture)
        XCTAssertGreaterThan(before.t.minY, before.b.maxY, "T sits above the row (layout y grows upward)")

        XCTAssertTrue(fixture.engine.resizeSelected(by: 0.1, orientation: .vertical, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.t.maxY, before.t.maxY, accuracy: 0.5, "T's top edge stays put")
        XCTAssertGreaterThan(after.t.height, before.t.height + 20)
        for (name, row) in [("A", (before.a, after.a)), ("B", (before.b, after.b)), ("C", (before.c, after.c))] {
            XCTAssertLessThan(row.1.height, row.0.height - 20, name)
            XCTAssertEqual(row.1.width, row.0.width, accuracy: 0.5, name)
        }
        XCTAssertEqual(after.l, before.l)
    }

    func testGrowNeverSwitchesAxis() throws {
        let fixture = try makeFixture(extract: .right)
        for token in [fixture.a, fixture.c, fixture.l] {
            fixture.engine.updateWindowConstraints(
                for: token,
                constraints: WindowSizeConstraints(
                    minSize: CGSize(width: 2000, height: 1),
                    maxSize: .zero,
                    isFixed: false
                )
            )
        }
        let before = frames(fixture)

        XCTAssertFalse(fixture.engine.resizeSelected(by: 0.1, orientation: .horizontal, in: fixture.ws))
        XCTAssertFalse(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        XCTAssertEqual(frames(fixture).b, before.b)
        XCTAssertEqual(frames(fixture).t, before.t)
    }

    // MARK: - Fixture

    private static let aMinWidth: CGFloat = 260
    private static let cMinWidth: CGFloat = 120

    private struct Fixture {
        let engine: DwindleLayoutEngine
        let ws: WorkspaceDescriptor.ID
        let l: WindowToken
        let t: WindowToken
        let a: WindowToken
        let b: WindowToken
        let c: WindowToken
    }

    private struct Frames {
        let l: CGRect
        let t: CGRect
        let a: CGRect
        let b: CGRect
        let c: CGRect
    }

    private func frames(_ fixture: Fixture) -> Frames {
        let all = fixture.engine.calculateLayout(for: fixture.ws, screen: screen)
        return Frames(
            l: all[fixture.l] ?? .null,
            t: all[fixture.t] ?? .null,
            a: all[fixture.a] ?? .null,
            b: all[fixture.b] ?? .null,
            c: all[fixture.c] ?? .null
        )
    }

    private func makeFixture(extract: Direction, aMinWidth: CGFloat = aMinWidth) throws -> Fixture {
        let engine = DwindleLayoutEngine()
        let ws = WorkspaceDescriptor.ID()
        let l = WindowToken(pid: 1, windowId: 1)
        let t = WindowToken(pid: 2, windowId: 2)
        let a = WindowToken(pid: 3, windowId: 3)
        let b = WindowToken(pid: 4, windowId: 4)
        let c = WindowToken(pid: 5, windowId: 5)

        _ = engine.addWindow(token: l, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        for (token, direction) in [(t, Direction.right), (a, .down), (b, .right), (c, .right)] {
            XCTAssertTrue(engine.setPreselection(direction, in: ws))
            _ = engine.addWindow(token: token, to: ws, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: ws, screen: screen)
        }
        XCTAssertTrue(engine.groupWindow(b, into: a, in: ws))
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.ungroupWindow(b, direction: extract, in: ws))
        engine.updateWindowConstraints(
            for: a,
            constraints: WindowSizeConstraints(
                minSize: CGSize(width: aMinWidth, height: 1),
                maxSize: .zero,
                isFixed: false
            )
        )
        engine.updateWindowConstraints(
            for: c,
            constraints: WindowSizeConstraints(
                minSize: CGSize(width: Self.cMinWidth, height: 1),
                maxSize: .zero,
                isFixed: false
            )
        )
        engine.setSelectedNode(engine.findNode(for: b, in: ws), in: ws)

        let fixture = Fixture(engine: engine, ws: ws, l: l, t: t, a: a, b: b, c: c)
        let initial = frames(fixture)
        XCTAssertLessThan(max(initial.a.maxX, initial.b.maxX), initial.c.minX, "C is the rightmost window")
        if aMinWidth == Self.aMinWidth {
            XCTAssertEqual(initial.a.width, aMinWidth, accuracy: 1, "A is at its minimum width")
        }
        return fixture
    }
}
