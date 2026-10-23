// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

struct WorkspaceBarPressTracker {
    enum EventKind: Equatable {
        case leftDown
        case leftDragged
        case leftUp
        case rightDown
    }

    enum Decision: Equatable {
        case passThrough
        case consume
        case showMenu(WorkspaceBarHitTarget)
        case moveFocusedWindow(WorkspaceDescriptor.ID)
        case activateWindow(WorkspaceDescriptor.ID, WindowToken)
        case beginDrag(WorkspaceDescriptor.ID, WindowToken)
        case continueDrag
        case endDrag
        case focusWorkspace(WorkspaceDescriptor.ID)
        case beginWorkspaceReorder(WorkspaceDescriptor.ID)
        case continueWorkspaceReorder
        case endWorkspaceReorder
    }

    private enum Press: Equatable {
        case window(WorkspaceDescriptor.ID, WindowToken, origin: CGPoint)
        case workspace(WorkspaceDescriptor.ID, origin: CGPoint)
        case dragging
        case reorderingWorkspace
        case consumedUntilRelease
    }

    static let dragThreshold: CGFloat = 6

    private var press: Press?

    mutating func handle(
        _ kind: EventKind,
        modifiers: NSEvent.ModifierFlags,
        target: WorkspaceBarHitTarget?,
        location: CGPoint = .zero
    ) -> Decision {
        switch kind {
        case .rightDown:
            guard press != .dragging, press != .reorderingWorkspace else { return .consume }
            return target.map(Decision.showMenu) ?? .passThrough
        case .leftDown:
            return handleLeftDown(modifiers: modifiers, target: target, location: location)
        case .leftDragged:
            return handleDrag(location: location)
        case .leftUp:
            defer { press = nil }
            switch press {
            case let .window(workspaceId, token, _):
                return target == .window(workspaceId, token) ? .activateWindow(workspaceId, token) : .consume
            case let .workspace(workspaceId, _):
                return target == .workspace(workspaceId) ? .focusWorkspace(workspaceId) : .consume
            case .dragging:
                return .endDrag
            case .reorderingWorkspace:
                return .endWorkspaceReorder
            case .consumedUntilRelease:
                return .consume
            case nil:
                return .passThrough
            }
        }
    }

    private mutating func handleDrag(location: CGPoint) -> Decision {
        switch press {
        case let .window(workspaceId, token, origin)
            where hypot(location.x - origin.x, location.y - origin.y) >= Self.dragThreshold:
            press = .dragging
            return .beginDrag(workspaceId, token)
        case let .workspace(workspaceId, origin)
            where hypot(location.x - origin.x, location.y - origin.y) >= Self.dragThreshold:
            press = .reorderingWorkspace
            return .beginWorkspaceReorder(workspaceId)
        case .dragging:
            return .continueDrag
        case .reorderingWorkspace:
            return .continueWorkspaceReorder
        case nil:
            return .passThrough
        default:
            return .consume
        }
    }

    mutating func reset() {
        press = nil
    }

    private mutating func handleLeftDown(
        modifiers: NSEvent.ModifierFlags,
        target: WorkspaceBarHitTarget?,
        location: CGPoint
    ) -> Decision {
        press = nil
        guard let target else { return .passThrough }
        if modifiers.contains(.control) {
            press = .consumedUntilRelease
            return .showMenu(target)
        }
        if modifiers.contains(.shift), let workspaceId = target.workspaceId {
            press = .consumedUntilRelease
            return .moveFocusedWindow(workspaceId)
        }
        switch target {
        case let .window(workspaceId, token):
            press = .window(workspaceId, token, origin: location)
            return .consume
        case let .workspace(workspaceId):
            press = .workspace(workspaceId, origin: location)
            return .consume
        case .scratchpad:
            return .passThrough
        }
    }
}
