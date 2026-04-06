//
//  ChatMessageViews.swift
//  ClaudeIsland
//
//  Message type views: MessageItemView, UserMessageView, AssistantMessageView,
//  ThinkingView, InterruptedMessageView, ToolCallView
//

import SwiftUI

// MARK: - Message Item View

struct MessageItemView: View {
    let item: ChatHistoryItem
    let sessionId: String

    var body: some View {
        switch item.type {
        case .user(let text):
            UserMessageView(text: text)
        case .assistant(let text):
            AssistantMessageView(text: text)
        case .toolCall(let tool):
            ToolCallView(tool: tool, sessionId: sessionId)
        case .thinking(let text):
            ThinkingView(text: text)
        case .interrupted:
            InterruptedMessageView()
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 50)

            MarkdownText(text, color: .white, fontSize: 13)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .fill(
                            LinearGradient(
                                colors: [
                                    TerminalColors.brandCool.opacity(0.18),
                                    TerminalColors.brandCool.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xl)
                                .stroke(TerminalColors.brandCool.opacity(0.15), lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Assistant Message

struct AssistantMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ClaudeCrabIcon(size: 10)
                .opacity(0.5)
                .padding(.top, 6)

            MarkdownText(text, color: TerminalColors.textPrimary, fontSize: 13)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(TerminalColors.surface2.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .stroke(TerminalColors.strokeSubtle, lineWidth: 0.5)
                        )
                )

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Thinking View

struct ThinkingView: View {
    let text: String

    @State private var isExpanded = false

    private var canExpand: Bool { text.count > 80 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(TerminalColors.textDisabled)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Thinking")
                    .font(TypeStyle.captionSmall)
                    .foregroundColor(TerminalColors.textTertiary)

                Text(isExpanded ? text : String(text.prefix(80)) + (canExpand ? "..." : ""))
                    .font(TypeStyle.bodySmall)
                    .foregroundColor(TerminalColors.textTertiary)
                    .italic()
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if canExpand {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(TerminalColors.textDisabled)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canExpand {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Interrupted Message

struct InterruptedMessageView: View {
    var body: some View {
        HStack {
            Text("Interrupted")
                .font(TypeStyle.bodyLarge)
                .foregroundColor(TerminalColors.statusDanger)
            Spacer()
        }
    }
}

// ToolCallView lives in ToolCallView.swift
