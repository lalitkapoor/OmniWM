// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
@testable import OmniWM
import XCTest

final class WorkspaceBarReorderResolverTests: XCTestCase {
    private let ids = (0 ..< 4).map { _ in WorkspaceDescriptor.ID() }

    /// Pills "1", "2", "3", "5" side by side, each 40 points wide with an 8-point gap.
    private var horizontal: [WorkspaceBarReorderSlot] {
        zip(ids, ["1", "2", "3", "5"]).enumerated().map { index, pair in
            WorkspaceBarReorderSlot(id: pair.0, name: pair.1, frame: CGRect(x: index * 48, y: 0, width: 40, height: 20))
        }
    }

    private func resolve(_ source: String, x: CGFloat) -> WorkspaceBarReorderResolution? {
        WorkspaceBarReorderResolver.resolve(
            source: source,
            at: CGPoint(x: x, y: 10),
            slots: horizontal,
            vertical: false
        )
    }

    func testDroppingBeforeAnEarlierWorkspaceTakesItsNumber() {
        XCTAssertEqual(resolve("5", x: 5), WorkspaceBarReorderResolution(position: "1", marker: .before(ids[0])))
        XCTAssertEqual(resolve("5", x: 60), WorkspaceBarReorderResolution(position: "2", marker: .before(ids[1])))
    }

    func testDroppingAfterALaterWorkspaceTakesItsNumber() {
        XCTAssertEqual(resolve("1", x: 75), WorkspaceBarReorderResolution(position: "2", marker: .after(ids[1])))
        XCTAssertEqual(resolve("1", x: 400), WorkspaceBarReorderResolution(position: "5", marker: .after(ids[3])))
    }

    func testDroppingNextToItselfIsNoMove() {
        XCTAssertNil(resolve("2", x: 50))
        XCTAssertNil(resolve("2", x: 85))
        XCTAssertNil(resolve("5", x: 400))
        XCTAssertNil(resolve("1", x: -50))
    }

    func testVerticalBarsUseTopToBottomOrder() {
        // Screen coordinates grow upward, so the first pill sits highest.
        let slots = zip(ids.prefix(3), ["1", "2", "3"]).enumerated().map { index, pair in
            WorkspaceBarReorderSlot(
                id: pair.0,
                name: pair.1,
                frame: CGRect(x: 0, y: 200 - CGFloat(index) * 48, width: 20, height: 40)
            )
        }

        XCTAssertEqual(
            WorkspaceBarReorderResolver.resolve(source: "3", at: CGPoint(x: 10, y: 250), slots: slots, vertical: true),
            WorkspaceBarReorderResolution(position: "1", marker: .before(ids[0]))
        )
        XCTAssertEqual(
            WorkspaceBarReorderResolver.resolve(source: "1", at: CGPoint(x: 10, y: 0), slots: slots, vertical: true),
            WorkspaceBarReorderResolution(position: "3", marker: .after(ids[2]))
        )
    }
}
