//
//  ApprovalRulesView.swift
//  ClaudeIsland
//
//  Settings panel for managing tool auto-approval allowlist.
//

import SwiftUI

struct ApprovalRulesView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var manager = ApprovalRulesManager.shared
    @State private var newToolName: String = ""
    @State private var showDangerousWarning: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            // Back button
            MenuRow(icon: "chevron.left", label: "Back") {
                viewModel.contentType = .menu
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            // Master toggle
            MenuToggleRow(
                icon: "checkmark.shield",
                label: "Auto-Approval",
                isOn: manager.masterEnabled
            ) {
                manager.masterEnabled.toggle()
            }

            if manager.masterEnabled {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                // Tool toggles
                ForEach(manager.allRules(), id: \.name) { rule in
                    toolRow(name: rule.name, enabled: rule.enabled)
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                // Add custom tool
                addCustomToolRow

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                // Reset all
                MenuRow(icon: "trash", label: "Reset All", isDestructive: true) {
                    manager.resetAll()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Tool Toggle Row

    @ViewBuilder
    private func toolRow(name: String, enabled: Bool) -> some View {
        VStack(spacing: 2) {
            MenuToggleRow(
                icon: toolIcon(for: name),
                label: name,
                isOn: enabled
            ) {
                let newEnabled = !enabled
                if newEnabled && ApprovalRulesManager.dangerousTools.contains(name) {
                    showDangerousWarning = name
                }
                manager.setAutoApproved(toolName: name, enabled: newEnabled)
            }

            // Danger warning for risky tools that are enabled
            if enabled && ApprovalRulesManager.dangerousTools.contains(name) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(TerminalColors.amber)
                    Text("Can modify your system")
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.amber.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 2)
            }
        }
    }

    // MARK: - Add Custom Tool Row

    private var addCustomToolRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 16)

            TextField("Custom tool name…", text: $newToolName)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .textFieldStyle(.plain)
                .onSubmit { commitCustomTool() }

            if !newToolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add") { commitCustomTool() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.85))
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func commitCustomTool() {
        manager.addCustomTool(name: newToolName)
        newToolName = ""
    }

    private func toolIcon(for name: String) -> String {
        switch name {
        case "Read":        return "doc.text"
        case "Glob":        return "folder.badge.magnifyingglass"
        case "Grep":        return "magnifyingglass"
        case "Write":       return "pencil"
        case "Edit":        return "square.and.pencil"
        case "Bash":        return "terminal"
        case "WebFetch":    return "network"
        case "WebSearch":   return "safari"
        case "NotebookEdit": return "book"
        case "TodoRead":    return "checklist"
        case "TodoWrite":   return "checklist.checked"
        default:            return "wrench.and.screwdriver"
        }
    }
}
