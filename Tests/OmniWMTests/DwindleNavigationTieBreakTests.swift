// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleNavigationTieBreakTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)

    func testHorizontalFocusIntoEvenlyStackedTilesPrefersTop() throws {
        for (fullSide, focusDirection) in [(Direction.left, Direction.right), (.right, .left)] {
            let (engine, ws, full, stacked) = makeLayout(full: fullSide)
            let top = try topmost(of: stacked, engine: engine, ws: ws)

            XCTAssertEqual(
                engine.findGeometricNeighbor(from: full, direction: focusDirection, in: ws),
                top,
                "full window on the \(fullSide.rawValue)"
            )
        }
    }

    func testVerticalFocusIntoEvenlySideBySideTilesPrefersLeft() throws {
        for (fullSide, focusDirection) in [(Direction.up, Direction.down), (.down, .up)] {
            let (engine, ws, full, sideBySide) = makeLayout(full: fullSide)
            let left = try leftmost(of: sideBySide, engine: engine, ws: ws)

            XCTAssertEqual(
                engine.findGeometricNeighbor(from: full, direction: focusDirection, in: ws),
                left,
                "full window on the \(fullSide.rawValue)"
            )
        }
    }

    func testLargerOverlapStillWinsOverTieBreak() throws {
        let (engine, ws, full, stacked) = makeLayout(full: .left)
        let top = try topmost(of: stacked, engine: engine, ws: ws)
        let bottom = try XCTUnwrap(stacked.first { $0 != top })
        let split = try XCTUnwrap(engine.findNode(for: top, in: ws)?.parent)
        // The first child of a vertical split is the lower tile; a ratio above 1 enlarges it.
        XCTAssertEqual(split.firstChild()?.windowToken, bottom)
        split.kind = .split(orientation: .vertical, ratio: 1.4)
        _ = engine.calculateLayout(for: ws, screen: screen)

        XCTAssertEqual(engine.findGeometricNeighbor(from: full, direction: .right, in: ws), bottom)
    }

    func testNearTieWithinOnePointCountsAsTie() throws {
        let (engine, ws, full, stacked) = makeLayout(full: .left)
        let top = try topmost(of: stacked, engine: engine, ws: ws)
        let bottom = try XCTUnwrap(stacked.first { $0 != top })
        let split = try XCTUnwrap(engine.findNode(for: top, in: ws)?.parent)
        // Grow the lower tile by well under one point.
        split.kind = .split(orientation: .vertical, ratio: 1.001)
        let frames = engine.calculateLayout(for: ws, screen: screen)
        let topFrame = try XCTUnwrap(frames[top])
        let bottomFrame = try XCTUnwrap(frames[bottom])
        XCTAssertGreaterThan(bottomFrame.height, topFrame.height)
        XCTAssertLessThanOrEqual(bottomFrame.height - topFrame.height, 1)

        XCTAssertEqual(engine.findGeometricNeighbor(from: full, direction: .right, in: ws), top)
    }

    /// One full-length window on `full`'s side and two evenly split windows filling the opposite side.
    private func makeLayout(full side: Direction) -> (
        DwindleLayoutEngine,
        WorkspaceDescriptor.ID,
        WindowToken,
        [WindowToken]
    ) {
        let engine = DwindleLayoutEngine()
        let ws = WorkspaceDescriptor.ID()
        let full = WindowToken(pid: 1, windowId: 1)
        let first = WindowToken(pid: 2, windowId: 2)
        let second = WindowToken(pid: 3, windowId: 3)
        let opposite: Direction = switch side {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }

        _ = engine.addWindow(token: full, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.setPreselection(opposite, in: ws))
        _ = engine.addWindow(token: first, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.setPreselection(side.dwindleOrientation == .horizontal ? .down : .right, in: ws))
        _ = engine.addWindow(token: second, to: ws, activeWindowFrame: nil)
        let frames = engine.calculateLayout(for: ws, screen: screen)

        let fullFrame = frames[full] ?? .null
        XCTAssertEqual(
            side.dwindleOrientation == .horizontal ? fullFrame.height : fullFrame.width,
            side.dwindleOrientation == .horizontal ? screen.height : screen.width
        )
        let a = frames[first] ?? .null
        let b = frames[second] ?? .null
        XCTAssertEqual(a.size, b.size, "the opposite side must be split evenly")
        return (engine, ws, full, [first, second])
    }

    private func topmost(of tokens: [WindowToken], engine: DwindleLayoutEngine, ws: WorkspaceDescriptor.ID) throws
        -> WindowToken
    {
        let frames = engine.calculateLayout(for: ws, screen: screen)
        return try XCTUnwrap(tokens.max { (frames[$0]?.maxY ?? 0) < (frames[$1]?.maxY ?? 0) })
    }

    private func leftmost(of tokens: [WindowToken], engine: DwindleLayoutEngine, ws: WorkspaceDescriptor.ID) throws
        -> WindowToken
    {
        let frames = engine.calculateLayout(for: ws, screen: screen)
        return try XCTUnwrap(tokens.min { (frames[$0]?.minX ?? 0) < (frames[$1]?.minX ?? 0) })
    }
}
