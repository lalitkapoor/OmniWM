// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import OmniWMIPC
import TOML
import XCTest

@MainActor
final class DwindleDirectionalFocusSkipsTabsTests: XCTestCase {
    /// Source monitor sits above the target monitor. On the source workspace, tile A `[a0, a1, a2]`
    /// (active `a1`) fills the top half and tile B `[b0, b1]` (active `b1`) fills the bottom half.
    private struct Fixture {
        let controller: WMController
        let engine: DwindleLayoutEngine
        let sourceMonitor: Monitor
        let targetMonitor: Monitor
        let workspaceId: WorkspaceDescriptor.ID
        let tileA: [WindowToken]
        let tileB: [WindowToken]
        let targetToken: WindowToken

        @MainActor var router: IPCCommandRouter {
            IPCCommandRouter(controller: controller, sessionToken: "focus-skips-tabs-test")
        }

        var activeToken: WindowToken? {
            engine.activeToken(in: workspaceId)
        }

        func activeMember(of tile: [WindowToken]) -> WindowToken? {
            engine.tileSnapshot(for: tile[0], in: workspaceId)?.activeToken
        }
    }

    // MARK: - Configuration

    func testSettingDefaultsOffAndIsWrittenToTOML() throws {
        XCTAssertEqual(SettingsExport.Dwindle.defaults().directionalFocusSkipsTabs, false)
        XCTAssertFalse(DwindlePreferences(gaps: GapSettings()).directionalFocusSkipsTabs)

        let data = try SettingsTOMLCodec.encode(.defaults())
        let tree = try TOMLDecoder().decode([String: TOMLNode].self, from: data)
        guard case let .table(dwindle)? = tree["dwindle"] else { return XCTFail("Expected dwindle table") }
        XCTAssertEqual(dwindle["directionalFocusSkipsTabs"], .boolean(false))
    }

    func testMissingKeyDecodesToDefaultAndEnabledValueRoundTrips() throws {
        var legacy = SettingsExport.defaults()
        legacy.dwindle.directionalFocusSkipsTabs = nil
        XCTAssertEqual(try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(legacy)), .defaults())

        let preferences = DwindlePreferences(gaps: GapSettings())
        preferences.directionalFocusSkipsTabs = true
        var export = SettingsExport.defaults()
        export.dwindle = preferences.export()
        let reloaded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))
        XCTAssertEqual(reloaded.dwindle.directionalFocusSkipsTabs, true)

        let restored = DwindlePreferences(gaps: GapSettings())
        restored.apply(reloaded.dwindle)
        XCTAssertTrue(restored.directionalFocusSkipsTabs)
        restored.apply(legacy.dwindle)
        XCTAssertFalse(restored.directionalFocusSkipsTabs)
    }

    // MARK: - Spatial focus from grouped tiles

    func testFocusDownFromGroupedTileGoesStraightToNeighborAndKeepsItsActiveTab() throws {
        let fixture = try makeFixture(skipsTabs: true)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.focus(.down)), .executed)

        XCTAssertEqual(fixture.activeToken, fixture.tileB[1])
        XCTAssertEqual(fixture.activeMember(of: fixture.tileA), fixture.tileA[1])
        XCTAssertEqual(fixture.activeMember(of: fixture.tileB), fixture.tileB[1])
    }

    func testFocusUpFromGroupedTileGoesStraightToNeighborViaIPC() throws {
        let fixture = try makeFixture(skipsTabs: true)
        focusTile(fixture.tileB, of: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.router.handle(.focus(.spatial(direction: .up))), .executed)

        XCTAssertEqual(fixture.activeToken, fixture.tileA[1])
        XCTAssertEqual(fixture.activeMember(of: fixture.tileB), fixture.tileB[1])
    }

    func testDefaultSettingStillTraversesTabsFirst() throws {
        let fixture = try makeFixture(skipsTabs: false)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.focus(.down)), .executed)

        XCTAssertEqual(fixture.activeToken, fixture.tileA[2])
    }

    // MARK: - Screen edges

    func testEdgeWithoutMonitorDoesNotCycleOrWrapWithinGroup() throws {
        let fixture = try makeFixture(skipsTabs: true)
        activate(fixture.tileA[0], in: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        for direction in [Direction.up, .left, .right] {
            _ = fixture.controller.commandHandler.performCommand(.focus(direction))
            XCTAssertEqual(fixture.activeToken, fixture.tileA[0], direction.rawValue)
            XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.sourceMonitor.id)
        }
        XCTAssertEqual(fixture.router.handle(.focus(.spatial(direction: .up))), .executed)
        XCTAssertEqual(fixture.activeToken, fixture.tileA[0])
    }

    func testDefaultSettingStillWrapsLocallyAtEdgeWithoutMonitor() throws {
        let fixture = try makeFixture(skipsTabs: false)
        activate(fixture.tileA[0], in: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        _ = fixture.controller.commandHandler.performCommand(.focus(.up))

        XCTAssertEqual(fixture.activeToken, fixture.tileA[2])
    }

    func testEdgeWithAdjacentMonitorFollowsMonitorPolicyWithoutTabTraversal() throws {
        let fixture = try makeFixture(skipsTabs: true)
        focusTile(fixture.tileB, of: fixture)
        activate(fixture.tileB[0], in: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.focus(.down)), .executed)

        XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.targetMonitor.id)
        XCTAssertEqual(fixture.activeMember(of: fixture.tileB), fixture.tileB[0])
    }

    func testEdgeWithMonitorCrossingDisabledStaysPut() throws {
        let fixture = try makeFixture(skipsTabs: true)
        fixture.controller.settings.focus.crossesMonitorAtEdge = false
        focusTile(fixture.tileB, of: fixture)
        activate(fixture.tileB[0], in: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        _ = fixture.controller.commandHandler.performCommand(.focus(.down))

        XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.sourceMonitor.id)
        XCTAssertEqual(fixture.activeToken, fixture.tileB[0])
    }

    // MARK: - Next / Previous Tab in Tile

    func testTabInTileActionsCycleAndWrapWithinTileOnly() throws {
        for skipsTabs in [true, false] {
            let fixture = try makeFixture(skipsTabs: skipsTabs)
            let tileAId = try XCTUnwrap(fixture.engine.tileSnapshot(for: fixture.tileA[0], in: fixture.workspaceId)?.id)
            let blocker = blockLayoutRefresh(fixture)
            defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

            for expected in [fixture.tileA[2], fixture.tileA[0], fixture.tileA[1]] {
                XCTAssertEqual(
                    fixture.controller.commandHandler.performCommand(.dwindle(.focusNextTabInTile)),
                    .executed
                )
                XCTAssertEqual(fixture.activeToken, expected, "skipsTabs: \(skipsTabs)")
            }
            for expected in [fixture.tileA[0], fixture.tileA[2], fixture.tileA[1]] {
                XCTAssertEqual(fixture.router.handle(.dwindle(.focusPreviousTabInTile)), .executed)
                XCTAssertEqual(fixture.activeToken, expected, "skipsTabs: \(skipsTabs)")
            }

            XCTAssertEqual(
                fixture.engine.tileSnapshot(for: try XCTUnwrap(fixture.activeToken), in: fixture.workspaceId)?.id,
                tileAId
            )
            XCTAssertEqual(fixture.activeMember(of: fixture.tileB), fixture.tileB[1])
            XCTAssertEqual(fixture.controller.workspaceManager.interactionMonitorId, fixture.sourceMonitor.id)
        }
    }

    func testTabInTileSkipsIneligibleMembers() throws {
        let fixture = try makeFixture(skipsTabs: true)
        fixture.controller.workspaceManager.setLayoutReason(.nativeFullscreen, for: fixture.tileA[2])
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.dwindle(.focusNextTabInTile)), .executed)

        XCTAssertEqual(fixture.activeToken, fixture.tileA[0])
    }

    func testTabInTileIsNoChangeOnSingletonTile() throws {
        let fixture = try makeFixture(skipsTabs: true, groupTileB: false)
        focusTile(fixture.tileB, of: fixture)
        let blocker = blockLayoutRefresh(fixture)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(fixture.controller.commandHandler.performCommand(.dwindle(.focusNextTabInTile)), .noChange)
        XCTAssertEqual(fixture.router.handle(.dwindle(.focusPreviousTabInTile)), .noChange)
        XCTAssertEqual(fixture.activeToken, fixture.tileB[0])
    }

    func testTabInTileActionsAreAssignableDwindleCommandsWithIPCNames() throws {
        let cases: [(DwindleAction, String, IPCDwindleCommandName, IPCDwindleCommand)] = [
            (.focusNextTabInTile, "focusNextTabInTile", .focusNextTabInTile, .focusNextTabInTile),
            (.focusPreviousTabInTile, "focusPreviousTabInTile", .focusPreviousTabInTile, .focusPreviousTabInTile)
        ]
        for (action, id, ipcName, ipcCommand) in cases {
            let spec = try XCTUnwrap(ActionCatalog.spec(for: .dwindle(action)))
            XCTAssertEqual(spec.id, id)
            XCTAssertEqual(spec.layoutCompatibility, .dwindle)
            XCTAssertEqual(spec.category, .focus)
            XCTAssertEqual(spec.defaultBinding, .unassigned)
            XCTAssertNotEqual(spec.visibility, .unassignable)
            XCTAssertEqual(spec.ipcCommandName, .dwindle(ipcName))
            XCTAssertNotNil(spec.ipcDescriptor)
            XCTAssertEqual(HotkeyCommand(ipc: ipcCommand), .dwindle(action))
        }
        XCTAssertEqual(IPCDwindleCommandName.focusNextTabInTile.rawValue, "focus-next-tab-in-tile")
        XCTAssertEqual(IPCDwindleCommandName.focusPreviousTabInTile.rawValue, "focus-previous-tab-in-tile")
    }

    // MARK: - Fixtures

    private func makeFixture(skipsTabs: Bool, groupTileB: Bool = true) throws -> Fixture {
        let sourceMonitor = Monitor(
            id: .init(displayId: 32_001),
            displayId: 32_001,
            frame: CGRect(x: 0, y: 900, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 900, width: 1600, height: 900),
            hasNotch: false,
            name: "Source"
        )
        let targetMonitor = Monitor(
            id: .init(displayId: 32_002),
            displayId: 32_002,
            frame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
            hasNotch: false,
            name: "Target"
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMDwindleFocusSkipsTabsTests-\(UUID().uuidString)", isDirectory: true)
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
        settings.workspaces.configurations = [
            WorkspaceConfiguration(
                name: "1",
                monitorAssignment: .specificDisplay(OutputId(from: sourceMonitor)),
                layoutType: .dwindle
            ),
            WorkspaceConfiguration(
                name: "2",
                monitorAssignment: .specificDisplay(OutputId(from: targetMonitor)),
                layoutType: .dwindle
            )
        ]
        settings.focus.crossesMonitorAtEdge = true
        settings.dwindle.directionalFocusSkipsTabs = skipsTabs
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.workspaceManager.applyMonitorConfigurationChange([sourceMonitor, targetMonitor])
        controller.workspaceManager.applySettings()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "1"))
        let targetWorkspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: "2"))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(
            targetWorkspaceId,
            on: targetMonitor.id,
            updateInteractionMonitor: false
        ))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspaceId, on: sourceMonitor.id))

        let engine = DwindleLayoutEngine()
        engine.animationClock = controller.animationClock
        controller.dwindleEngine = engine
        let tileA = (0 ..< 3).map { addWindow(id: 32_100 + $0, to: workspaceId, controller: controller) }
        let tileB = (0 ..< (groupTileB ? 2 : 1)).map {
            addWindow(id: 32_200 + $0, to: workspaceId, controller: controller)
        }
        let targetToken = addWindow(id: 32_300, to: targetWorkspaceId, controller: controller)
        let screen = sourceMonitor.visibleFrame

        controller.workspaceManager.withEngineMutationScope(in: workspaceId) {
            _ = engine.addWindow(token: tileA[0], to: workspaceId, activeWindowFrame: nil)
            for token in tileA.dropFirst() {
                _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: nil)
                _ = engine.calculateLayout(for: workspaceId, screen: screen)
                XCTAssertTrue(engine.groupWindow(direction: .left, in: workspaceId))
                _ = engine.calculateLayout(for: workspaceId, screen: screen)
            }
            XCTAssertTrue(engine.setPreselection(.down, in: workspaceId))
            _ = engine.addWindow(token: tileB[0], to: workspaceId, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            if groupTileB {
                _ = engine.addWindow(token: tileB[1], to: workspaceId, activeWindowFrame: nil)
                _ = engine.calculateLayout(for: workspaceId, screen: screen)
                XCTAssertTrue(engine.groupWindow(direction: .left, in: workspaceId))
                _ = engine.calculateLayout(for: workspaceId, screen: screen)
            }
            _ = engine.addWindow(token: targetToken, to: targetWorkspaceId, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: targetWorkspaceId, screen: targetMonitor.visibleFrame)
            XCTAssertEqual(engine.activateWindowOutcome(tileA[1], in: workspaceId), .activated)
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
        }
        XCTAssertTrue(controller.workspaceManager.setManagedFocus(
            tileA[1],
            in: workspaceId,
            onMonitor: sourceMonitor.id
        ))
        XCTAssertNotNil(controller.preferredKeyboardFocusFrame(for: targetToken))

        let fixture = Fixture(
            controller: controller,
            engine: engine,
            sourceMonitor: sourceMonitor,
            targetMonitor: targetMonitor,
            workspaceId: workspaceId,
            tileA: tileA,
            tileB: tileB,
            targetToken: targetToken
        )
        XCTAssertEqual(fixture.engine.tileSnapshot(for: tileA[0], in: workspaceId)?.members.map(\.token), tileA)
        XCTAssertEqual(fixture.engine.tileSnapshot(for: tileB[0], in: workspaceId)?.members.map(\.token), tileB)
        XCTAssertEqual(fixture.activeToken, tileA[1])
        XCTAssertEqual(fixture.activeMember(of: tileB), tileB.last)
        XCTAssertEqual(
            engine.findGeometricNeighbor(from: tileA[1], direction: .down, in: workspaceId),
            tileB.last
        )
        return fixture
    }

    private func focusTile(_ tile: [WindowToken], of fixture: Fixture) {
        let token = fixture.activeMember(of: tile) ?? tile[0]
        fixture.controller.workspaceManager.withEngineMutationScope(in: fixture.workspaceId) {
            fixture.engine.setSelectedNode(
                fixture.engine.findNode(for: token, in: fixture.workspaceId),
                in: fixture.workspaceId
            )
        }
        XCTAssertTrue(fixture.controller.workspaceManager.setManagedFocus(
            token,
            in: fixture.workspaceId,
            onMonitor: fixture.sourceMonitor.id
        ))
        XCTAssertEqual(fixture.activeToken, token)
    }

    private func activate(_ token: WindowToken, in fixture: Fixture) {
        fixture.controller.workspaceManager.withEngineMutationScope(in: fixture.workspaceId) {
            _ = fixture.engine.activateWindowOutcome(token, in: fixture.workspaceId)
            _ = fixture.engine.calculateLayout(
                for: fixture.workspaceId,
                screen: fixture.sourceMonitor.visibleFrame
            )
        }
        XCTAssertEqual(fixture.activeToken, token)
    }

    private func addWindow(
        id: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) -> WindowToken {
        let pid = pid_t(id)
        return controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: id),
            pid: pid,
            windowId: id,
            to: workspaceId
        )
    }

    private func blockLayoutRefresh(_ fixture: Fixture) -> Task<Void, Never> {
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        fixture.controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        fixture.controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [fixture.workspaceId]
        )
        return blocker
    }

    private func unblockLayoutRefresh(_ controller: WMController, blocker: Task<Void, Never>) {
        blocker.cancel()
        controller.layoutRefreshController.layoutState.activeRefreshTask = nil
        controller.layoutRefreshController.layoutState.activeRefresh = nil
        controller.layoutRefreshController.layoutState.pendingRefresh = nil
    }
}
