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

    /// Resizes the window at `leaf` by moving one of its edges along `axis`. Growing pushes the
    /// right edge (bottom edge for height), taking space from the windows on that side, nearest first,
    /// each down to its minimum; shrinking gives the space to the window on that side. Windows on the
    /// other side keep their size. Only when that side has nothing to give (or no window) does the
    /// opposite edge move instead. One step is `delta / 2` of the workspace length on the axis.
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
        // Layout y grows upward, so the bottom neighbor is the first child of a vertical split.
        let preferredNeighborIsFirst = axis == .vertical
        var slots: [ObjectIdentifier: CGFloat] = [:]
        collectSlotLengths(of: state.root, in: rootFrame, axis: axis, into: &slots)
        for neighborIsFirst in [preferredNeighborIsFirst, !preferredNeighborIsFirst] {
            var edit = DwindleEdgeResize(axis: axis, excludedTokens: state.excludedTokens, slots: slots)
            let moved = delta > 0
                ? growEdge(of: leaf, by: amount, neighborIsFirst: neighborIsFirst, edit: &edit)
                : shrinkEdge(of: leaf, by: amount, neighborIsFirst: neighborIsFirst, edit: &edit)
            guard moved > 0.5 else { continue }
            let previousRatios = edit.touchedSplits.map { ($0, $0.kind) }
            guard applyRatios(of: edit) else { continue }
            var updated: [ObjectIdentifier: CGFloat] = [:]
            collectSlotLengths(of: state.root, in: rootFrame, axis: axis, into: &updated)
            let leafChange = (updated[ObjectIdentifier(leaf)] ?? 0) - (slots[ObjectIdentifier(leaf)] ?? 0)
            if delta > 0 ? leafChange > 0.5 : leafChange < -0.5 {
                return true
            }
            for (split, kind) in previousRatios {
                split.kind = kind
            }
        }
        return false
    }

    private func growEdge(
        of leaf: DwindleNode,
        by amount: CGFloat,
        neighborIsFirst: Bool,
        edit: inout DwindleEdgeResize
    ) -> CGFloat {
        var remaining = amount
        var current = leaf
        while remaining > 0.5, let parent = current.parent {
            defer { current = parent }
            guard isResizableSplit(parent, edit: edit),
                  current.isFirstChild(of: parent) != neighborIsFirst,
                  let neighbor = neighborIsFirst ? parent.firstChild() : parent.secondChild()
            else { continue }
            let take = min(remaining, spareLength(of: neighbor, in: parent, edit: edit))
            guard take > 0.5 else { continue }
            change(leaf, upTo: current, by: take, edit: &edit)
            shrink(neighbor, by: take, fromSideFirst: !neighborIsFirst, edit: &edit)
            edit.touch(parent)
            remaining -= take
        }
        return amount - remaining
    }

    private func shrinkEdge(
        of leaf: DwindleNode,
        by amount: CGFloat,
        neighborIsFirst: Bool,
        edit: inout DwindleEdgeResize
    ) -> CGFloat {
        var current = leaf
        while let parent = current.parent {
            defer { current = parent }
            guard isResizableSplit(parent, edit: edit),
                  current.isFirstChild(of: parent) != neighborIsFirst,
                  let neighbor = neighborIsFirst ? parent.firstChild() : parent.secondChild()
            else { continue }
            let give = min(amount, spareLength(of: leaf, in: parent, edit: edit))
            guard give > 0.5 else { return 0 }
            change(leaf, upTo: current, by: -give, edit: &edit)
            grow(neighbor, by: give, fromSideFirst: !neighborIsFirst, edit: &edit)
            edit.touch(parent)
            return give
        }
        return 0
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

    /// Shrinks `node` by `amount`, taking first from the part nearest the moving edge.
    private func shrink(_ node: DwindleNode, by amount: CGFloat, fromSideFirst: Bool, edit: inout DwindleEdgeResize) {
        edit.lengths[ObjectIdentifier(node)] = length(of: node, edit: edit) - amount
        if isResizableSplit(node, edit: edit) {
            edit.touch(node)
        }
        forEachVisibleChild(of: node, edit: edit, fromSideFirst: fromSideFirst) { near, far in
            guard let far else {
                shrink(near, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
                return
            }
            let nearTake = min(amount, spareLength(of: near, in: node, edit: edit))
            shrink(near, by: nearTake, fromSideFirst: fromSideFirst, edit: &edit)
            shrink(far, by: amount - nearTake, fromSideFirst: fromSideFirst, edit: &edit)
        } across: { first, second in
            shrink(first, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
            shrink(second, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
        }
    }

    /// Grows `node` by `amount`, giving all of it to the part nearest the moving edge.
    private func grow(_ node: DwindleNode, by amount: CGFloat, fromSideFirst: Bool, edit: inout DwindleEdgeResize) {
        edit.lengths[ObjectIdentifier(node)] = length(of: node, edit: edit) + amount
        if isResizableSplit(node, edit: edit) {
            edit.touch(node)
        }
        forEachVisibleChild(of: node, edit: edit, fromSideFirst: fromSideFirst) { near, _ in
            grow(near, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
        } across: { first, second in
            grow(first, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
            grow(second, by: amount, fromSideFirst: fromSideFirst, edit: &edit)
        }
    }

    /// Visits `node`'s visible children: `along` for a split on the resize axis (nearest child first,
    /// `far` is nil when only one child is visible), `across` for a perpendicular split.
    private func forEachVisibleChild(
        of node: DwindleNode,
        edit: DwindleEdgeResize,
        fromSideFirst: Bool,
        along: (_ near: DwindleNode, _ far: DwindleNode?) -> Void,
        across: (_ first: DwindleNode, _ second: DwindleNode) -> Void
    ) {
        guard case let .split(orientation, _) = node.kind,
              let first = node.firstChild(),
              let second = node.secondChild()
        else { return }
        let firstVisible = subtreeHasVisibleMember(first, excluding: edit.excludedTokens)
        let secondVisible = subtreeHasVisibleMember(second, excluding: edit.excludedTokens)
        guard firstVisible, secondVisible else {
            if firstVisible || secondVisible {
                along(firstVisible ? first : second, nil)
            }
            return
        }
        if orientation == edit.axis {
            along(fromSideFirst ? first : second, fromSideFirst ? second : first)
        } else {
            across(first, second)
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

    /// How much `node` can shrink inside `split`: down to its minimum size, and never below the
    /// smallest share a split ratio allows.
    private func spareLength(of node: DwindleNode, in split: DwindleNode, edit: DwindleEdgeResize) -> CGFloat {
        let smallestShare = length(of: split, edit: edit) * settings.ratioToFraction(0.1)
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
