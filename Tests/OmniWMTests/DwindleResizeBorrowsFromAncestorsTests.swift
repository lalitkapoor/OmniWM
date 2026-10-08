// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

/// Layout under test (screen 1600x900): `L` fills the left half; the right half has `T` on one row and
/// `B | A | C` on the other. `B` was grouped into `A` and extracted to the left, so `B` and `A` share
/// `A`'s former slot. `A` has a large minimum width, which pins the `B | A` split.
final class DwindleResizeBorrowsFromAncestorsTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    func testGrowingPinnedWindowBorrowsFromOuterSplitAndKeepsSiblingSize() throws {
        let fixture = try makePinnedFixture()
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertEqual(after.a.width, before.a.width, accuracy: 1)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
        XCTAssertEqual(after.b.width - before.b.width, before.c.width - after.c.width, accuracy: 1)
        XCTAssertEqual(after.l, before.l)
        XCTAssertEqual(after.t, before.t)
    }

    func testGrowHorizontallyBorrowsFromOuterSplitAndKeepsSiblingSize() throws {
        let fixture = try makePinnedFixture()
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeSelected(by: 0.1, orientation: .horizontal, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertGreaterThan(after.b.width, before.b.width + 20)
        XCTAssertEqual(after.a.width, before.a.width, accuracy: 1)
        XCTAssertLessThan(after.c.width, before.c.width - 20)
    }

    func testRepeatedGrowKeepsBorrowingUntilEveryNeighborIsAtItsMinimum() throws {
        let fixture = try makePinnedFixture()
        var previous = frames(fixture).b.width
        var steps = 0
        while fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws), steps < 50 {
            let width = frames(fixture).b.width
            XCTAssertGreaterThan(width, previous, "step \(steps)")
            previous = width
            steps += 1
        }

        XCTAssertGreaterThan(steps, 1)
        XCTAssertLessThan(steps, 50)
        let final = frames(fixture)
        XCTAssertGreaterThanOrEqual(final.a.width, Self.aMinWidth - 1)
        XCTAssertGreaterThanOrEqual(final.c.width, Self.cMinWidth - 1)
        XCTAssertEqual(final.l, frames(fixture).l)
    }

    func testShrinkStillUsesNearestSplit() throws {
        let fixture = try makePinnedFixture()
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: -0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertLessThan(after.b.width, before.b.width)
        XCTAssertGreaterThan(after.a.width, before.a.width)
        XCTAssertEqual(after.c, before.c)
    }

    func testGrowNeverSwitchesAxis() throws {
        let fixture = try makePinnedFixture()
        // Pin the outer row split as well, so no horizontal split anywhere can give B more width.
        fixture.engine.updateWindowConstraints(
            for: fixture.c,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 2000, height: 1), maxSize: .zero, isFixed: false)
        )
        fixture.engine.updateWindowConstraints(
            for: fixture.l,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 2000, height: 1), maxSize: .zero, isFixed: false)
        )
        let before = frames(fixture)

        XCTAssertFalse(fixture.engine.resizeSelected(by: 0.1, orientation: .horizontal, in: fixture.ws))
        XCTAssertFalse(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        XCTAssertEqual(frames(fixture).b, before.b)
        XCTAssertEqual(frames(fixture).t, before.t)
    }

    func testUnpinnedGrowStillOnlyUsesNearestSplit() throws {
        let fixture = try makePinnedFixture(aMinWidth: 1)
        let before = frames(fixture)

        XCTAssertTrue(fixture.engine.resizeFocusedWindow(by: 0.1, in: fixture.ws))

        let after = frames(fixture)
        XCTAssertGreaterThan(after.b.width, before.b.width)
        XCTAssertLessThan(after.a.width, before.a.width)
        XCTAssertEqual(after.c, before.c)
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

    private func makePinnedFixture(aMinWidth: CGFloat = aMinWidth) throws -> Fixture {
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
        engine.setSelectedNode(engine.findNode(for: b, in: ws), in: ws)
        XCTAssertTrue(engine.groupWindow(b, into: a, in: ws))
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.ungroupWindow(b, direction: .left, in: ws))
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
        XCTAssertLessThan(initial.b.maxX, initial.a.minX, "B sits left of A")
        XCTAssertLessThan(initial.a.maxX, initial.c.minX, "A sits left of C")
        if aMinWidth > 1 {
            XCTAssertEqual(initial.a.width, aMinWidth, accuracy: 1, "A is pinned at its minimum width")
        }
        return fixture
    }
}
