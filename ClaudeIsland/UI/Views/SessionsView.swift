//
//  SessionsView.swift
//  ClaudeIsland
//
//  Session list with urgency-tiered cards, SF Symbol state indicators, and section headers.
//

import Combine
import AppKit
import SwiftUI

struct SessionsView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var codexMonitor: CodexSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var searchText = ""
    @State private var activeFilter: SessionFilter = .all

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

    private var filteredSessions: [SessionState] {
        sortedInstances.filter { session in
            activeFilter.matches(session) &&
            (searchText.isEmpty ||
             session.projectName.localizedCaseInsensitiveContains(searchText) ||
             session.displayTitle.localizedCaseInsensitiveContains(searchText) ||
             session.cwd.localizedCaseInsensitiveContains(searchText))
        }
    }

    // MARK: - Urgency Groups

    private var approvalSessions: [SessionState] {
        filteredSessions.filter { $0.phase.isWaitingForApproval }
    }

    private var activeSessions: [SessionState] {
        filteredSessions.filter { $0.phase == .processing || $0.phase == .compacting }
    }

    private var quietSessions: [SessionState] {
        filteredSessions.filter {
            $0.phase == .waitingForInput || $0.phase == .idle || $0.phase == .ended
        }
    }

    // MARK: - List

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                SessionSearchBar(searchText: $searchText, activeFilter: $activeFilter)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                if filteredSessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No matching sessions")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    sectionedSessionRows
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var sectionedSessionRows: some View {
        if !approvalSessions.isEmpty {
            sessionSectionHeader("Needs Attention", count: approvalSessions.count, tint: TerminalColors.statusWarning)
            ForEach(Array(approvalSessions.enumerated()), id: \.element.stableId) { index, session in
                sessionRow(session, sectionIndex: index)
            }
        }

        if !activeSessions.isEmpty {
            sessionSectionHeader("Active", count: activeSessions.count, tint: TerminalColors.statusInfo)
            ForEach(Array(activeSessions.enumerated()), id: \.element.stableId) { index, session in
                sessionRow(session, sectionIndex: index)
            }
        }

        if !quietSessions.isEmpty {
            sessionSectionHeader("Recent", count: quietSessions.count, tint: TerminalColors.textTertiary)
            ForEach(Array(quietSessions.enumerated()), id: \.element.stableId) { index, session in
                sessionRow(session, sectionIndex: index)
            }
        }
    }

    private func sessionRow(_ session: SessionState, sectionIndex: Int) -> some View {
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
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        ))
        .animation(
            .spring(response: 0.35, dampingFraction: 0.8)
                .delay(Double(sectionIndex) * 0.035),
            value: session.phase.description
        )
    }

    private func sessionSectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(TypeStyle.badge)
                .tracking(1.0)
                .foregroundColor(tint)

            Text("\(count)")
                .font(TypeStyle.badge)
                .foregroundColor(tint.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        if session.agent == .codex {
            focusCodexApp()
            return
        }

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

    private func focusCodexApp() {
        let bundleId = "com.openai.codex"

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        if let codexURL = URL(string: "codex://") {
            NSWorkspace.shared.open(codexURL)
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

// MARK: - SessionRow

struct SessionRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onOpenLog: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var isYabaiAvailable = false

    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Number of tools simultaneously waiting for approval (from socket server)
    private var batchPendingCount: Int {
        guard isWaitingForApproval && session.agent == .claude else { return 0 }
        return HookSocketServer.shared.pendingPermissionCount(sessionId: session.sessionId)
    }

    // MARK: - Urgency Tier

    private enum UrgencyTier {
        case approval  // waitingForApproval
        case active    // processing, compacting
        case quiet     // waitingForInput, idle, ended
    }

    private var urgencyTier: UrgencyTier {
        switch session.phase {
        case .waitingForApproval: return .approval
        case .processing, .compacting: return .active
        case .waitingForInput, .idle, .ended: return .quiet
        }
    }

    // MARK: - Computed Colors

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
            return TerminalColors.statusInfo
        case .waitingForApproval:
            return TerminalColors.statusWarning
        case .waitingForInput:
            return TerminalColors.statusSuccess
        case .idle, .ended:
            return TerminalColors.textTertiary
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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                stateIndicator

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TerminalColors.textPrimary)
                            .lineLimit(1)

                        sourceBadge
                        statusBadge

                        if batchPendingCount > 1 {
                            batchBadge(count: batchPendingCount)
                        }
                    }

                    summaryText
                }

                Spacer(minLength: 8)
            }

            providerActionLane
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .onTapGesture(count: 2) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background { cardBackground }
        .shadow(color: .black.opacity(isHovered ? 0.32 : 0.2), radius: isHovered ? 16 : 10, y: 8)
        .shadow(color: approvalGlowColor, radius: 14, y: 0)
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        switch urgencyTier {
        case .approval:
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(TerminalColors.surface2)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: Radius.xl,
                        bottomLeadingRadius: Radius.xl,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(TerminalColors.statusWarning)
                    .frame(width: 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .stroke(TerminalColors.statusWarning.opacity(isHovered ? 0.28 : 0.18), lineWidth: 1)
                }

        case .active:
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(TerminalColors.surface2)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: Radius.xl,
                        bottomLeadingRadius: Radius.xl,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(TerminalColors.statusInfo)
                    .frame(width: 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .stroke(TerminalColors.statusInfo.opacity(isHovered ? 0.22 : 0.12), lineWidth: 1)
                }

        case .quiet:
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TerminalColors.surface1.opacity(0.8),
                            TerminalColors.surface0.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .stroke(isHovered ? TerminalColors.strokeDefault : TerminalColors.strokeSubtle, lineWidth: 1)
                }
        }
    }

    private var approvalGlowColor: Color {
        switch urgencyTier {
        case .approval:
            return TerminalColors.statusWarning.opacity(isHovered ? 0.18 : 0.10)
        case .active:
            return TerminalColors.statusInfo.opacity(0.06)
        case .quiet:
            return .clear
        }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        ZStack {
            Circle()
                .fill(phaseTint.opacity(0.14))
                .frame(width: 24, height: 24)

            Circle()
                .stroke(phaseTint.opacity(0.28), lineWidth: 0.5)
                .frame(width: 24, height: 24)

            switch session.phase {
            case .processing, .compacting:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(phaseTint)
                    .symbolEffect(.pulse, options: .repeating)

            case .waitingForApproval:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(phaseTint)
                    .symbolEffect(.pulse, options: .repeating)

            case .waitingForInput:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(phaseTint)

            case .idle:
                Circle()
                    .fill(phaseTint.opacity(0.6))
                    .frame(width: 5, height: 5)

            case .ended:
                Image(systemName: "minus.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(phaseTint)
            }
        }
    }

    // MARK: - Badges

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(phaseTint)
                .frame(width: 4, height: 4)

            Text(phaseLabel.uppercased())
                .font(TypeStyle.badge)
                .tracking(0.5)
        }
        .foregroundColor(phaseTint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(phaseTint.opacity(0.14))
        )
    }

    private func batchBadge(count: Int) -> some View {
        Text("\(count)")
            .font(TypeStyle.badge)
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(TerminalColors.statusWarning)
            )
    }

    /// Source badge dimmed relative to status badge
    private var sourceBadge: some View {
        Text(session.agent.rawValue.uppercased())
            .font(TypeStyle.badge)
            .tracking(0.5)
            .foregroundColor(sourceTint.opacity(0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(sourceTint.opacity(0.08))
            )
    }

    // MARK: - Summary Text

    @ViewBuilder
    private var summaryText: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            VStack(alignment: .leading, spacing: 5) {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.statusWarning.opacity(0.96))
                    .lineLimit(1)

                if isInteractiveTool {
                    Text("This tool needs your response in the terminal.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.textTertiary)
                        .lineLimit(2)
                } else if session.agent == .codex {
                    Text("Codex is waiting for approval inside its own app flow.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.textTertiary)
                        .lineLimit(2)
                } else if let input = session.pendingToolInput, !input.isEmpty {
                    Text(input)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.textTertiary)
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
                            .foregroundColor(TerminalColors.textTertiary)
                            .lineLimit(2)
                    }
                }
            case "user":
                HStack(spacing: 4) {
                    Text("You")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TerminalColors.textSecondary)

                    if let msg = session.lastMessage {
                        Text(msg)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TerminalColors.textTertiary)
                            .lineLimit(2)
                    }
                }
            default:
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.textTertiary)
                        .lineLimit(2)
                }
            }
        } else if let lastMsg = session.lastMessage {
            Text(lastMsg)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.textTertiary)
                .lineLimit(2)
        }
    }

    // MARK: - Action Lane

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
            actionChip(icon: "scope", label: "Focus", isPrimary: true, action: onFocus)
            actionChip(icon: "bubble.left", label: "Chat", isPrimary: false, action: onChat)
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
            .foregroundColor(isPrimary ? .black : TerminalColors.textSecondary)
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
                            : AnyShapeStyle(TerminalColors.interactiveRest)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - InlineApprovalButtons

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

            // Deny: understated
            Button(action: onReject) {
                Text("Deny")
                    .font(TypeStyle.labelMedium)
                    .foregroundColor(TerminalColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TerminalColors.interactiveRest)
                    )
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.84)

            // Allow: green gradient + glow — visually dominant
            Button(action: onApprove) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Allow")
                        .font(TypeStyle.labelMedium)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    TerminalColors.statusSuccess,
                                    TerminalColors.statusSuccess.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: TerminalColors.statusSuccess.opacity(0.25), radius: 6, y: 2)
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

// MARK: - IconButton

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? TerminalColors.textPrimary : TerminalColors.textSecondary)
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

// MARK: - CompactTerminalButton

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
            .foregroundColor(isEnabled ? TerminalColors.textPrimary : TerminalColors.textDisabled)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? TerminalColors.interactiveRest : TerminalColors.interactiveRest.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TerminalButton

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
            .foregroundColor(isEnabled ? .black : TerminalColors.textDisabled)
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
                            : AnyShapeStyle(TerminalColors.interactiveRest)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
