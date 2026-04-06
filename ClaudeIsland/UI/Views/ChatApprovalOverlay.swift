//
//  ChatApprovalOverlay.swift
//  ClaudeIsland
//
//  ChatApprovalBar — animated approval/deny bar shown when Claude requests tool permission.
//  Allow button has green gradient + glow to communicate urgency and visual hierarchy.
//

import SwiftUI

// MARK: - Chat Approval Bar

/// Approval bar for the chat view with animated buttons and green glow Allow action.
struct ChatApprovalBar: View {
    let tool: String
    let toolInput: String?
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var showContent = false
    @State private var showAllowButton = false
    @State private var showDenyButton = false
    @State private var isAllowHovered = false
    @State private var isDenyHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Warning icon + tool info
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TerminalColors.statusWarning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(MCPToolFormatter.formatToolName(tool))
                        .font(TypeStyle.codeMedium)
                        .foregroundColor(TerminalColors.statusWarning)
                    if let input = toolInput {
                        Text(input)
                            .font(TypeStyle.bodySmall)
                            .foregroundColor(TerminalColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(x: showContent ? 0 : -10)

            Spacer()

            // Deny button — understated
            Button { onDeny() } label: {
                Text("Deny")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDenyHovered ? TerminalColors.textPrimary : TerminalColors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isDenyHovered ? TerminalColors.interactiveHover : TerminalColors.interactiveRest)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isDenyHovered = $0 }
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            // Allow button — green gradient + glow
            Button { onApprove() } label: {
                Text("Allow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        TerminalColors.statusSuccess,
                                        TerminalColors.statusSuccess.opacity(0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: TerminalColors.statusSuccess.opacity(isAllowHovered ? 0.55 : 0.35),
                                radius: isAllowHovered ? 10 : 6,
                                x: 0,
                                y: 2
                            )
                    )
                    .scaleEffect(isAllowHovered ? 1.04 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isAllowHovered = h
                }
            }
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color.black.opacity(0.25)
                LinearGradient(
                    colors: [TerminalColors.statusWarning.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.12)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.20)) {
                showAllowButton = true
            }
        }
    }
}
