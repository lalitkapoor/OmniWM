// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class DwindleNavigationReadingOrderTests: XCTestCase {
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

    func testTopmostWinsEvenWhenLowerTileIsLarger() throws {
        let (engine, ws, full, stacked) = makeLayout(full: .left)
        let top = try topmost(of: stacked, engine: engine, ws: ws)
        let bottom = try XCTUnwrap(stacked.first { $0 != top })
        let split = try XCTUnwrap(engine.findNode(for: top, in: ws)?.parent)
        // The first child of a vertical split is the lower tile; a ratio above 1 enlarges it.
        XCTAssertEqual(split.firstChild()?.windowToken, bottom)
        split.kind = .split(orientation: .vertical, ratio: 1.4)
        let frames = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertGreaterThan(try XCTUnwrap(frames[bottom]).height, try XCTUnwrap(frames[top]).height)

        XCTAssertEqual(engine.findGeometricNeighbor(from: full, direction: .right, in: ws), top)
    }

    func testLeftmostWinsEvenWhenRightTileIsLarger() throws {
        let (engine, ws, full, sideBySide) = makeLayout(full: .up)
        let left = try leftmost(of: sideBySide, engine: engine, ws: ws)
        let right = try XCTUnwrap(sideBySide.first { $0 != left })
        let split = try XCTUnwrap(engine.findNode(for: left, in: ws)?.parent)
        XCTAssertEqual(split.firstChild()?.windowToken, left)
        split.kind = .split(orientation: .horizontal, ratio: 0.6)
        let frames = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertGreaterThan(try XCTUnwrap(frames[right]).width, try XCTUnwrap(frames[left]).width)

        XCTAssertEqual(engine.findGeometricNeighbor(from: full, direction: .down, in: ws), left)
    }

    func testOnlyTilesBesideTheCurrentWindowAreConsidered() throws {
        let (engine, ws, columns) = makeTwoStackedColumns()
        let leftSplit = try XCTUnwrap(engine.findNode(for: columns.leftTop, in: ws)?.parent)
        let rightSplit = try XCTUnwrap(engine.findNode(for: columns.rightTop, in: ws)?.parent)

        // Left column: bottom 0...540, top 540...900. Right column split evenly at 450.
        leftSplit.kind = .split(orientation: .vertical, ratio: 1.2)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertEqual(
            engine.findGeometricNeighbor(from: columns.rightBottom, direction: .left, in: ws),
            columns.leftBottom
        )
        XCTAssertEqual(
            engine.findGeometricNeighbor(from: columns.rightTop, direction: .left, in: ws),
            columns.leftTop
        )

        // Left column: bottom 0...270, top 270...900. Both left tiles sit beside the lower right tile.
        leftSplit.kind = .split(orientation: .vertical, ratio: 0.6)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertEqual(
            engine.findGeometricNeighbor(from: columns.rightBottom, direction: .left, in: ws),
            columns.leftTop
        )
        XCTAssertEqual(rightSplit.splitRatio, 1.0)
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

    /// Two columns, each split into an upper and a lower tile.
    private func makeTwoStackedColumns() -> (
        DwindleLayoutEngine,
        WorkspaceDescriptor.ID,
        (leftTop: WindowToken, leftBottom: WindowToken, rightTop: WindowToken, rightBottom: WindowToken)
    ) {
        let engine = DwindleLayoutEngine()
        let ws = WorkspaceDescriptor.ID()
        let leftTop = WindowToken(pid: 1, windowId: 1)
        let rightTop = WindowToken(pid: 2, windowId: 2)
        let rightBottom = WindowToken(pid: 3, windowId: 3)
        let leftBottom = WindowToken(pid: 4, windowId: 4)

        _ = engine.addWindow(token: leftTop, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.setPreselection(.right, in: ws))
        _ = engine.addWindow(token: rightTop, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertTrue(engine.setPreselection(.down, in: ws))
        _ = engine.addWindow(token: rightBottom, to: ws, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: ws, screen: screen)
        engine.setSelectedNode(engine.findNode(for: leftTop, in: ws), in: ws)
        XCTAssertTrue(engine.setPreselection(.down, in: ws))
        _ = engine.addWindow(token: leftBottom, to: ws, activeWindowFrame: nil)
        let frames = engine.calculateLayout(for: ws, screen: screen)
        XCTAssertGreaterThan(frames[leftTop]?.minY ?? 0, frames[leftBottom]?.minY ?? 0)
        XCTAssertGreaterThan(frames[rightTop]?.minY ?? 0, frames[rightBottom]?.minY ?? 0)
        XCTAssertLessThan(frames[leftTop]?.minX ?? 0, frames[rightTop]?.minX ?? 0)
        return (engine, ws, (leftTop, leftBottom, rightTop, rightBottom))
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
