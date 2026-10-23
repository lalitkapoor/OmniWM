// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import XCTest

@MainActor
final class WorkspaceReorderTests: XCTestCase {
    // MARK: - Plan

    func testMovingEarlierShiftsTheWorkspacesInBetweenUp() {
        XCTAssertEqual(
            WorkspaceReorderPlan.renames(existing: ["1", "2", "3", "4", "5"], moving: "4", to: "1"),
            ["4": "1", "1": "2", "2": "3", "3": "4"]
        )
    }

    func testMovingLaterShiftsTheWorkspacesInBetweenDown() {
        XCTAssertEqual(
            WorkspaceReorderPlan.renames(existing: ["1", "2", "3", "4", "5"], moving: "1", to: "4"),
            ["1": "4", "2": "1", "3": "2", "4": "3"]
        )
    }

    func testGapsInTheNumberingAreKept() {
        XCTAssertEqual(
            WorkspaceReorderPlan.renames(existing: ["1", "2", "5"], moving: "5", to: "1"),
            ["5": "1", "1": "2", "2": "3"]
        )
        XCTAssertEqual(WorkspaceReorderPlan.renames(existing: ["1", "2", "5"], moving: "5", to: "3"), ["5": "3"])
    }

    func testInvalidMovesHaveNoPlan() {
        let names = ["1", "2", "3"]
        XCTAssertNil(WorkspaceReorderPlan.renames(existing: names, moving: "2", to: "2"), "same position")
        XCTAssertNil(WorkspaceReorderPlan.renames(existing: names, moving: "7", to: "1"), "unknown source")
        XCTAssertNil(WorkspaceReorderPlan.renames(existing: names, moving: "1", to: "4"), "past the last workspace")
        XCTAssertNil(WorkspaceReorderPlan.renames(existing: names, moving: "1", to: "0"), "not a workspace number")
        XCTAssertNil(WorkspaceReorderPlan.renames(existing: names, moving: "1", to: "x"), "not a workspace number")
    }

    // MARK: - Reordering a running setup

    func testReorderMovesContentsAndSettingsAndShiftsTheRest() throws {
        let fixture = try makeFixture()
        let ws = fixture.workspaceIds
        let before = fixture.controller.settings.workspaces.configurations

        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "4", toPosition: "1"), .executed)

        let manager = fixture.controller.workspaceManager
        XCTAssertEqual(manager.workspaceId(named: "1"), ws["4"])
        XCTAssertEqual(manager.workspaceId(named: "2"), ws["1"])
        XCTAssertEqual(manager.workspaceId(named: "3"), ws["2"])
        XCTAssertEqual(manager.workspaceId(named: "4"), ws["3"])
        XCTAssertEqual(manager.workspaceId(named: "5"), ws["5"])
        for descriptor in manager.sortedWorkspaces() {
            XCTAssertEqual(manager.workspaceId(named: descriptor.name), descriptor.id, descriptor.name)
        }

        XCTAssertEqual(workspaceName(of: fixture.windows["4"], in: fixture), "1")
        XCTAssertEqual(workspaceName(of: fixture.windows["1"], in: fixture), "2")
        XCTAssertEqual(workspaceName(of: fixture.windows["5"], in: fixture), "5")

        let after = fixture.controller.settings.workspaces.configurations
        func row(_ name: String, in rows: [WorkspaceConfiguration]) -> WorkspaceConfiguration? {
            rows.first { $0.name == name }
        }
        XCTAssertEqual(row("1", in: after)?.displayName, "Slack")
        XCTAssertEqual(row("1", in: after)?.id, row("4", in: before)?.id)
        XCTAssertEqual(row("2", in: after)?.layoutType, .niri)
        XCTAssertEqual(row("2", in: after)?.id, row("1", in: before)?.id)
        XCTAssertEqual(row("5", in: after), row("5", in: before))
        XCTAssertEqual(after.map(\.name), ["1", "2", "3", "4", "5"])
    }

    func testReorderKeepsEachWorkspacesLayoutTree() throws {
        let fixture = try makeFixture()
        let engine = try XCTUnwrap(fixture.controller.dwindleEngine)
        let movedId = try XCTUnwrap(fixture.workspaceIds["4"])
        let token = try XCTUnwrap(fixture.windows["4"])
        XCTAssertTrue(engine.containsWindow(token, in: movedId))

        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "4", toPosition: "1"), .executed)

        XCTAssertTrue(engine.containsWindow(token, in: movedId))
        XCTAssertEqual(fixture.controller.workspaceManager.descriptor(for: movedId)?.name, "1")
    }

    func testReorderSurvivesReapplyingSettings() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "1", toPosition: "3"), .executed)
        fixture.controller.updateWorkspaceConfig()

        let manager = fixture.controller.workspaceManager
        XCTAssertEqual(manager.workspaceId(named: "3"), fixture.workspaceIds["1"])
        XCTAssertEqual(manager.workspaceId(named: "1"), fixture.workspaceIds["2"])
        XCTAssertEqual(manager.workspaceId(named: "2"), fixture.workspaceIds["3"])
        XCTAssertEqual(manager.sortedWorkspaces().count, 5)
        XCTAssertEqual(
            fixture.controller.settings.workspaces.configurations.first { $0.name == "3" }?.layoutType,
            .niri
        )
    }

    func testInvalidReorderChangesNothing() throws {
        let fixture = try makeFixture()
        let configurations = fixture.controller.settings.workspaces.configurations

        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "2", toPosition: "2"), .noChange)
        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "9", toPosition: "1"), .invalidArguments)
        XCTAssertEqual(fixture.controller.reorderWorkspace(named: "1", toPosition: "6"), .invalidArguments)

        XCTAssertEqual(fixture.controller.settings.workspaces.configurations, configurations)
        for (name, id) in fixture.workspaceIds {
            XCTAssertEqual(fixture.controller.workspaceManager.workspaceId(named: name), id, name)
        }
    }

    func testIPCReorderResolvesTargetsAndValidatesPosition() throws {
        let fixture = try makeFixture()
        let router = IPCCommandRouter(controller: fixture.controller, sessionToken: "reorder-test")

        XCTAssertEqual(
            router.handle(IPCWorkspaceRequest.reorder(target: .displayName("Slack"), position: "1")),
            .executed
        )
        XCTAssertEqual(fixture.controller.workspaceManager.workspaceId(named: "1"), fixture.workspaceIds["4"])
        XCTAssertEqual(router.handle(IPCWorkspaceRequest.reorder(target: .rawID("1"), position: "1")), .noChange)
        XCTAssertEqual(
            router.handle(IPCWorkspaceRequest.reorder(target: .rawID("1"), position: "one")),
            .invalidArguments
        )
        XCTAssertEqual(router.handle(IPCWorkspaceRequest.reorder(target: .rawID("99"), position: "1")), .notFound)
    }

    // MARK: - Fixture

    private struct Fixture {
        let controller: WMController
        let workspaceIds: [String: WorkspaceDescriptor.ID]
        let windows: [String: WindowToken]
    }

    /// Workspaces 1–5 on one monitor: 1 is Niri, 4 is labeled "Slack", and 1, 4 and 5 hold one window each.
    private func makeFixture() throws -> Fixture {
        let monitor = Monitor(
            id: .init(displayId: 88_001),
            displayId: 88_001,
            frame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            hasNotch: false,
            name: "Reorder"
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMWorkspaceReorderTests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        settings.workspaces.configurations = (1 ... 5).map { number in
            WorkspaceConfiguration(
                name: "\(number)",
                displayName: number == 4 ? "Slack" : nil,
                monitorAssignment: .specificDisplay(OutputId(from: monitor)),
                layoutType: number == 1 ? .niri : .dwindle
            )
        }
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.workspaceManager.applyMonitorConfigurationChange([monitor])
        controller.workspaceManager.applySettings()
        controller.dwindleLayoutHandler.enableDwindleLayout()

        var workspaceIds: [String: WorkspaceDescriptor.ID] = [:]
        for number in 1 ... 5 {
            workspaceIds["\(number)"] = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "\(number)"))
        }
        var windows: [String: WindowToken] = [:]
        let engine = try XCTUnwrap(controller.dwindleEngine)
        for name in ["1", "4", "5"] {
            let workspaceId = try XCTUnwrap(workspaceIds[name])
            let id = 88_100 + (Int(name) ?? 0)
            let token = controller.workspaceManager.addWindow(
                AXWindowRef(element: AXUIElementCreateApplication(pid_t(id)), windowId: id),
                pid: pid_t(id),
                windowId: id,
                to: workspaceId
            )
            if name != "1" {
                controller.workspaceManager.withEngineMutationScope {
                    _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
                }
            }
            windows[name] = token
        }
        return Fixture(controller: controller, workspaceIds: workspaceIds, windows: windows)
    }

    private func workspaceName(of token: WindowToken?, in fixture: Fixture) -> String? {
        let manager = fixture.controller.workspaceManager
        return token.flatMap { manager.entry(for: $0)?.workspaceId }.flatMap { manager.descriptor(for: $0)?.name }
    }
}
