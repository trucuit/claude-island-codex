//
//  ToolCallView.swift
//  ClaudeIsland
//
//  Styled card view for a single tool call: SF Symbol icon chip, status colors,
//  expandable result content, subagent tree for Task tools.
//

import SwiftUI

// MARK: - Tool Call View

struct ToolCallView: View {
    let tool: ToolCallItem
    let sessionId: String

    @State private var pulseOpacity: Double = 0.6
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    private var statusColor: Color {
        switch tool.status {
        case .running:              return TerminalColors.textSecondary
        case .waitingForApproval:   return TerminalColors.statusWarning
        case .success:              return TerminalColors.statusSuccess
        case .error, .interrupted:  return TerminalColors.statusDanger
        }
    }

    private var textColor: Color {
        switch tool.status {
        case .running:              return TerminalColors.textSecondary
        case .waitingForApproval:   return TerminalColors.statusWarning
        case .success:              return TerminalColors.textSecondary
        case .error, .interrupted:  return TerminalColors.statusDanger
        }
    }

    private var hasResult: Bool {
        tool.result != nil || tool.structuredResult != nil
    }

    private var canExpand: Bool {
        tool.name != "Task" && tool.name != "Edit" && hasResult
    }

    private var showContent: Bool {
        tool.name == "Edit" || isExpanded
    }

    private var agentDescription: String? {
        guard tool.name == "AgentOutputTool",
              let agentId = tool.input["agentId"],
              let sessionDescriptions = ChatHistoryManager.shared.agentDescriptions[sessionId] else {
            return nil
        }
        return sessionDescriptions[agentId]
    }

    /// SF Symbol name per tool type.
    private var toolIcon: String {
        switch tool.name {
        case "Read":            return "doc.text"
        case "Write":           return "doc.text.fill"
        case "Edit":            return "pencil.line"
        case "Bash":            return "terminal"
        case "Grep":            return "magnifyingglass"
        case "Glob":            return "folder.magnifyingglass"
        case "WebFetch":        return "globe"
        case "WebSearch":       return "globe.magnifyingglass"
        case "Task":            return "person.2"
        case "TodoWrite":       return "checklist"
        case "TodoRead":        return "checklist"
        case "NotebookEdit":    return "text.book.closed.fill"
        case "AgentOutputTool": return "arrow.triangle.branch"
        default:                return "wrench.and.screwdriver"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            headerRow
            subagentRow
            resultRow
            editDiffRow
        }
        .padding(Spacing.md)
        .background(cardBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if canExpand {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: Spacing.md) {
            // Status-tinted icon chip
            Image(systemName: toolIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(
                    statusColor.opacity(
                        tool.status == .running || tool.status == .waitingForApproval
                            ? pulseOpacity : 0.85
                    )
                )
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(statusColor.opacity(0.10))
                )
                .id(tool.status)
                .onAppear {
                    if tool.status == .running || tool.status == .waitingForApproval {
                        startPulsing()
                    }
                }

            Text(MCPToolFormatter.formatToolName(tool.name))
                .font(TypeStyle.codeMedium)
                .foregroundColor(textColor)
                .fixedSize()

            statusTextView

            Spacer()

            if canExpand && tool.status != .running && tool.status != .waitingForApproval {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TerminalColors.textDisabled)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isExpanded)
            }
        }
    }

    @ViewBuilder
    private var subagentRow: some View {
        if tool.name == "Task" && !tool.subagentTools.isEmpty {
            SubagentToolsList(tools: tool.subagentTools)
                .padding(.leading, 30)
                .padding(.top, Spacing.xxs)
        }
    }

    @ViewBuilder
    private var resultRow: some View {
        if showContent && tool.status != .running && tool.name != "Task" && (hasResult || tool.name == "Edit") {
            ToolResultContent(tool: tool)
                .padding(.leading, 30)
                .padding(.top, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var editDiffRow: some View {
        if tool.name == "Edit" && tool.status == .running {
            EditInputDiffView(input: tool.input)
                .padding(.leading, 30)
                .padding(.top, Spacing.xs)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(TerminalColors.surface1.opacity(isHovering ? 0.85 : 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(
                        isHovering ? TerminalColors.strokeDefault : TerminalColors.strokeSubtle,
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusTextView: some View {
        if tool.name == "Task" && !tool.subagentTools.isEmpty {
            let taskDesc = tool.input["description"] ?? "Running agent..."
            Text("\(taskDesc) (\(tool.subagentTools.count) tools)")
                .font(TypeStyle.bodySmall)
                .foregroundColor(textColor.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        } else if tool.name == "AgentOutputTool", let desc = agentDescription {
            let blocking = tool.input["block"] == "true"
            Text(blocking ? "Waiting: \(desc)" : desc)
                .font(TypeStyle.bodySmall)
                .foregroundColor(textColor.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        } else if MCPToolFormatter.isMCPTool(tool.name) && !tool.input.isEmpty {
            Text(MCPToolFormatter.formatArgs(tool.input))
                .font(TypeStyle.bodySmall)
                .foregroundColor(textColor.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(tool.statusDisplay.text)
                .font(TypeStyle.bodySmall)
                .foregroundColor(textColor.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Helpers

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.15
        }
    }
}
