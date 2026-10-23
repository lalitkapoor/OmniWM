// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit
import Foundation
import OmniWMIPC
import QuartzCore

extension WorkspaceManager {
    func updateWorkspace(_ workspaceId: WorkspaceDescriptor.ID, update: (inout WorkspaceDescriptor) -> Void) {
        guard let result = workspaceCatalog.updateWorkspace(workspaceId, update: update) else { return }
        invalidateWorkspaceProjectionCaches()
        if result.previous != result.current {
            noteInvalidation(workspaceId: workspaceId, domains: [.workspace, .layout])
            schedulePersistedWindowRestoreCatalogSave()
        }
    }

    /// Moves workspace `source` to number `target`, shifting the workspaces in between by one. Windows,
    /// layout trees and focus history follow the contents (they are keyed by workspace id); each moved
    /// workspace's settings row is renamed with it, so its layout type, display name and monitor move too.
    /// Returns the renamed workspaces, or nil when the move is not possible.
    func reorderWorkspace(named source: String, toPosition target: String) -> [WorkspaceDescriptor.ID]? {
        let descriptors = sortedWorkspaces()
        guard let renames = WorkspaceReorderPlan.renames(
            existing: descriptors.map(\.name),
            moving: source,
            to: target
        ) else {
            return nil
        }
        var newNames: [WorkspaceDescriptor.ID: String] = [:]
        for descriptor in descriptors {
            if let name = renames[descriptor.name] {
                newNames[descriptor.id] = name
            }
        }
        workspaceCatalog.renameWorkspaces(newNames)
        settings.workspaces.configurations = settings.workspaces.configurations.map { configuration in
            var configuration = configuration
            if let name = renames[configuration.name] {
                configuration.name = name
            }
            return configuration
        }.sorted { $0.sortOrder < $1.sortOrder }
        invalidateWorkspaceProjectionCaches()
        for id in newNames.keys {
            noteInvalidation(workspaceId: id, domains: [.workspace, .layout, .focus])
        }
        schedulePersistedWindowRestoreCatalogSave()
        notifySessionStateChanged()
        return Array(newNames.keys)
    }

    func createWorkspace(
        named name: String,
        assignedMonitorPoint: CGPoint? = nil,
        requiresConfiguration: Bool = true
    ) -> WorkspaceDescriptor.ID? {
        guard let rawID = WorkspaceIDPolicy.normalizeRawID(name) else { return nil }
        guard !requiresConfiguration || configuredWorkspaceNameSet().contains(rawID) else { return nil }
        let workspace = WorkspaceDescriptor(name: rawID, assignedMonitorPoint: assignedMonitorPoint)
        workspaceCatalog.insertWorkspace(workspace)
        invalidateWorkspaceProjectionCaches()
        noteInvalidation(workspaceId: workspace.id, domains: [.workspace, .layout, .focus])
        settings.reconcileWorkspaceNumberHotkeys()
        return workspace.id
    }
}
