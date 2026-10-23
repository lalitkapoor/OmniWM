// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import SwiftUI

/// Dims a workspace chip while it is dragged and draws the insertion marker beside the chip it would land next to.
private struct WorkspaceBarReorderMarkerModifier: ViewModifier {
    let workspaceId: WorkspaceDescriptor.ID
    let accentColor: Color?

    @Environment(\.workspaceBarOrientation) private var orientation
    @Environment(WorkspaceBarDragPresentation.self) private var drag: WorkspaceBarDragPresentation?

    private var edge: Edge? {
        switch drag?.reorderMarker {
        case .before(workspaceId): orientation.isVertical ? .top : .leading
        case .after(workspaceId): orientation.isVertical ? .bottom : .trailing
        default: nil
        }
    }

    private var alignment: Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .bottom: .bottom
        case nil: .center
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let edge {
                    let isVerticalLine = edge == .leading || edge == .trailing
                    Capsule()
                        .fill(accentColor ?? .accentColor)
                        .frame(width: isVerticalLine ? 2 : nil, height: isVerticalLine ? nil : 2)
                        .offset(
                            x: edge == .leading ? -5 : edge == .trailing ? 5 : 0,
                            y: edge == .top ? -5 : edge == .bottom ? 5 : 0
                        )
                        .allowsHitTesting(false)
                }
            }
            .opacity(drag?.reorderSource == workspaceId ? 0.45 : 1)
    }
}

extension View {
    func workspaceBarReorderMarker(for workspaceId: WorkspaceDescriptor.ID, accentColor: Color?) -> some View {
        modifier(WorkspaceBarReorderMarkerModifier(workspaceId: workspaceId, accentColor: accentColor))
    }
}
