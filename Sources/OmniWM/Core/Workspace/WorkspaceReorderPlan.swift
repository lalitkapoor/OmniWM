// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

enum WorkspaceReorderPlan {
    /// The renames (old name → new name) that move workspace `source` to number `target` and shift every
    /// existing workspace numbered in between by one toward the gap it leaves. Returns nil when the move is
    /// not possible: an unknown source, the same position, or a target outside `1...` the highest number.
    static func renames(existing names: [String], moving source: String, to target: String) -> [String: String]? {
        let numbers = names.compactMap(WorkspaceIDPolicy.workspaceNumber(from:))
        guard let from = WorkspaceIDPolicy.workspaceNumber(from: source),
              let to = WorkspaceIDPolicy.workspaceNumber(from: target),
              from != to,
              numbers.contains(from),
              let highest = numbers.max(),
              to <= highest
        else {
            return nil
        }
        var renames = [source: target]
        for number in numbers where number != from {
            if to < from, (to ..< from).contains(number) {
                renames[String(number)] = String(number + 1)
            } else if to > from, (from + 1 ... to).contains(number) {
                renames[String(number)] = String(number - 1)
            }
        }
        return renames
    }
}
