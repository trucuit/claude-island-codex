//
//  SessionsView.swift
//  ClaudeIsland
//
//  Session list with richer hierarchy and better control affordances
//

import Combine
import AppKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var codexMonitor: CodexSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        if sortedInstances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                TerminalColors.shellCool.opacity(0.34),
                                TerminalColors.shellWarm.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            VStack(spacing: 6) {
                Text("Waiting for Claude or Codex")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text("Run `claude` or `codex` and active sessions will appear here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.46))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        (sessionMonitor.instances + codexMonitor.instances).sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }

            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(sortedInstances) { session in
                    SessionRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onOpenLog: { openLog(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func openLog(_ session: SessionState) {
        if let logPath = session.logPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        }
    }

    private func approveSession(_ session: SessionState) {
        guard session.supportsRemoteApproval else {
            openChat(session)
            return
        }
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        guard session.supportsRemoteApproval else {
            openChat(session)
            return
        }
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        guard session.agent == .claude else { return }
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

struct SessionRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onOpenLog: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    private var phaseLabel: String {
        switch session.phase {
        case .processing: return "Processing"
        case .compacting: return "Compacting"
        case .waitingForApproval: return "Approval"
        case .waitingForInput: return "Ready"
        case .idle: return "Idle"
        case .ended: return "Ended"
        }
    }

    private var phaseTint: Color {
        switch session.phase {
        case .processing, .compacting:
            return TerminalColors.shellWarm
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.green
        case .idle, .ended:
            return .white.opacity(0.55)
        }
    }

    private var sourceTint: Color {
        switch session.agent {
        case .claude:
            return TerminalColors.shellWarm
        case .codex:
            return TerminalColors.shellCool
        }
    }

    private var cardFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isHovered ? 0.095 : 0.07),
                Color.black.opacity(0.26)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                stateIndicator

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(session.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.94))
                            .lineLimit(1)

                        sourceBadge
                        statusBadge
                    }

                    summaryText
                }

                Spacer(minLength: 8)
            }

            providerActionLane
        }
        .padding(14)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(count: 2) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    TerminalColors.cardStrokeStrong.opacity(isHovered ? 1 : 0.75),
                                    TerminalColors.cardStroke,
                                    phaseTint.opacity(isWaitingForApproval ? 0.45 : 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .overlay(alignment: .top) {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    phaseTint.opacity(0.7),
                                    .white.opacity(0.55),
                                    TerminalColors.shellCool.opacity(0.55)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.top, 1)
                        .opacity(0.7)
                }
        }
        .shadow(color: .black.opacity(isHovered ? 0.32 : 0.2), radius: isHovered ? 16 : 10, y: 8)
        .shadow(color: phaseTint.opacity(isWaitingForApproval ? 0.16 : 0.08), radius: 14, y: 0)
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(phaseTint)
                .frame(width: 6, height: 6)

            Text(phaseLabel.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
        }
        .foregroundColor(phaseTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(phaseTint.opacity(0.14))
        )
    }

    private var sourceBadge: some View {
        Text(session.agent.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundColor(sourceTint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(sourceTint.opacity(0.14))
            )
    }

    @ViewBuilder
    private var summaryText: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            VStack(alignment: .leading, spacing: 5) {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.96))
                    .lineLimit(1)

                if isInteractiveTool {
                    Text("This tool needs your response in the terminal.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                } else if session.agent == .codex {
                    Text("Codex is waiting for approval inside its own app flow.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                } else if let input = session.pendingToolInput, !input.isEmpty {
                    Text(input)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                }
            }
        } else if let role = session.lastMessageRole {
            switch role {
            case "tool":
                HStack(spacing: 4) {
                    if let toolName = session.lastToolName {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(TerminalColors.shellCool.opacity(0.82))
                            .lineLimit(1)
                    }

                    if let input = session.lastMessage {
                        Text(input)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.48))
                            .lineLimit(2)
                    }
                }
            case "user":
                HStack(spacing: 4) {
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))

                    if let msg = session.lastMessage {
                        Text(msg)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(2)
                    }
                }
            default:
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
        } else if let lastMsg = session.lastMessage {
            Text(lastMsg)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var providerActionLane: some View {
        Group {
            switch session.agent {
            case .claude:
                claudeActionLane
            case .codex:
                codexActionLane
            }
        }
    }

    @ViewBuilder
    private var codexActionLane: some View {
        HStack(spacing: 8) {
            if isWaitingForApproval {
                actionChip(icon: "bubble.left", label: "Chat", isPrimary: true, action: onChat)
                actionChip(icon: "doc.text.magnifyingglass", label: "Log", isPrimary: false, action: onOpenLog)
            } else {
                actionChip(icon: "bubble.left", label: "Chat", isPrimary: true, action: onChat)
                actionChip(icon: "doc.text", label: "Log", isPrimary: false, action: onOpenLog)
            }
        }
    }

    @ViewBuilder
    private var claudeActionLane: some View {
        if isWaitingForApproval && isInteractiveTool {
            HStack(spacing: 8) {
                actionChip(icon: "bubble.left", label: "Open Chat", isPrimary: false, action: onChat)

                if isYabaiAvailable {
                    TerminalButton(
                        isEnabled: session.isInTmux,
                        onTap: onFocus
                    )
                }
            }
        } else if isWaitingForApproval {
            InlineApprovalButtons(
                onChat: onChat,
                onApprove: onApprove,
                onReject: onReject
            )
        } else {
            HStack(spacing: 8) {
                actionChip(icon: "bubble.left", label: "Chat", isPrimary: true, action: onChat)

                if session.isInTmux && isYabaiAvailable {
                    actionChip(icon: "eye", label: "Focus", isPrimary: false, action: onFocus)
                }

                if session.phase == .idle || session.phase == .waitingForInput {
                    actionChip(icon: "archivebox", label: "Archive", isPrimary: false, action: onArchive)
                }
            }
        }
    }

    private func actionChip(icon: String, label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isPrimary ? .black : .white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isPrimary
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.98), TerminalColors.shellCool.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        ZStack {
            Circle()
                .fill(phaseTint.opacity(0.14))
                .frame(width: 34, height: 34)

            Circle()
                .stroke(phaseTint.opacity(0.28), lineWidth: 1)
                .frame(width: 34, height: 34)

            switch session.phase {
            case .processing, .compacting, .waitingForApproval:
                Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(phaseTint)
                    .onReceive(spinnerTimer) { _ in
                        spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                    }
            case .waitingForInput:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(phaseTint)
            case .idle, .ended:
                Circle()
                    .fill(phaseTint.opacity(0.9))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 8) {
            IconButton(icon: "bubble.left", action: onChat)
                .opacity(showChatButton ? 1 : 0)
                .scaleEffect(showChatButton ? 1 : 0.84)

            Button(action: onReject) {
                Text("Deny")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.84)

            Button(action: onApprove) {
                Text("Allow")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, TerminalColors.shellWarm.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.84)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? .white.opacity(0.92) : .white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isHovered ? TerminalColors.cardHover : TerminalColors.card)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .semibold))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.34))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .bold))
                Text("Terminal")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.42))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isEnabled
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.white, TerminalColors.shellCool.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
