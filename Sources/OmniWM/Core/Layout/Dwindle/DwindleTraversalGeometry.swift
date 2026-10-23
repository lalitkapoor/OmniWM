// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import CoreGraphics
import Foundation

struct DwindleTraversalPosition {
    let node: DwindleNode
    let rect: CGRect
    let boundaryEdges: ResizeEdge
}

struct DwindleTreeProjection {
    let tilingArea: CGRect
    let excludedTokens: Set<WindowToken>
}

enum DwindleNeighborMeasurement {
    case gappedFrames
    case structuralRects
}

enum DwindleNeighborTieBreak {
    case treeOrder
    case topmostOrLeftmost
    /// Among the tiles beside the current window, the topmost for Left/Right and the leftmost for
    /// Up/Down, regardless of how much each overlaps. Layout y grows upward.
    case readingOrder
}

struct DwindleNavigationSearch {
    let current: DwindleNode
    let currentFrame: CGRect
    let direction: Direction
    let innerGap: CGFloat
    let projection: DwindleTreeProjection
    let measurement: DwindleNeighborMeasurement
    let tieBreak: DwindleNeighborTieBreak
}

struct DwindleNavigationCandidate {
    let handle: WindowToken
    let overlap: CGFloat
    let frame: CGRect

    func isPreferred(
        over other: DwindleNavigationCandidate,
        direction: Direction,
        tieBreak: DwindleNeighborTieBreak
    ) -> Bool {
        switch tieBreak {
        case .treeOrder:
            return overlap > other.overlap
        case .readingOrder:
            switch direction {
            case .left,
                 .right:
                return frame.maxY > other.frame.maxY
            case .up,
                 .down:
                return frame.minX < other.frame.minX
            }
        case .topmostOrLeftmost:
            let tolerance: CGFloat = 0.5
            if abs(overlap - other.overlap) > tolerance {
                return overlap > other.overlap
            }
            switch direction {
            case .left,
                 .right:
                return frame.maxY > other.frame.maxY + tolerance
            case .up,
                 .down:
                return frame.minX < other.frame.minX - tolerance
            }
        }
    }
}

enum DwindleProjectedBranches {
    case none
    case single(DwindleTraversalPosition)
    case split(DwindleTraversalPosition, DwindleTraversalPosition)
}
