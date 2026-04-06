//
//  ChatView.swift
//  ClaudeIsland
//
//  Main chat container: scroll list, header, loading/empty states, autoscroll logic.
//  Extracted views: ChatMessageViews, ChatInputBar, ChatApprovalOverlay, SubagentTreeView
//

import AppKit
import Combine
import SwiftUI

struct ChatView: View {
    let sessionId: String
    let initialSession: SessionState
    let claudeMonitor: ClaudeSessionMonitor
    let codexMonitor: CodexSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    // Internal (not private) so ChatViewActions extension can access them
    @State var inputText: String = ""
    @State var history: [ChatHistoryItem] = []
    @State var session: SessionState
    @State var isLoading: Bool = true
    @State var hasLoadedOnce: Bool = false
    @State var shouldScrollToBottom: Bool = false
    @State var isAutoscrollPaused: Bool = false
    @State var newMessageCount: Int = 0
    @State var previousHistoryCount: Int = 0
    @FocusState var isInputFocused: Bool

    init(
        sessionId: String,
        initialSession: SessionState,
        claudeMonitor: ClaudeSessionMonitor,
        codexMonitor: CodexSessionMonitor,
        viewModel: NotchViewModel
    ) {
        self.sessionId = sessionId
        self.initialSession = initialSession
        self.claudeMonitor = claudeMonitor
        self.codexMonitor = codexMonitor
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._session = State(initialValue: initialSession)

        // Initialize from cache if available (prevents loading flicker on view recreation)
        let cachedHistory: [ChatHistoryItem]
        let alreadyLoaded: Bool
        if initialSession.agent == .claude {
            cachedHistory = ChatHistoryManager.shared.history(for: sessionId)
            alreadyLoaded = !cachedHistory.isEmpty
        } else {
            cachedHistory = initialSession.chatItems
            alreadyLoaded = true
        }
        self._history = State(initialValue: cachedHistory)
        self._isLoading = State(initialValue: !alreadyLoaded)
        self._hasLoadedOnce = State(initialValue: alreadyLoaded)
    }

    /// Whether we're waiting for approval
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Extract the tool name if waiting for approval
    private var approvalTool: String? {
        session.phase.approvalToolName
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                chatHeader

                // Messages
                if isLoading {
                    loadingState
                } else if history.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                // Approval bar, interactive prompt, or Input bar
                if let tool = approvalTool {
                    if session.agent == .codex {
                        codexApprovalBar(tool: tool)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    } else if tool == "AskUserQuestion" {
                        // Interactive tools - show prompt to answer in terminal
                        interactivePromptBar
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    } else {
                        approvalBar(tool: tool)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }
                } else {
                    Group {
                        if session.agent == .codex {
                            codexReadOnlyBar
                        } else {
                            inputBar
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isWaitingForApproval)
        .animation(nil, value: viewModel.status)
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true

            if session.agent == .codex {
                history = session.chatItems
                isLoading = false
                return
            }

            if ChatHistoryManager.shared.isLoaded(sessionId: sessionId) {
                history = ChatHistoryManager.shared.history(for: sessionId)
                isLoading = false
                return
            }

            await ChatHistoryManager.shared.loadFromFile(sessionId: sessionId, cwd: session.cwd)
            history = ChatHistoryManager.shared.history(for: sessionId)

            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
        .onReceive(ChatHistoryManager.shared.$histories) { histories in
            guard session.agent == .claude else { return }
            if let newHistory = histories[sessionId] {
                let countChanged = newHistory.count != history.count
                let lastItemChanged = newHistory.last?.id != history.last?.id
                if countChanged || lastItemChanged || newHistory != history {
                    if isAutoscrollPaused && newHistory.count > previousHistoryCount {
                        let addedCount = newHistory.count - previousHistoryCount
                        newMessageCount += addedCount
                        previousHistoryCount = newHistory.count
                    }

                    history = newHistory

                    if !isAutoscrollPaused && countChanged {
                        shouldScrollToBottom = true
                    }

                    if isLoading && !newHistory.isEmpty {
                        isLoading = false
                    }
                }
            } else if hasLoadedOnce {
                // Session was loaded but is now gone (removed via /clear) - navigate back
                viewModel.exitChat()
            }
        }
        .onReceive(claudeMonitor.$instances) { sessions in
            guard session.agent == .claude else { return }
            if let updated = sessions.first(where: { $0.sessionId == sessionId }),
               updated != session {
                let wasWaiting = isWaitingForApproval
                session = updated
                let isNowProcessing = updated.phase == .processing

                if wasWaiting && isNowProcessing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        shouldScrollToBottom = true
                    }
                }
            }
        }
        .onReceive(codexMonitor.$instances) { sessions in
            guard session.agent == .codex else { return }
            if let updated = sessions.first(where: { $0.sessionId == sessionId }),
               updated != session {
                session = updated
                history = updated.chatItems
                if !isAutoscrollPaused {
                    shouldScrollToBottom = true
                }
                if isLoading {
                    isLoading = false
                }
            }
        }
        .onChange(of: canSendMessages) { _, canSend in
            if canSend && !isInputFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isInputFocused = true
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if canSendMessages {
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - Header

    @State private var isHeaderHovered = false

    /// Subtle tint color reflecting the current session phase.
    private var phaseTintForSession: Color {
        switch session.phase {
        case .processing:           return TerminalColors.brandWarm
        case .compacting:           return TerminalColors.brandWarm
        case .waitingForApproval:   return TerminalColors.statusWarning
        case .waitingForInput:      return TerminalColors.statusSuccess
        case .idle:                 return TerminalColors.brandCool
        case .ended:                return TerminalColors.textTertiary
        }
    }

    /// Inline phase pill displayed in the header alongside the session title.
    private var phasePill: some View {
        let label: String
        let tint: Color
        switch session.phase {
        case .processing:           label = "Processing"; tint = TerminalColors.brandWarm
        case .compacting:           label = "Compacting"; tint = TerminalColors.brandWarm
        case .waitingForApproval:   label = "Approval";  tint = TerminalColors.statusWarning
        case .waitingForInput:      label = "Ready";     tint = TerminalColors.statusSuccess
        case .idle:                 label = "Idle";      tint = TerminalColors.textTertiary
        case .ended:                label = "Ended";     tint = TerminalColors.textTertiary
        }
        return Text(label.uppercased())
            .font(TypeStyle.badge)
            .tracking(0.5)
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
    }

    private var chatHeader: some View {
        Button {
            viewModel.exitChat()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHeaderHovered ? TerminalColors.textPrimary : TerminalColors.textSecondary)
                    .frame(width: 24, height: 24)

                Text(session.displayTitle)
                    .font(TypeStyle.displayMedium)
                    .foregroundColor(isHeaderHovered ? TerminalColors.textPrimary : .white.opacity(0.85))
                    .lineLimit(1)

                // Phase pill — only for Claude sessions
                if session.agent == .claude {
                    phasePill
                }

                if session.agent == .codex {
                    codexReadOnlyBadge
                }

                Spacer()

                if session.agent == .codex {
                    codexHeaderButton
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isHeaderHovered ? TerminalColors.interactiveHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [phaseTintForSession.opacity(0.06), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [fadeColor.opacity(0.7), fadeColor.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: 24)
            .allowsHitTesting(false)
        }
        .zIndex(1)
    }

    private var codexReadOnlyBadge: some View {
        Text("CODEX READ-ONLY")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundColor(TerminalColors.shellCool)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(TerminalColors.shellCool.opacity(0.14))
            )
    }

    private var codexHeaderButton: some View {
        Button {
            continueInCodex()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                Text("Continue")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white.opacity(isHeaderHovered ? 0.95 : 0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(TerminalColors.shellCool.opacity(isHeaderHovered ? 0.22 : 0.14))
            )
        }
        .buttonStyle(.plain)
    }

    /// Whether the session is currently processing
    private var isProcessing: Bool {
        session.phase == .processing || session.phase == .compacting
    }

    /// Get the last user message ID for stable text selection per turn
    private var lastUserMessageId: String {
        for item in history.reversed() {
            if case .user = item.type {
                return item.id
            }
        }
        return ""
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                .scaleEffect(0.8)
            Text("Loading messages...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("No messages yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    /// Background color for fade gradients
    private let fadeColor = Color(red: 0.00, green: 0.00, blue: 0.00)

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")

                    if isProcessing {
                        ProcessingIndicatorView(turnId: lastUserMessageId)
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -4)),
                                removal: .opacity
                            ))
                    }

                    ForEach(history.reversed()) { item in
                        MessageItemView(item: item, sessionId: sessionId)
                            .padding(.horizontal, 16)
                            .scaleEffect(x: 1, y: -1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isProcessing)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: history.count)
            }
            .scaleEffect(x: 1, y: -1)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < 50
            } action: { wasAtBottom, isNowAtBottom in
                if wasAtBottom && !isNowAtBottom {
                    pauseAutoscroll()
                } else if !wasAtBottom && isNowAtBottom && isAutoscrollPaused {
                    resumeAutoscroll()
                }
            }
            .onChange(of: shouldScrollToBottom) { _, shouldScroll in
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    shouldScrollToBottom = false
                    resumeAutoscroll()
                }
            }
            .overlay(alignment: .bottom) {
                if isAutoscrollPaused && newMessageCount > 0 {
                    NewMessagesIndicator(count: newMessageCount) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        resumeAutoscroll()
                    }
                    .padding(.bottom, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isAutoscrollPaused && newMessageCount > 0)
        }
    }

    // MARK: - Input Bar

    /// Can send messages only if session is in tmux
    private var canSendMessages: Bool {
        guard session.agent == .claude else { return false }
        return session.isInTmux && session.tty != nil
    }

    private var inputPlaceholder: String {
        if session.agent == .codex {
            return "Codex transcript is read-only in this prototype"
        }
        return canSendMessages ? "Message Claude..." : "Open Claude Code in tmux to enable messaging"
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(inputPlaceholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(canSendMessages ? .white : .white.opacity(0.4))
                .focused($isInputFocused)
                .disabled(!canSendMessages)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(canSendMessages ? 0.08 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(!canSendMessages || inputText.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(!canSendMessages || inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [fadeColor.opacity(0), fadeColor.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
        .zIndex(1)
    }

    // MARK: - Codex Bars (see ChatViewActions.swift)

    var codexReadOnlyBar: some View { _codexReadOnlyBar }
    func codexApprovalBar(tool: String) -> some View { _codexApprovalBar(tool: tool) }

    // MARK: - Approval Bar

    func approvalBar(tool: String) -> some View {
        ChatApprovalBar(
            tool: tool,
            toolInput: session.pendingToolInput,
            onApprove: { approvePermission() },
            onDeny: { denyPermission() }
        )
    }

    // MARK: - Interactive Prompt Bar

    var interactivePromptBar: some View {
        ChatInteractivePromptBar(
            isInTmux: session.isInTmux,
            onGoToTerminal: { focusTerminal() }
        )
    }

    // MARK: - Autoscroll Management

    func pauseAutoscroll() {
        isAutoscrollPaused = true
        previousHistoryCount = history.count
    }

    func resumeAutoscroll() {
        isAutoscrollPaused = false
        newMessageCount = 0
        previousHistoryCount = history.count
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicatorView: View {
    private let baseTexts = ["Processing", "Working"]
    private let color = Color(red: 0.85, green: 0.47, blue: 0.34) // Claude orange
    private let baseText: String

    @State private var dotCount: Int = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    /// Use a turnId to select text consistently per user turn
    init(turnId: String = "") {
        let index = abs(turnId.hashValue) % baseTexts.count
        baseText = baseTexts[index]
    }

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ProcessingSpinner()
                .frame(width: 6)

            Text(baseText + dots)
                .font(.system(size: 13))
                .foregroundColor(color)

            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - New Messages Indicator

/// Floating indicator showing count of new messages when user has scrolled up
struct NewMessagesIndicator: View {
    let count: Int
    let onTap: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))

                Text(count == 1 ? "1 new message" : "\(count) new messages")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.85, green: 0.47, blue: 0.34)) // Claude orange
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}

