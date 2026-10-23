// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import OmniWMIPC

/// A workspace pill in bar order, in screen coordinates.
struct WorkspaceBarReorderSlot: Equatable {
    let id: WorkspaceDescriptor.ID
    let name: String
    let frame: CGRect
}

/// Where the insertion marker for a workspace drag is drawn.
enum WorkspaceBarReorderMarker: Equatable {
    case before(WorkspaceDescriptor.ID)
    case after(WorkspaceDescriptor.ID)
}

struct WorkspaceBarReorderResolution: Equatable {
    /// The workspace number the dragged workspace takes.
    let position: String
    let marker: WorkspaceBarReorderMarker
}

enum WorkspaceBarReorderResolver {
    /// Resolves dropping workspace `source` at `point` among `slots` (in bar order). Returns nil when the drop
    /// would leave the workspace where it is.
    static func resolve(
        source: String,
        at point: CGPoint,
        slots: [WorkspaceBarReorderSlot],
        vertical: Bool
    ) -> WorkspaceBarReorderResolution? {
        guard let sourceNumber = WorkspaceIDPolicy.workspaceNumber(from: source) else { return nil }
        let others = slots.filter { $0.name != source }
        // Screen coordinates grow upward, so a vertical bar runs from high y to low y.
        let insertion = others.count { slot in
            vertical ? point.y < slot.frame.midY : point.x > slot.frame.midX
        }
        if insertion < others.count,
           let next = WorkspaceIDPolicy.workspaceNumber(from: others[insertion].name),
           next < sourceNumber
        {
            return WorkspaceBarReorderResolution(
                position: others[insertion].name,
                marker: .before(others[insertion].id)
            )
        }
        if insertion > 0,
           let previous = WorkspaceIDPolicy.workspaceNumber(from: others[insertion - 1].name),
           previous > sourceNumber
        {
            return WorkspaceBarReorderResolution(
                position: others[insertion - 1].name,
                marker: .after(others[insertion - 1].id)
            )
        }
        return nil
    }
}
