// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

extension WorkspaceBarManager {
    func configureReorderController(controller: WMController) {
        reorderController.onDraggingChanged = { [weak self] in self?.refreshAutoHide() }
        reorderController.layoutProvider = { [weak self] workspaceId in
            self?.reorderLayout(containing: workspaceId)
        }
        reorderController.commit = { [weak controller] source, position in
            controller?.reorderWorkspace(named: source, toPosition: position) == .executed
        }
        reorderController.makeGhost = { [weak controller] in
            controller.map { WorkspaceBarDragGhost(icon: nil, ownedWindowRegistry: $0.ownedWindowRegistry) }
        }
    }

    /// The workspace pills of the bar island that shows `workspaceId`, in bar order and screen coordinates.
    private func reorderLayout(containing workspaceId: WorkspaceDescriptor.ID) -> WorkspaceBarReorderController
        .Layout?
    {
        for instance in barsByMonitor.values {
            for island in [instance.primary] + (instance.secondary.map { [$0] } ?? []) {
                let items = island.slice.items(in: instance.model.snapshot)
                guard items.contains(where: { $0.id == workspaceId }) else { continue }
                let slots = items.compactMap { item -> WorkspaceBarReorderSlot? in
                    guard let local = island.interaction.frames[.workspace(item.id)],
                          let frame = island.hostingView.workspaceBarScreenRect(forLocalRect: local)
                    else {
                        return nil
                    }
                    return WorkspaceBarReorderSlot(id: item.id, name: item.rawName, frame: frame)
                }
                return WorkspaceBarReorderController.Layout(
                    slots: slots,
                    vertical: instance.model.snapshot.orientation.isVertical
                )
            }
        }
        return nil
    }
}
