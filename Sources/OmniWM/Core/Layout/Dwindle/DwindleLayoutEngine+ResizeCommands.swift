// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation
import QuartzCore

extension DwindleLayoutEngine {
    @discardableResult
    func resizeSelected(
        by delta: CGFloat,
        orientation targetOrientation: DwindleOrientation,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let selected = selectedNode(in: workspaceId)
        else { return false }
        return resize(selected, by: delta, orientation: targetOrientation, state: state)
    }

    @discardableResult
    func resizeFocusedWindow(by delta: CGFloat, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let selected = selectedNode(in: workspaceId),
              let orientation = firstVisibleSplitAncestor(
                  from: selected,
                  excluding: state.excludedTokens
              )?.split.splitOrientation
        else { return false }
        return resize(selected, by: delta, orientation: orientation, state: state)
    }

    /// Resizes the window at `leaf` by moving its right edge (bottom edge for height) along `axis`.
    /// Growing takes space equally from the windows on that side that can give; shrinking gives the
    /// space equally to them. Windows on the other side never change, so a window with nothing on that
    /// side (or nothing able to give) does not resize. One step is `delta / 2` of the workspace length
    /// on the axis.
    private func resize(
        _ leaf: DwindleNode,
        by delta: CGFloat,
        orientation axis: DwindleOrientation,
        state: DwindleWorkspaceState
    ) -> Bool {
        guard delta != 0,
              let rootFrame = state.root.cachedFrame,
              axisLength(of: rootFrame, axis) > 0
        else { return false }
        let amount = abs(delta) / 2 * axisLength(of: rootFrame, axis)
        var slots: [ObjectIdentifier: CGFloat] = [:]
        collectSlotLengths(of: state.root, in: rootFrame, axis: axis, into: &slots)
        var edit = DwindleEdgeResize(axis: axis, excludedTokens: state.excludedTokens, slots: slots)
        // Layout y grows upward, so the bottom neighbor is the first child of a vertical split.
        let moved = moveEdge(of: leaf, by: amount, growing: delta > 0, neighborIsFirst: axis == .vertical, edit: &edit)
        guard moved > 0.5 else { return false }
        let previousRatios = edit.touchedSplits.map { ($0, $0.kind) }
        guard applyRatios(of: edit) else { return false }
        var updated: [ObjectIdentifier: CGFloat] = [:]
        collectSlotLengths(of: state.root, in: rootFrame, axis: axis, into: &updated)
        let leafChange = (updated[ObjectIdentifier(leaf)] ?? 0) - (slots[ObjectIdentifier(leaf)] ?? 0)
        if delta > 0 ? leafChange > 0.5 : leafChange < -0.5 {
            return true
        }
        for (split, kind) in previousRatios {
            split.kind = kind
        }
        return false
    }

    /// Moves the leaf's edge on the `neighborIsFirst` side. Every column on that side shares the change
    /// equally; when growing, only columns above their minimum give, and a column that runs out passes the
    /// rest of its share to the others. Returns how far the edge moved.
    private func moveEdge(
        of leaf: DwindleNode,
        by amount: CGFloat,
        growing: Bool,
        neighborIsFirst: Bool,
        edit: inout DwindleEdgeResize
    ) -> CGFloat {
        var dividers: [DwindleEdgeDivider] = []
        var current = leaf
        while let parent = current.parent {
            if isResizableSplit(parent, edit: edit),
               current.isFirstChild(of: parent) != neighborIsFirst,
               let neighbor = neighborIsFirst ? parent.firstChild() : parent.secondChild()
            {
                dividers.append(DwindleEdgeDivider(split: parent, pathChild: current, neighbor: neighbor))
            }
            current = parent
        }
        let columns = dividers.map { columnsAlongAxis(in: $0.neighbor, edit: edit) }
        let allColumns = columns.flatMap(\.self)
        guard !allColumns.isEmpty else { return 0 }

        let shares: [CGFloat]
        if growing {
            shares = equalShares(of: amount, from: allColumns, edit: edit)
        } else {
            let give = min(amount, spareLength(of: leaf, edit: edit))
            shares = Array(repeating: -give / CGFloat(allColumns.count), count: allColumns.count)
        }
        let moved = shares.reduce(0, +)
        guard abs(moved) > 0.5 else { return 0 }

        var index = 0
        for (divider, dividerColumns) in zip(dividers, columns) {
            var dividerChange: CGFloat = 0
            for column in dividerColumns {
                resizeColumn(column, by: -shares[index], edit: &edit)
                dividerChange += shares[index]
                index += 1
            }
            recomputeLength(of: divider.neighbor, edit: &edit)
            change(leaf, upTo: divider.pathChild, by: dividerChange, edit: &edit)
            edit.touch(divider.split)
        }
        return abs(moved)
    }

    /// Splits `amount` equally across `columns`, capping each at what it can give and handing the
    /// remainder to the columns that still have room.
    private func equalShares(of amount: CGFloat, from columns: [DwindleNode], edit: DwindleEdgeResize) -> [CGFloat] {
        let spare = columns.map { spareLength(of: $0, edit: edit) }
        var shares = Array(repeating: CGFloat(0), count: columns.count)
        var remaining = amount
        var open = Set(columns.indices.filter { spare[$0] > 0.5 })
        while remaining > 0.5, !open.isEmpty {
            let share = remaining / CGFloat(open.count)
            for index in open.sorted() {
                let take = min(share, spare[index] - shares[index])
                shares[index] += take
                remaining -= take
                if spare[index] - shares[index] <= 0.5 {
                    open.remove(index)
                }
            }
        }
        return shares
    }

    /// The pieces of `node` laid out side by side along the axis. A stack across the axis counts as one.
    private func columnsAlongAxis(in node: DwindleNode, edit: DwindleEdgeResize) -> [DwindleNode] {
        guard case let .split(orientation, _) = node.kind,
              let first = node.firstChild(),
              let second = node.secondChild()
        else { return [node] }
        let firstVisible = subtreeHasVisibleMember(first, excluding: edit.excludedTokens)
        let secondVisible = subtreeHasVisibleMember(second, excluding: edit.excludedTokens)
        guard firstVisible, secondVisible else {
            return firstVisible || secondVisible
                ? columnsAlongAxis(in: firstVisible ? first : second, edit: edit)
                : []
        }
        guard orientation == edit.axis else { return [node] }
        return columnsAlongAxis(in: first, edit: edit) + columnsAlongAxis(in: second, edit: edit)
    }

    /// Changes a column's length; every part of a stack across the axis changes with it, and the
    /// side-by-side pieces inside each part share the change equally.
    private func resizeColumn(_ column: DwindleNode, by change: CGFloat, edit: inout DwindleEdgeResize) {
        edit.lengths[ObjectIdentifier(column)] = length(of: column, edit: edit) + change
        guard case .split = column.kind,
              let first = column.firstChild(),
              let second = column.secondChild()
        else { return }
        for child in [first, second] where subtreeHasVisibleMember(child, excluding: edit.excludedTokens) {
            let parts = columnsAlongAxis(in: child, edit: edit)
            let shares = change < 0
                ? equalShares(of: -change, from: parts, edit: edit).map { -$0 }
                : Array(repeating: change / CGFloat(parts.count), count: parts.count)
            for (part, share) in zip(parts, shares) where part !== column {
                resizeColumn(part, by: share, edit: &edit)
            }
            recomputeLength(of: child, edit: &edit)
        }
    }

    /// Recomputes split lengths inside `node` from its children after their lengths changed.
    @discardableResult
    private func recomputeLength(of node: DwindleNode, edit: inout DwindleEdgeResize) -> CGFloat {
        guard case let .split(orientation, _) = node.kind,
              let first = node.firstChild(),
              let second = node.secondChild()
        else { return length(of: node, edit: edit) }
        let firstVisible = subtreeHasVisibleMember(first, excluding: edit.excludedTokens)
        let secondVisible = subtreeHasVisibleMember(second, excluding: edit.excludedTokens)
        guard firstVisible, secondVisible, orientation == edit.axis else {
            if firstVisible || secondVisible, orientation == edit.axis || !(firstVisible && secondVisible) {
                return recomputeLength(of: firstVisible ? first : second, edit: &edit)
            }
            return length(of: node, edit: edit)
        }
        let total = recomputeLength(of: first, edit: &edit) + recomputeLength(of: second, edit: &edit)
        edit.lengths[ObjectIdentifier(node)] = total
        edit.touch(node)
        return total
    }

    /// Changes the length of every node from `leaf` up to `top` by `change`; the splits in between keep
    /// their other side's length, so the whole change lands on `leaf`.
    private func change(_ leaf: DwindleNode, upTo top: DwindleNode, by change: CGFloat, edit: inout DwindleEdgeResize) {
        var node = leaf
        while true {
            edit.lengths[ObjectIdentifier(node)] = length(of: node, edit: edit) + change
            guard node !== top, let parent = node.parent else { return }
            if isResizableSplit(parent, edit: edit) {
                edit.touch(parent)
            }
            node = parent
        }
    }

    private func applyRatios(of edit: DwindleEdgeResize) -> Bool {
        var changed = false
        for node in edit.touchedSplits {
            guard case let .split(orientation, ratio) = node.kind,
                  let first = node.firstChild(),
                  let second = node.secondChild()
            else { continue }
            let firstLength = length(of: first, edit: edit)
            let total = firstLength + length(of: second, edit: edit)
            guard total > 0 else { continue }
            let newRatio = settings.clampedRatio(2 * firstLength / total)
            guard abs(newRatio - ratio) > 0.0001 else { continue }
            node.kind = .split(orientation: orientation, ratio: newRatio)
            changed = true
        }
        return changed
    }

    private func isResizableSplit(_ node: DwindleNode, edit: DwindleEdgeResize) -> Bool {
        node.splitOrientation == edit.axis && splitHasTwoVisibleBranches(node, excluding: edit.excludedTokens)
    }

    private func length(of node: DwindleNode, edit: DwindleEdgeResize) -> CGFloat {
        edit.lengths[ObjectIdentifier(node)] ?? edit.slots[ObjectIdentifier(node)] ?? 0
    }

    private func minimumLength(of node: DwindleNode, edit: DwindleEdgeResize) -> CGFloat {
        edit.axis == .horizontal ? node.projectedMinSize.width : node.projectedMinSize.height
    }

    /// How much `node` can shrink: down to its minimum size, and never below the smallest share a
    /// split ratio allows inside its parent.
    private func spareLength(of node: DwindleNode, edit: DwindleEdgeResize) -> CGFloat {
        let smallestShare = node.parent.map { length(of: $0, edit: edit) * settings.ratioToFraction(0.1) } ?? 0
        return max(0, length(of: node, edit: edit) - max(minimumLength(of: node, edit: edit), smallestShare))
    }

    /// Slot lengths from the current ratios, split exactly as the layout pass splits them, so repeated
    /// commands stay consistent before the next relayout runs.
    private func collectSlotLengths(
        of node: DwindleNode,
        in rect: CGRect,
        axis: DwindleOrientation,
        into slots: inout [ObjectIdentifier: CGFloat]
    ) {
        slots[ObjectIdentifier(node)] = axisLength(of: rect, axis)
        guard case let .split(orientation, ratio) = node.kind,
              let first = node.firstChild(),
              let second = node.secondChild()
        else { return }
        let firstVisible = first.projectedVisibleLeafCount > 0
        let secondVisible = second.projectedVisibleLeafCount > 0
        guard firstVisible, secondVisible else {
            if firstVisible || secondVisible {
                collectSlotLengths(of: firstVisible ? first : second, in: rect, axis: axis, into: &slots)
            }
            return
        }
        let (firstRect, secondRect) = splitRect(
            rect,
            orientation: orientation,
            ratio: ratio,
            minimums: (first: first.projectedMinSize, second: second.projectedMinSize)
        )
        collectSlotLengths(of: first, in: firstRect, axis: axis, into: &slots)
        collectSlotLengths(of: second, in: secondRect, axis: axis, into: &slots)
    }

    private func axisLength(of frame: CGRect, _ orientation: DwindleOrientation) -> CGFloat {
        orientation == .horizontal ? frame.width : frame.height
    }

    @discardableResult
    func balanceSizes(in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId) else { return false }
        return balanceSizesRecursive(state.root, excludedTokens: state.excludedTokens)
    }

    private func balanceSizesRecursive(
        _ node: DwindleNode,
        excludedTokens: Set<WindowToken>
    ) -> Bool {
        guard case let .split(orientation, ratio) = node.kind else { return false }
        let first = node.firstChild()
        let second = node.secondChild()
        let firstVisible = first.map { subtreeHasVisibleMember($0, excluding: excludedTokens) } ?? false
        let secondVisible = second.map { subtreeHasVisibleMember($0, excluding: excludedTokens) } ?? false
        var changed = false
        if firstVisible, secondVisible {
            let target = clampedRatioRespectingMinimums(
                1.0,
                for: node,
                innerGap: settings.innerGap,
                excludedTokens: excludedTokens
            )
            changed = ratio != target
            if changed {
                node.kind = .split(orientation: orientation, ratio: target)
            }
        }
        if firstVisible, let first {
            changed = balanceSizesRecursive(first, excludedTokens: excludedTokens) || changed
        }
        if secondVisible, let second {
            changed = balanceSizesRecursive(second, excludedTokens: excludedTokens) || changed
        }
        return changed
    }

    @discardableResult
    func swapSplit(in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let selected = selectedNode(in: workspaceId),
              let parent = firstVisibleSplitAncestor(
                  from: selected,
                  excluding: state.excludedTokens
              )?.split,
              parent.children.count == 2 else { return false }

        let first = parent.children[0]
        let second = parent.children[1]
        parent.children = [second, first]
        return true
    }

    @discardableResult
    func cycleSplitRatio(forward: Bool, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        assertSanctionedMutation()
        guard let state = existingState(for: workspaceId),
              let selected = selectedNode(in: workspaceId),
              let ancestor = firstVisibleSplitAncestor(from: selected, excluding: state.excludedTokens),
              case let .split(orientation, currentRatio) = ancestor.split.kind else { return false }

        let presets = DwindleSettings.splitRatioPresets
        let isFirst = ancestor.child.isFirstChild(of: ancestor.split)
        let focusedRatio = isFirst ? currentRatio : 2 - currentRatio
        let currentIndex = presets.indices
            .min { abs(presets[$0] - focusedRatio) < abs(presets[$1] - focusedRatio) } ?? 1
        let preset = presets[(currentIndex + (forward ? 1 : presets.count - 1)) % presets.count]
        let newRatio = clampedRatioRespectingMinimums(
            isFirst ? preset : 2 - preset,
            for: ancestor.split,
            innerGap: settings.innerGap,
            excludedTokens: state.excludedTokens
        )
        guard newRatio != currentRatio else { return false }
        ancestor.split.kind = .split(orientation: orientation, ratio: newRatio)
        return true
    }
}

/// Pending edge-resize lengths along one axis, applied to split ratios at the end.
private struct DwindleEdgeResize {
    let axis: DwindleOrientation
    let excludedTokens: Set<WindowToken>
    let slots: [ObjectIdentifier: CGFloat]
    var lengths: [ObjectIdentifier: CGFloat] = [:]
    private(set) var touchedSplits: [DwindleNode] = []

    mutating func touch(_ split: DwindleNode) {
        if !touchedSplits.contains(where: { $0 === split }) {
            touchedSplits.append(split)
        }
    }
}

/// A split whose divider is the moving edge: `pathChild` holds the resized window, `neighbor` is the
/// side that gives or receives space.
private struct DwindleEdgeDivider {
    let split: DwindleNode
    let pathChild: DwindleNode
    let neighbor: DwindleNode
}
