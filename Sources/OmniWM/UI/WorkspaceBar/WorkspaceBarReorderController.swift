// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import AppKit

/// Drags a workspace pill to a new position in its bar. Dropping it takes the number shown by the
/// insertion marker; the workspaces in between shift by one.
@MainActor
final class WorkspaceBarReorderController {
    struct Layout {
        let slots: [WorkspaceBarReorderSlot]
        let vertical: Bool
    }

    private struct Session {
        let source: WorkspaceBarReorderSlot
        let layout: Layout
        let ghost: WorkspaceBarDragGhost?
        var resolution: WorkspaceBarReorderResolution?
    }

    let presentation: WorkspaceBarDragPresentation
    var layoutProvider: (WorkspaceDescriptor.ID) -> Layout? = { _ in nil }
    var commit: (_ source: String, _ position: String) -> Bool = { _, _ in false }
    var makeGhost: () -> WorkspaceBarDragGhost? = { nil }
    var onDraggingChanged: (() -> Void)?
    private let escapeMonitor = PanelDismissalMonitor()
    private var session: Session?

    init(presentation: WorkspaceBarDragPresentation) {
        self.presentation = presentation
    }

    var isDragging: Bool {
        session != nil
    }

    func begin(workspaceId: WorkspaceDescriptor.ID, at point: CGPoint) {
        cancel()
        guard let layout = layoutProvider(workspaceId),
              let source = layout.slots.first(where: { $0.id == workspaceId })
        else {
            return
        }
        let ghost = makeGhost()
        session = Session(source: source, layout: layout, ghost: ghost)
        presentation.reorderSource = workspaceId
        onDraggingChanged?()
        update(at: point)
        if let ghost {
            escapeMonitor.start(
                panels: [ghost],
                isExemptWindow: { _ in true },
                onEscape: { [weak self] in self?.cancel() },
                onDismiss: { [weak self] in self?.cancel() }
            )
        }
    }

    func update(at point: CGPoint) {
        guard var session else { return }
        let resolution = WorkspaceBarReorderResolver.resolve(
            source: session.source.name,
            at: point,
            slots: session.layout.slots,
            vertical: session.layout.vertical
        )
        session.resolution = resolution
        self.session = session
        if presentation.reorderMarker != resolution?.marker {
            presentation.reorderMarker = resolution?.marker
        }
        let label = resolution.map { String(localized: "Move to workspace \($0.position)") }
            ?? String(localized: "Workspace \(session.source.name)")
        session.ghost?.update(label: label, isValid: resolution != nil)
        session.ghost?.moveTo(cursorLocation: point)
    }

    @discardableResult
    func end(at point: CGPoint) -> Bool {
        update(at: point)
        guard let session else { return false }
        let committed = session.resolution.map { commit(session.source.name, $0.position) } ?? false
        finish()
        return committed
    }

    func cancel() {
        guard session != nil else { return }
        finish()
    }

    private func finish() {
        escapeMonitor.stop()
        session?.ghost?.destroy()
        session = nil
        presentation.reorderSource = nil
        presentation.reorderMarker = nil
        onDraggingChanged?()
    }
}
