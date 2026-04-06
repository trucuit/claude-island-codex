//
//  BatchApprovalView.swift
//  ClaudeIsland
//
//  Shown in the notch/chat bar when 2+ tools are pending approval for the same session.
//  Replaces the single-tool ChatApprovalBar when batch mode is active.
//
//  ChatView integration (Phase 3B): In ChatView.swift's approval section (~line 101),
//  replace the `approvalBar(tool:)` call with:
//
//    let pendingCount = viewModel.pendingApprovalCount(for: session.sessionId)
//    if pendingCount > 1 {
//        let tools = viewModel.pendingTools(for: session.sessionId).map { p in
//            PendingToolEntry(id: p.toolUseId, name: p.toolName ?? "unknown", input: p.toolInput)
//        }
//        BatchApprovalView(sessionId: session.sessionId, pendingTools: tools) {
//            // onDecisionMade: no-op here; SessionStore updates via permissionApproved events
//        }
//    } else {
//        approvalBar(tool: tool)
//    }
//

import SwiftUI

/// A pending tool entry for display in the batch approval UI
struct PendingToolEntry: Identifiable {
    let id: String        // toolUseId
    let name: String
    let input: [String: AnyCodable]?
}

/// Shown when 2+ tools await approval simultaneously.
/// Groups entries by tool name for cleaner UX.
struct BatchApprovalView: View {
    let sessionId: String
    let pendingTools: [PendingToolEntry]
    /// Called after user approves/denies so the parent can update state
    let onDecisionMade: () -> Void

    /// Groups: toolName → [entries]
    private var groups: [(name: String, entries: [PendingToolEntry])] {
        var result: [(name: String, entries: [PendingToolEntry])] = []
        var seen: [String: Int] = [:]
        for entry in pendingTools {
            if let idx = seen[entry.name] {
                result[idx].entries.append(entry)
            } else {
                seen[entry.name] = result.count
                result.append((name: entry.name, entries: [entry]))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))
            groupList
            Divider().background(Color.white.opacity(0.1))
            footerButtons
        }
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TerminalColors.amber)

            Text("\(pendingTools.count) tools pending approval")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            ForEach(groups, id: \.name) { group in
                GroupRow(
                    name: group.name,
                    entries: group.entries,
                    onApproveGroup: { approveGroup(group.entries) },
                    onDenyGroup: { denyGroup(group.entries) }
                )
                if group.name != groups.last?.name {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 8) {
            Button(action: denyAll) {
                Text("Deny All")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(TerminalColors.red.opacity(0.18)))
                    .overlay(Capsule().stroke(TerminalColors.red.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: approveAll) {
                Text("Approve All (\(pendingTools.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [TerminalColors.green, TerminalColors.green.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func approveAll() {
        let ids = pendingTools.map(\.id)
        HookSocketServer.shared.respondToMultiplePermissions(toolUseIds: ids, decision: "allow")
        onDecisionMade()
    }

    private func denyAll() {
        let ids = pendingTools.map(\.id)
        HookSocketServer.shared.respondToMultiplePermissions(toolUseIds: ids, decision: "deny")
        onDecisionMade()
    }

    private func approveGroup(_ entries: [PendingToolEntry]) {
        HookSocketServer.shared.respondToMultiplePermissions(
            toolUseIds: entries.map(\.id), decision: "allow"
        )
        onDecisionMade()
    }

    private func denyGroup(_ entries: [PendingToolEntry]) {
        HookSocketServer.shared.respondToMultiplePermissions(
            toolUseIds: entries.map(\.id), decision: "deny"
        )
        onDecisionMade()
    }
}

// MARK: - GroupRow

private struct GroupRow: View {
    let name: String
    let entries: [PendingToolEntry]
    let onApproveGroup: () -> Void
    let onDenyGroup: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Tool name + count badge
            HStack(spacing: 6) {
                Text(MCPToolFormatter.formatToolName(name))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))
                    .lineLimit(1)

                if entries.count > 1 {
                    Text("\(entries.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(TerminalColors.amber))
                }
            }

            Spacer(minLength: 4)

            // Per-group actions
            Button(action: onDenyGroup) {
                Text("Deny")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)

            Button(action: onApproveGroup) {
                Text("Allow")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TerminalColors.green))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
