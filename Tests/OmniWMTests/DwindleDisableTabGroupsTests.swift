// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import TOML
import XCTest

@MainActor
final class DwindleDisableTabGroupsTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    // MARK: - Configuration

    func testSettingDefaultsToEnabledGroupsAndIsWrittenToTOML() throws {
        XCTAssertEqual(SettingsExport.Dwindle.defaults().disableTabGroups, false)

        let data = try SettingsTOMLCodec.encode(.defaults())
        let tree = try TOMLDecoder().decode([String: TOMLNode].self, from: data)
        guard case let .table(dwindle)? = tree["dwindle"] else { return XCTFail("Expected dwindle table") }
        XCTAssertEqual(dwindle["disableTabGroups"], .boolean(false))
    }

    func testMissingKeyDecodesToDefaultAndEnabledValueRoundTrips() throws {
        var legacy = SettingsExport.defaults()
        legacy.dwindle.disableTabGroups = nil
        XCTAssertEqual(try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(legacy)), .defaults())

        let preferences = DwindlePreferences(gaps: GapSettings())
        XCTAssertFalse(preferences.disableTabGroups)
        preferences.disableTabGroups = true
        var export = SettingsExport.defaults()
        export.dwindle = preferences.export()
        let reloaded = try SettingsTOMLCodec.decode(SettingsTOMLCodec.encode(export))
        XCTAssertEqual(reloaded.dwindle.disableTabGroups, true)

        let restored = DwindlePreferences(gaps: GapSettings())
        restored.apply(reloaded.dwindle)
        XCTAssertTrue(restored.disableTabGroups)
        restored.apply(legacy.dwindle)
        XCTAssertFalse(restored.disableTabGroups)
    }

    func testSettingResolvesIntoEngineSettings() {
        let preferences = DwindlePreferences(gaps: GapSettings())
        preferences.disableTabGroups = true
        let monitor = makeMonitor()
        let resolved = preferences.resolved(for: monitor)
        XCTAssertTrue(resolved.disableTabGroups)

        let handler = DwindleLayoutHandler(controller: nil)
        let engine = DwindleLayoutEngine()
        handler.applyResolvedSettings(resolved, to: engine)
        XCTAssertTrue(engine.settings.disableTabGroups)
        XCTAssertTrue(handler.calculationSettings(resolved, from: DwindleLayoutEngine()).disableTabGroups)
    }

    // MARK: - Engine: grouping prevention

    func testDefaultSettingStillJoinsGroups() {
        let (engine, workspace, _, _) = makeTwoWindowEngine()
        XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
        XCTAssertEqual(engine.tileCount(in: workspace), 1)
    }

    func testDisabledSettingRejectsJoinWithoutMutation() {
        let (engine, workspace, first, second) = makeTwoWindowEngine()
        engine.settings.disableTabGroups = true

        XCTAssertFalse(engine.groupWindow(direction: .left, in: workspace))
        XCTAssertFalse(engine.groupWindow(second, into: first, in: workspace))
        XCTAssertEqual(engine.tileCount(in: workspace), 2)
        XCTAssertEqual(engine.tileSnapshot(for: first, in: workspace)?.members.map(\.token), [first])
        XCTAssertEqual(engine.tileSnapshot(for: second, in: workspace)?.members.map(\.token), [second])
    }

    // MARK: - Engine: conversion of existing groups

    func testSyncKeepsGroupsWhenSettingIsOff() {
        let (engine, workspace, first, second, third) = makeThreeMemberGroupEngine()

        _ = engine.syncWindows([first, second, third], in: workspace, focusedToken: second)

        XCTAssertEqual(engine.tileCount(in: workspace), 1)
        XCTAssertEqual(engine.inactiveGroupTokens(in: workspace), [first, third])
    }

    func testSyncSeparatesGroupPreservingOrderFocusAndTileIdentity() throws {
        let (engine, workspace, first, second, third) = makeThreeMemberGroupEngine()
        let originalTileId = try XCTUnwrap(engine.tileSnapshot(for: first, in: workspace)?.id)
        XCTAssertEqual(engine.activeToken(in: workspace), second)
        engine.settings.disableTabGroups = true

        let removed = engine.syncWindows([first, second, third], in: workspace, focusedToken: second)

        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(engine.windowCount(in: workspace), 3)
        XCTAssertEqual(engine.tileCount(in: workspace), 3)
        XCTAssertTrue(engine.inactiveGroupTokens(in: workspace).isEmpty)
        for token in [first, second, third] {
            XCTAssertEqual(engine.tileSnapshot(for: token, in: workspace)?.members.map(\.token), [token])
        }
        XCTAssertEqual(engine.tileSnapshot(for: first, in: workspace)?.id, originalTileId)
        XCTAssertEqual(engine.activeToken(in: workspace), second)

        let frames = engine.calculateLayout(for: workspace, screen: screen)
        XCTAssertEqual(Set(frames.keys), [first, second, third])
        let firstFrame = try XCTUnwrap(frames[first])
        let secondFrame = try XCTUnwrap(frames[second])
        let thirdFrame = try XCTUnwrap(frames[third])
        XCTAssertLessThan(firstFrame.midX, secondFrame.midX)
        XCTAssertGreaterThan(secondFrame.midY, thirdFrame.midY)
        XCTAssertFalse(firstFrame.intersects(secondFrame))
        XCTAssertFalse(secondFrame.intersects(thirdFrame))
        XCTAssertFalse(firstFrame.intersects(thirdFrame))
    }

    func testSeparationKeepsUngroupedTilesAndFullscreenFlags() throws {
        let (engine, workspace, first, second, third) = makeThreeMemberGroupEngine()
        let outsider = WindowToken(pid: 4, windowId: 4)
        XCTAssertTrue(engine.setPreselection(.right, in: workspace))
        _ = engine.addWindow(token: outsider, to: workspace, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        XCTAssertEqual(engine.activateWindowOutcome(third, in: workspace), .activated)
        XCTAssertEqual(engine.toggleFullscreen(in: workspace), third)
        let outsiderTileId = try XCTUnwrap(engine.tileSnapshot(for: outsider, in: workspace)?.id)
        engine.settings.disableTabGroups = true

        _ = engine.syncWindows([first, second, third, outsider], in: workspace, focusedToken: third)

        XCTAssertEqual(engine.tileCount(in: workspace), 4)
        XCTAssertEqual(engine.tileSnapshot(for: outsider, in: workspace)?.id, outsiderTileId)
        XCTAssertTrue(engine.isWindowFullscreen(third, in: workspace))
        XCTAssertFalse(engine.isWindowFullscreen(first, in: workspace))
        XCTAssertEqual(engine.activeToken(in: workspace), third)
    }

    func testSeparationSeedsPeeledMembersFromGroupFrame() throws {
        let (engine, workspace, first, second, third) = makeThreeMemberGroupEngine()
        engine.findNode(for: second, in: workspace)?.clearAnimations()
        let groupFrame = try XCTUnwrap(engine.contentFrame(for: second, in: workspace))
        var oldFrames: [WindowToken: CGRect] = [:]
        var previousTargetFrames: [WindowToken: CGRect] = [:]
        // Drain the seeds left by the fixture's own joins, as each relayout pass does.
        engine.consumePendingMovementFrameSeeds(
            in: workspace,
            oldFrames: &oldFrames,
            previousTargetFrames: &previousTargetFrames
        )
        oldFrames.removeAll()
        engine.settings.disableTabGroups = true

        _ = engine.syncWindows([first, second, third], in: workspace, focusedToken: second)

        engine.consumePendingMovementFrameSeeds(
            in: workspace,
            oldFrames: &oldFrames,
            previousTargetFrames: &previousTargetFrames
        )
        XCTAssertEqual(oldFrames[second], groupFrame)
        XCTAssertEqual(oldFrames[third], groupFrame)
        XCTAssertNil(oldFrames[first])
    }

    // MARK: - Engine: restoration

    func testRestoredGroupPlacementsAreSeparatedOnReconciliation() throws {
        let a = WindowToken(pid: 1, windowId: 1)
        let b = WindowToken(pid: 2, windowId: 2)
        let c = WindowToken(pid: 3, windowId: 3)
        let step = { (index: Int) in
            PersistedDwindleSplitStep(orientation: .horizontal, ratio: 1.0, childIndex: index)
        }
        let placements: [WindowToken: PersistedDwindlePlacement] = [
            a: PersistedDwindlePlacement(steps: [step(0)], memberIndex: 1, isActiveMember: false),
            b: PersistedDwindlePlacement(steps: [step(0)], memberIndex: 0, isActiveMember: true),
            c: PersistedDwindlePlacement(steps: [step(1)], memberIndex: 0, isActiveMember: true)
        ]
        let engine = DwindleLayoutEngine()
        engine.settings.disableTabGroups = true
        let workspace = WorkspaceDescriptor.ID()

        // Mirrors DwindleLayoutHandler.prepareRelayoutTransition: restore, then sync.
        XCTAssertTrue(engine.restoreInitialPlacements(placements, matching: [a, b, c], in: workspace))
        _ = engine.syncWindows([a, b, c], in: workspace, focusedToken: b)

        XCTAssertEqual(engine.tileCount(in: workspace), 3)
        XCTAssertTrue(engine.inactiveGroupTokens(in: workspace).isEmpty)
        XCTAssertEqual(engine.activeToken(in: workspace), b)
        XCTAssertEqual(engine.root(for: workspace)?.collectAllWindows(), [b, a, c])
        XCTAssertTrue(engine.persistedPlacements(in: workspace).values.allSatisfy { $0.memberIndex == 0 })
    }

    // MARK: - Controller: reconciliation, focus and movement

    func testRelayoutSeparatesGroupAndRevealsParkedMember() throws {
        let fixture = try makeFixture()
        fixture.controller.workspaceManager.setHiddenState(
            HiddenState(proportionalPosition: .zero, referenceMonitorId: nil, reason: .layoutTransient(.left)),
            for: fixture.inactiveToken
        )
        fixture.controller.settings.dwindle.disableTabGroups = true

        let plan = try XCTUnwrap(relayout(fixture).first)

        XCTAssertEqual(fixture.engine.tileCount(in: fixture.workspaceId), 3)
        XCTAssertTrue(fixture.engine.inactiveGroupTokens(in: fixture.workspaceId).isEmpty)
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)
        XCTAssertEqual(
            fixture.controller.workspaceManager.entry(for: fixture.inactiveToken)?.workspaceId,
            fixture.workspaceId
        )
        XCTAssertTrue(plan.diff.frameChanges.contains { $0.token == fixture.inactiveToken })
        XCTAssertTrue(plan.diff.visibilityChanges.contains { change in
            if case let .show(token) = change { return token == fixture.inactiveToken }
            return false
        })
        XCTAssertFalse(plan.diff.visibilityChanges.contains { change in
            if case .hide = change { return true }
            return false
        })
    }

    func testFocusIsSpatialAfterSeparation() throws {
        let fixture = try makeFixture()
        fixture.controller.settings.dwindle.disableTabGroups = true
        _ = try relayout(fixture)
        let handler = fixture.controller.dwindleLayoutHandler
        let blocker = blockLayoutRefresh(fixture.controller, workspaceId: fixture.workspaceId)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertFalse(handler.focusNeighbor(direction: .up))
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)
        XCTAssertFalse(handler.wrapGroupFocus(direction: .up))

        XCTAssertTrue(handler.focusNeighbor(direction: .left))
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.inactiveToken)
        XCTAssertTrue(handler.focusNeighbor(direction: .down))
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.neighborToken)
        XCTAssertTrue(handler.focusNeighbor(direction: .up))
        XCTAssertNotEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.neighborToken)
    }

    func testFocusSkipsTabTraversalEvenBeforeReconciliation() throws {
        let fixture = try makeFixture()
        fixture.controller.settings.dwindle.disableTabGroups = true
        let blocker = blockLayoutRefresh(fixture.controller, workspaceId: fixture.workspaceId)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertFalse(fixture.controller.dwindleLayoutHandler.focusNeighbor(direction: .up))
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)
        XCTAssertFalse(fixture.controller.dwindleLayoutHandler.wrapGroupFocus(direction: .down))
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)
    }

    func testMoveSwapsTilesInsteadOfJoiningAndMatchesMoveContainer() throws {
        let fixture = try makeFixture()
        fixture.controller.settings.dwindle.disableTabGroups = true
        _ = try relayout(fixture)
        let handler = fixture.controller.dwindleLayoutHandler
        let root = try XCTUnwrap(fixture.engine.root(for: fixture.workspaceId))
        let originalOrder = root.collectAllWindows()
        XCTAssertEqual(
            originalOrder.filter { $0 != fixture.neighborToken },
            [fixture.inactiveToken, fixture.activeToken]
        )
        let swappedOrder = originalOrder.map { token in
            token == fixture.inactiveToken ? fixture.activeToken
                : token == fixture.activeToken ? fixture.inactiveToken : token
        }
        let blocker = blockLayoutRefresh(fixture.controller, workspaceId: fixture.workspaceId)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(handler.moveWindow(direction: .left), .movedWithinWorkspace)
        XCTAssertEqual(fixture.engine.tileCount(in: fixture.workspaceId), 3)
        XCTAssertTrue(fixture.engine.inactiveGroupTokens(in: fixture.workspaceId).isEmpty)
        XCTAssertEqual(root.collectAllWindows(), swappedOrder)
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)

        layoutEngine(fixture)
        XCTAssertEqual(handler.moveWindow(direction: .left), .atWorkspaceEdge)
        XCTAssertEqual(handler.moveWindow(direction: .up), .atWorkspaceEdge)
        XCTAssertEqual(handler.swapWindow(direction: .right), .movedWithinWorkspace)
        XCTAssertEqual(root.collectAllWindows(), originalOrder)

        layoutEngine(fixture)
        XCTAssertEqual(handler.moveWindow(direction: .down), .movedWithinWorkspace)
        XCTAssertEqual(fixture.engine.tileCount(in: fixture.workspaceId), 3)
        XCTAssertEqual(fixture.engine.activeToken(in: fixture.workspaceId), fixture.activeToken)
        XCTAssertEqual(
            fixture.engine.tileSnapshot(for: fixture.activeToken, in: fixture.workspaceId)?.members.count,
            1
        )
    }

    func testMoveFromStillGroupedTileDoesNotJoinNeighbor() throws {
        let fixture = try makeFixture()
        fixture.controller.settings.dwindle.disableTabGroups = true
        let blocker = blockLayoutRefresh(fixture.controller, workspaceId: fixture.workspaceId)
        defer { unblockLayoutRefresh(fixture.controller, blocker: blocker) }

        XCTAssertEqual(
            fixture.controller.dwindleLayoutHandler.moveWindow(direction: .down),
            .movedWithinWorkspace
        )
        XCTAssertEqual(
            fixture.engine.tileSnapshot(for: fixture.neighborToken, in: fixture.workspaceId)?.members.count,
            1
        )
        XCTAssertEqual(fixture.engine.tileCount(in: fixture.workspaceId), 2)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let controller: WMController
        let workspaceId: WorkspaceDescriptor.ID
        let engine: DwindleLayoutEngine
        let inactiveToken: WindowToken
        let activeToken: WindowToken
        let neighborToken: WindowToken
    }

    private func makeTwoWindowEngine() -> (DwindleLayoutEngine, WorkspaceDescriptor.ID, WindowToken, WindowToken) {
        let engine = DwindleLayoutEngine()
        let workspace = WorkspaceDescriptor.ID()
        let first = WindowToken(pid: 1, windowId: 1)
        let second = WindowToken(pid: 2, windowId: 2)
        _ = engine.addWindow(token: first, to: workspace, activeWindowFrame: nil)
        _ = engine.addWindow(token: second, to: workspace, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        return (engine, workspace, first, second)
    }

    /// One tile holding `[first, second, third]` with `second` active.
    private func makeThreeMemberGroupEngine() -> (
        DwindleLayoutEngine,
        WorkspaceDescriptor.ID,
        WindowToken,
        WindowToken,
        WindowToken
    ) {
        let (engine, workspace, first, second) = makeTwoWindowEngine()
        let third = WindowToken(pid: 3, windowId: 3)
        XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
        _ = engine.calculateLayout(for: workspace, screen: screen)
        _ = engine.addWindow(token: third, to: workspace, activeWindowFrame: nil)
        _ = engine.calculateLayout(for: workspace, screen: screen)
        XCTAssertTrue(engine.groupWindow(direction: .left, in: workspace))
        _ = engine.calculateLayout(for: workspace, screen: screen)
        XCTAssertEqual(engine.activateWindowOutcome(second, in: workspace), .activated)
        XCTAssertEqual(engine.tileSnapshot(for: first, in: workspace)?.members.map(\.token), [first, second, third])
        return (engine, workspace, first, second, third)
    }

    /// A group `[inactive, active]` filling the top half, with a singleton neighbor below it.
    private func makeFixture() throws -> Fixture {
        let controller = makeController()
        let workspaceName = "96"
        controller.settings.workspaces.configurations.append(
            WorkspaceConfiguration(name: workspaceName, layoutType: .dwindle)
        )
        controller.workspaceManager.applySettings()
        let workspaceId = try XCTUnwrap(controller.workspaceManager.workspaceId(named: workspaceName))
        _ = controller.workspaceManager.focusWorkspace(named: workspaceName)
        controller.dwindleLayoutHandler.enableDwindleLayout()
        let engine = try XCTUnwrap(controller.dwindleEngine)
        controller.layoutRefreshController.resetState()

        let inactive = addWindow(pid: 981, windowId: 1, workspaceId: workspaceId, controller: controller)
        let active = addWindow(pid: 982, windowId: 2, workspaceId: workspaceId, controller: controller)
        let neighbor = addWindow(pid: 983, windowId: 3, workspaceId: workspaceId, controller: controller)
        let screen = try XCTUnwrap(controller.workspaceManager.monitor(for: workspaceId)?.visibleFrame)
        controller.workspaceManager.withEngineMutationScope {
            _ = engine.addWindow(token: inactive, to: workspaceId, activeWindowFrame: nil)
            _ = engine.addWindow(token: active, to: workspaceId, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            XCTAssertTrue(engine.groupWindow(direction: .left, in: workspaceId))
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            XCTAssertTrue(engine.setPreselection(.down, in: workspaceId))
            _ = engine.addWindow(token: neighbor, to: workspaceId, activeWindowFrame: nil)
            _ = engine.calculateLayout(for: workspaceId, screen: screen)
            engine.setSelectedNode(engine.findNode(for: active, in: workspaceId), in: workspaceId)
        }
        _ = controller.workspaceManager.applySessionPatch(
            .init(
                workspaceId: workspaceId,
                viewportState: nil,
                rememberedFocusToken: active,
                plannedSeq: controller.workspaceManager.worldSeq
            )
        )
        controller.layoutRefreshController.resetState()
        XCTAssertEqual(engine.activeToken(in: workspaceId), active)
        XCTAssertEqual(engine.tileSnapshot(for: active, in: workspaceId)?.members.map(\.token), [inactive, active])
        return Fixture(
            controller: controller,
            workspaceId: workspaceId,
            engine: engine,
            inactiveToken: inactive,
            activeToken: active,
            neighborToken: neighbor
        )
    }

    private func relayout(_ fixture: Fixture) throws -> [WorkspaceLayoutPlan] {
        let plans = fixture.controller.workspaceManager.withBatchedLayoutBuild {
            fixture.controller.dwindleLayoutHandler.layoutWithDwindleEngine(
                activeWorkspaces: [fixture.workspaceId]
            )
        }
        XCTAssertEqual(plans.count, 1)
        return plans
    }

    private func layoutEngine(_ fixture: Fixture) {
        let screen = fixture.controller.workspaceManager.monitor(for: fixture.workspaceId)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        fixture.controller.workspaceManager.withEngineMutationScope {
            _ = fixture.engine.calculateLayout(for: fixture.workspaceId, screen: screen)
        }
    }

    private func makeMonitor() -> Monitor {
        Monitor(
            id: .init(displayId: 96_000),
            displayId: 96_000,
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            hasNotch: false,
            name: "Dwindle Disable Tab Groups"
        )
    }

    private func makeController() -> WMController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OmniWMDwindleDisableTabGroupsTests-\(UUID().uuidString)", isDirectory: true)
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
        let controller = WMController(
            settings: settings,
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.workspaceManager.applyMonitorConfigurationChange([makeMonitor()])
        return controller
    }

    private func addWindow(
        pid: pid_t,
        windowId: Int,
        workspaceId: WorkspaceDescriptor.ID,
        controller: WMController
    ) -> WindowToken {
        controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid), windowId: windowId),
            pid: pid,
            windowId: windowId,
            to: workspaceId
        )
    }

    private func blockLayoutRefresh(
        _ controller: WMController,
        workspaceId: WorkspaceDescriptor.ID
    ) -> Task<Void, Never> {
        let blocker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        controller.layoutRefreshController.layoutState.activeRefreshTask = blocker
        controller.layoutRefreshController.layoutState.activeRefresh = .init(
            kind: .immediateRelayout,
            reason: .layoutCommand,
            affectedWorkspaceIds: [workspaceId]
        )
        return blocker
    }

    private func unblockLayoutRefresh(
        _ controller: WMController,
        blocker: Task<Void, Never>
    ) {
        blocker.cancel()
        controller.layoutRefreshController.layoutState.activeRefreshTask = nil
        controller.layoutRefreshController.layoutState.activeRefresh = nil
        controller.layoutRefreshController.layoutState.pendingRefresh = nil
    }
}
