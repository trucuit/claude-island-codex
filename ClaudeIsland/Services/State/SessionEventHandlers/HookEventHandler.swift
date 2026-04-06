//
//  HookEventHandler.swift
//  ClaudeIsland
//
//  Handles hook-received events: session creation, tool tracking, subagent tracking.
//

import Foundation
import Mixpanel
import os.log

extension SessionStore {

    // MARK: - Hook Event Entry Point

    func processHookEvent(_ event: HookEvent) async {
        let sessionId = event.sessionId
        let isNewSession = sessions[sessionId] == nil
        var session = sessions[sessionId] ?? createSession(from: event)

        if isNewSession {
            Mixpanel.mainInstance().track(event: "Session Started")
        }

        session.pid = event.pid
        if let pid = event.pid {
            let tree = ProcessTreeBuilder.shared.buildTree()
            session.isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)
        }
        if let tty = event.tty {
            session.tty = tty.replacingOccurrences(of: "/dev/", with: "")
        }
        session.lastActivity = Date()

        if event.status == "ended" {
            sessions.removeValue(forKey: sessionId)
            cancelPendingSync(sessionId: sessionId)
            return
        }

        let newPhase = event.determinePhase()

        if session.phase.canTransition(to: newPhase) {
            session.phase = newPhase
        } else {
            Self.logger.debug("Invalid transition: \(String(describing: session.phase), privacy: .public) -> \(String(describing: newPhase), privacy: .public), ignoring")
        }

        if event.event == "PermissionRequest", let toolUseId = event.toolUseId {
            Self.logger.debug("Setting tool \(toolUseId.prefix(12), privacy: .public) status to waitingForApproval")
            updateToolStatus(in: &session, toolId: toolUseId, status: .waitingForApproval)
        }

        processToolTracking(event: event, session: &session)
        processSubagentTracking(event: event, session: &session)

        if event.event == "Stop" {
            session.subagentState = SubagentState()
        }

        sessions[sessionId] = session
        publishState()

        if event.shouldSyncFile {
            scheduleFileSync(sessionId: sessionId, cwd: event.cwd)
        }
    }

    // MARK: - Session Creation

    func createSession(from event: HookEvent) -> SessionState {
        SessionState(
            sessionId: event.sessionId,
            cwd: event.cwd,
            projectName: URL(fileURLWithPath: event.cwd).lastPathComponent,
            pid: event.pid,
            tty: event.tty?.replacingOccurrences(of: "/dev/", with: ""),
            isInTmux: false,
            phase: .idle
        )
    }

    // MARK: - Tool Tracking

    func processToolTracking(event: HookEvent, session: inout SessionState) {
        switch event.event {
        case "PreToolUse":
            guard let toolUseId = event.toolUseId, let toolName = event.tool else { return }
            session.toolTracker.startTool(id: toolUseId, name: toolName)

            let isSubagentTool = session.subagentState.hasActiveSubagent && toolName != "Task"
            if isSubagentTool { return }

            let toolExists = session.chatItems.contains { $0.id == toolUseId }
            if !toolExists {
                var input: [String: String] = [:]
                if let hookInput = event.toolInput {
                    for (key, value) in hookInput {
                        if let str = value.value as? String {
                            input[key] = str
                        } else if let num = value.value as? Int {
                            input[key] = String(num)
                        } else if let bool = value.value as? Bool {
                            input[key] = bool ? "true" : "false"
                        }
                    }
                }

                let placeholderItem = ChatHistoryItem(
                    id: toolUseId,
                    type: .toolCall(ToolCallItem(
                        name: toolName,
                        input: input,
                        status: .running,
                        result: nil,
                        structuredResult: nil,
                        subagentTools: []
                    )),
                    timestamp: Date()
                )
                session.chatItems.append(placeholderItem)
                Self.logger.debug("Created placeholder tool entry for \(toolUseId.prefix(16), privacy: .public)")
            }

        case "PostToolUse":
            guard let toolUseId = event.toolUseId else { return }
            session.toolTracker.completeTool(id: toolUseId, success: true)
            for i in 0..<session.chatItems.count {
                if session.chatItems[i].id == toolUseId,
                   case .toolCall(var tool) = session.chatItems[i].type,
                   tool.status == .waitingForApproval || tool.status == .running {
                    tool.status = .success
                    session.chatItems[i] = ChatHistoryItem(
                        id: toolUseId,
                        type: .toolCall(tool),
                        timestamp: session.chatItems[i].timestamp
                    )
                    break
                }
            }

        default:
            break
        }
    }

    // MARK: - Subagent Tracking

    func processSubagentTracking(event: HookEvent, session: inout SessionState) {
        switch event.event {
        case "PreToolUse":
            if event.tool == "Task", let toolUseId = event.toolUseId {
                let description = event.toolInput?["description"]?.value as? String
                session.subagentState.startTask(taskToolId: toolUseId, description: description)
                Self.logger.debug("Started Task subagent tracking: \(toolUseId.prefix(12), privacy: .public)")
            }

        case "PostToolUse":
            if event.tool == "Task" {
                Self.logger.debug("PostToolUse for Task received (subagent still running)")
            }

        case "SubagentStop":
            Self.logger.debug("SubagentStop received")

        default:
            break
        }
    }
}
