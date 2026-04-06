//
//  ChatViewActions.swift
//  ClaudeIsland
//
//  ChatView extension: Codex bars, action handlers, tmux messaging helpers.
//  Kept separate to stay within file-size guidelines.
//

import AppKit
import SwiftUI

// MARK: - Codex Bars

extension ChatView {

    var _codexReadOnlyBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex transcript")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TerminalColors.shellCool.opacity(0.95))
                Text("Read-only in Claude Island for now")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Button { continueInCodex() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                    Text("Continue in Codex")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.95))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
        .zIndex(1)
    }

    func _codexApprovalBar(tool: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MCPToolFormatter.formatToolName(tool))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber)
                Text("Approval must be handled inside Codex")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Button { continueInCodex() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                    Text("Open in Codex")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.95))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - Actions

extension ChatView {

    func focusTerminal() {
        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    func approvePermission() {
        claudeMonitor.approvePermission(sessionId: sessionId)
    }

    func denyPermission() {
        claudeMonitor.denyPermission(sessionId: sessionId, reason: nil)
    }

    func continueInCodex() {
        guard session.agent == .codex else { return }

        let bundleId = "com.openai.codex"
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        if let logPath = session.logPath,
           NSWorkspace.shared.openFile(logPath, withApplication: "Codex") {
            return
        }

        if let codexURL = URL(string: "codex://") {
            NSWorkspace.shared.open(codexURL)
            return
        }

        if let logPath = session.logPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        resumeAutoscroll()
        shouldScrollToBottom = true

        Task { await sendToSession(text) }
    }

    func sendToSession(_ text: String) async {
        guard session.isInTmux, let tty = session.tty else { return }

        if let target = await findTmuxTarget(tty: tty) {
            _ = await ToolApprovalHandler.shared.sendMessage(text, to: target)
        }
    }

    func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else { return nil }

        do {
            let output = try await ProcessExecutor.shared.run(
                tmuxPath,
                arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
            )

            for line in output.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: " ")
                guard parts.count >= 2 else { continue }

                let paneTty = parts[1].replacingOccurrences(of: "/dev/", with: "")
                if paneTty == tty {
                    return TmuxTarget(from: parts[0])
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}
