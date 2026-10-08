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

    /// Resizes `node` along `orientation`, starting with its nearest split on that axis.
    /// When growing and minimum sizes pin that split, the space comes from the next split up
    /// instead, and every pinned split in between keeps its other side at its current size.
    private func resize(
        _ node: DwindleNode,
        by delta: CGFloat,
        orientation: DwindleOrientation,
        state: DwindleWorkspaceState
    ) -> Bool {
        var pinned: [(split: DwindleNode, child: DwindleNode)] = []
        var current = node
        while let parent = current.parent {
            defer { current = parent }
            guard case let .split(splitOrientation, ratio) = parent.kind,
                  splitOrientation == orientation,
                  splitHasTwoVisibleBranches(parent, excluding: state.excludedTokens)
            else { continue }

            let isFirst = current.isFirstChild(of: parent)
            let effective = clampedRatio(ratio, for: parent, state: state)
            let target = clampedRatio(isFirst ? effective + delta : effective - delta, for: parent, state: state)
            let growth = isFirst ? target - effective : effective - target
            guard abs(growth) > 0.0001, (growth > 0) == (delta > 0) else {
                guard delta > 0 else { return false }
                pinned.append((parent, current))
                continue
            }

            let lengthChange = parent.cachedFrame.map { frame in
                axisLength(of: frame, orientation) * (
                    pathFraction(target, isFirst: isFirst) - pathFraction(effective, isFirst: isFirst)
                )
            }
            parent.kind = .split(orientation: orientation, ratio: target)
            if let lengthChange {
                keepOtherSidesFixed(in: pinned, growingBy: lengthChange, orientation: orientation, state: state)
            }
            return true
        }
        return false
    }

    private func keepOtherSidesFixed(
        in pinned: [(split: DwindleNode, child: DwindleNode)],
        growingBy lengthChange: CGFloat,
        orientation: DwindleOrientation,
        state: DwindleWorkspaceState
    ) {
        for (split, child) in pinned {
            guard case let .split(_, ratio) = split.kind,
                  let frame = split.cachedFrame
            else { continue }
            let isFirst = child.isFirstChild(of: split)
            let oldLength = axisLength(of: frame, orientation)
            let newLength = oldLength + lengthChange
            guard newLength > 0 else { continue }
            let otherLength = oldLength * (1 - pathFraction(
                clampedRatio(ratio, for: split, state: state),
                isFirst: isFirst
            ))
            let childFraction = (newLength - otherLength) / newLength
            let firstFraction = isFirst ? childFraction : 1 - childFraction
            split.kind = .split(orientation: orientation, ratio: settings.clampedRatio(2 * firstFraction))
        }
    }

    private func clampedRatio(_ ratio: CGFloat, for split: DwindleNode, state: DwindleWorkspaceState) -> CGFloat {
        clampedRatioRespectingMinimums(
            ratio,
            for: split,
            innerGap: settings.innerGap,
            excludedTokens: state.excludedTokens
        )
    }

    private func pathFraction(_ ratio: CGFloat, isFirst: Bool) -> CGFloat {
        let firstFraction = settings.ratioToFraction(ratio)
        return isFirst ? firstFraction : 1 - firstFraction
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
