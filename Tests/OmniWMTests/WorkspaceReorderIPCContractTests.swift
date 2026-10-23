// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
@testable import OmniWMCtl
import OmniWMIPC
import XCTest

final class WorkspaceReorderIPCContractTests: XCTestCase {
    func testReorderWireShapeRoundTrips() throws {
        let request = IPCWorkspaceRequest.reorder(target: .rawID("4"), position: "1")
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["name"] as? String, "reorder")
        XCTAssertEqual(object["workspaceTarget"] as? [String: String], ["kind": "raw-id", "value": "4"])
        XCTAssertEqual(object["position"] as? String, "1")
        XCTAssertNil(object["displayName"])
        XCTAssertEqual(try JSONDecoder().decode(IPCWorkspaceRequest.self, from: data), request)
    }

    func testReorderDecodeRequiresPosition() {
        let data = Data(#"{"name": "reorder", "workspaceTarget": {"kind": "raw-id", "value": "4"}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(IPCWorkspaceRequest.self, from: data))
    }

    func testManifestDescribesWorkspaceReorder() throws {
        let descriptor = try XCTUnwrap(
            IPCAutomationManifest.workspaceActionDescriptors.first { $0.name == .reorder }
        )

        XCTAssertEqual(descriptor.actionWords, ["reorder"])
        XCTAssertEqual(descriptor.path, "workspace reorder <workspace> <position>")
        XCTAssertEqual(descriptor.arguments, ["workspace", "position"])
        XCTAssertTrue(descriptor.optionalFlags.isEmpty)
    }

    func testParserBuildsWorkspaceReorder() throws {
        let parsed = try CLIParser.parse(arguments: ["omniwmctl", "workspace", "reorder", "4", "1"])
        guard case let .workspace(request) = parsed.request.payload else { return XCTFail("expected workspace") }
        XCTAssertEqual(request, .reorder(target: .rawID("4"), position: "1"))
    }

    func testParserRejectsMalformedWorkspaceReorders() {
        for invocation in [
            ["workspace", "reorder", "4"],
            ["workspace", "reorder", "4", "1", "extra"],
            ["workspace", "reorder", "--force", "4", "1"]
        ] {
            XCTAssertThrowsError(try CLIParser.parse(arguments: ["omniwmctl"] + invocation)) { error in
                XCTAssertEqual(error as? CLIParseError, .usage(CLIParser.usageText))
            }
        }
    }

    func testHelpAndCompletionsExposeWorkspaceReorder() {
        XCTAssertTrue(CLIParser.usageText.contains("omniwmctl workspace reorder <workspace> <position>"))
        for shell in CLIShell.allCases {
            XCTAssertTrue(CLICompletionGenerator.script(for: shell).contains("reorder"), "\(shell)")
        }
    }
}
