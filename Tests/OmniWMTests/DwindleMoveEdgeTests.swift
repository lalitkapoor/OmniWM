// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

/// Move Edge on the layout under test (screen 1600x900): `L` fills the left half; the right half has `T` on top and a
/// row of `A`, `B` and `C` below it. `B` was grouped into `A` and extracted again, so `B` and `A`
/// share `A`'s former slot: extracting right gives `A | B | C`, extracting left gives `B | A | C`.
final class DwindleMoveEdgeTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    // MARK: - Shared engine behavior (equal shares, minimum sizes)

    func testMoveEdgeRightTakesEquallyFromEveryWindowToTheRight() throws {
        let fixture = try makeFixture(extract: .left, aMinWidth: 1)
        let before = frames(fixture)
        XCTAssertLessThan(before.b.maxX, before.a.minX, "B sits left of A")

        XCTAssertTrue(fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        let aGave = before.a.width - after.a.width
        let cGave = before.c.width - after.c.width
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(aGave, 20)
        XCTAssertEqual(aGave, cGave, accuracy: 1)
        XCTAssertEqual(after.b.width - before.b.width, aGave + cGave, accuracy: 1)
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
        XCTAssertEqual(after.l, before.l)
    }

    func testMoveEdgeRightSkipsWindowsAtTheirMinimum() throws {
        let fixture = try makeFixture(extract: .left)
        let before = frames(fixture)
        XCTAssertEqual(before.a.width, Self.aMinWidth, accuracy: 1)

        XCTAssertTrue(fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertEqual(after.a.width, before.a.width, accuracy: 1)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
    }

    func testMoveEdgeRightStopsWhenEverythingToTheRightIsAtItsMinimum() throws {
        let fixture = try makeFixture(extract: .right, aMinWidth: 150)
        let start = frames(fixture)
        var steps = 0
        while fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws), steps < 50 {
            let current = frames(fixture)
            XCTAssertEqual(current.a, start.a, "step \(steps)")
            XCTAssertEqual(current.l, start.l, "step \(steps)")
            steps += 1
        }

        XCTAssertGreaterThan(steps, 0)
        XCTAssertLessThan(steps, 50)
        let final = frames(fixture)
        XCTAssertEqual(final.c.width, Self.cMinWidth, accuracy: 1)
        XCTAssertEqual(final.a, start.a)
        XCTAssertEqual(final.l, start.l)
    }

    func testMoveEdgeLeftGivesSpaceEquallyToEveryWindowToTheRight() throws {
        let fixture = try makeFixture(extract: .left, aMinWidth: 1)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.moveEdge(.left, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        let aGained = after.a.width - before.a.width
        let cGained = after.c.width - before.c.width
        XCTAssertEqual(after.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(aGained, 10)
        XCTAssertEqual(aGained, cGained, accuracy: 1)
        XCTAssertEqual(before.b.width - after.b.width, aGained + cGained, accuracy: 1)
        XCTAssertEqual(after.l, before.l)
    }

    func testMoveEdgeDoesNothingWhenNothingOnThatSideCanGive() throws {
        let fixture = try makeFixture(extract: .right)
        for token in [fixture.c, fixture.l] {
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

        XCTAssertFalse(fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.b, before.b)
        XCTAssertEqual(after.a, before.a)
        XCTAssertEqual(after.t, before.t)
    }

    // MARK: - Move Edge Left / Right / Up / Down

    func testMoveEdgeRightAndLeftMoveTheRightEdgeWhenThereIsAWindowOnTheRight() throws {
        let fixture = try makeFixture(extract: .right)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws))
        let grown = frames(fixture)
        XCTAssertEqual(grown.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertGreaterThan(grown.b.width, before.b.width + 20)
        XCTAssertLessThan(grown.c.width, before.c.width - 20)
        XCTAssertEqual(grown.a, before.a)
        XCTAssertEqual(grown.l, before.l)

        XCTAssertTrue(fixture.engine.moveEdge(.left, by: 0.1, in: fixture.ws))
        let shrunk = frames(fixture)
        XCTAssertEqual(shrunk.b.minX, before.b.minX, accuracy: 0.5)
        XCTAssertEqual(shrunk.b.width, before.b.width, accuracy: 1)
        XCTAssertEqual(shrunk.c.width, before.c.width, accuracy: 1)
        XCTAssertEqual(shrunk.a, before.a)
        XCTAssertEqual(shrunk.l, before.l)
    }

    func testMoveEdgeLeftGrowsTheRightmostWindowFromItsLeftEdge() throws {
        let fixture = try makeFixture(extract: .right)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.c, in: fixture.ws), in: fixture.ws)
        let before = frames(fixture)
        XCTAssertEqual(before.a.width, Self.aMinWidth, accuracy: 1, "A has nothing to give")

        XCTAssertTrue(fixture.engine.moveEdge(.left, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        let bGave = before.b.width - after.b.width
        let lGave = before.l.width - after.l.width
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5, "the right edge stays at the screen edge")
        XCTAssertGreaterThan(bGave, 10)
        XCTAssertEqual(bGave, lGave, accuracy: 1)
        XCTAssertEqual(after.c.width - before.c.width, bGave + lGave, accuracy: 1)
        XCTAssertEqual(after.a.width, before.a.width, accuracy: 1)
    }

    func testMoveEdgeRightShrinksTheRightmostWindowGivingEquallyToTheLeft() throws {
        let fixture = try makeFixture(extract: .right, aMinWidth: 1)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.c, in: fixture.ws), in: fixture.ws)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.moveEdge(.right, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        let gains = [after.a.width - before.a.width, after.b.width - before.b.width, after.l.width - before.l.width]
        XCTAssertEqual(after.c.maxX, before.c.maxX, accuracy: 0.5)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
        for gain in gains {
            XCTAssertEqual(gain, gains[0], accuracy: 1)
            XCTAssertGreaterThan(gain, 5)
        }
    }

    func testMoveEdgeDownAndUpMoveTheBottomEdgeWhenThereIsAWindowBelow() throws {
        let fixture = try makeFixture(extract: .right)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.t, in: fixture.ws), in: fixture.ws)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.moveEdge(.down, by: 0.1, in: fixture.ws))
        let grown = frames(fixture)
        XCTAssertEqual(grown.t.maxY, before.t.maxY, accuracy: 0.5, "T's top edge stays put")
        XCTAssertGreaterThan(grown.t.height, before.t.height + 20)
        XCTAssertLessThan(grown.b.height, before.b.height - 20)

        XCTAssertTrue(fixture.engine.moveEdge(.up, by: 0.1, in: fixture.ws))
        XCTAssertEqual(frames(fixture).t.height, before.t.height, accuracy: 1)
        XCTAssertEqual(frames(fixture).l, before.l)
    }

    func testMoveEdgeUpGrowsTheBottomRowFromItsTopEdge() throws {
        let fixture = try makeFixture(extract: .right)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.moveEdge(.up, by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertEqual(after.b.minY, before.b.minY, accuracy: 0.5, "the row's bottom edge stays at the screen edge")
        XCTAssertGreaterThan(after.b.height, before.b.height + 20)
        XCTAssertLessThan(after.t.height, before.t.height - 20)
        XCTAssertEqual(after.l, before.l)
    }

    func testMoveEdgeDoesNothingWithoutANeighborOnThatAxis() throws {
        let engine = DwindleLayoutEngine()
        let ws = WorkspaceDescriptor.ID()
        let only = WindowToken(pid: 1, windowId: 1)
        _ = engine.addWindow(token: only, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        engine.setSelectedNode(engine.findNode(for: only, in: ws), in: ws)

        for direction in [Direction.left, .right, .up, .down] {
            XCTAssertFalse(engine.moveEdge(direction, by: 0.1, in: ws), direction.rawValue)
        }

        let fixture = try makeFixture(extract: .right)
        fixture.engine.setSelectedNode(fixture.engine.findNode(for: fixture.l, in: fixture.ws), in: fixture.ws)
        XCTAssertFalse(fixture.engine.moveEdge(.up, by: 0.1, in: fixture.ws), "L spans the full height")
        XCTAssertFalse(fixture.engine.moveEdge(.down, by: 0.1, in: fixture.ws), "L spans the full height")
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
