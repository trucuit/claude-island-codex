//
//  FileEventHandler.swift
//  ClaudeIsland
//
//  Handles file update, history loading, and tool completion events.
//  Low-level chat item builders live in ChatItemBuilder.swift.
//

import Foundation
import os.log

extension SessionStore {

    // MARK: - File Update

    func processFileUpdate(_ payload: FileUpdatePayload) async {
        guard var session = sessions[payload.sessionId] else { return }

        let conversationInfo = await ConversationParser.shared.parse(
            sessionId: payload.sessionId,
            cwd: session.cwd
        )
        session.conversationInfo = conversationInfo

        // /clear reconciliation — remove items that no longer exist in parser state
        if session.needsClearReconciliation {
            var validIds = Set<String>()
            for message in payload.messages {
                for (blockIndex, block) in message.content.enumerated() {
                    switch block {
                    case .toolUse(let tool):
                        validIds.insert(tool.id)
                    case .text, .thinking, .interrupted:
                        let itemId = "\(message.id)-\(block.typePrefix)-\(blockIndex)"
                        validIds.insert(itemId)
                    }
                }
            }

            let cutoffTime = Date().addingTimeInterval(-2)
            let previousCount = session.chatItems.count
            session.chatItems = session.chatItems.filter { item in
                validIds.contains(item.id) || item.timestamp > cutoffTime
            }

            session.toolTracker = ToolTracker()
            session.subagentState = SubagentState()
            session.needsClearReconciliation = false
            Self.logger.debug("Clear reconciliation: kept \(session.chatItems.count) of \(previousCount) items")
        }

        let existingIds = Set(session.chatItems.map { $0.id })

        for message in payload.messages {
            for (blockIndex, block) in message.content.enumerated() {
                if case .toolUse(let tool) = block,
                   let idx = session.chatItems.firstIndex(where: { $0.id == tool.id }),
                   case .toolCall(let existingTool) = session.chatItems[idx].type {
                    session.chatItems[idx] = ChatHistoryItem(
                        id: tool.id,
                        type: .toolCall(ToolCallItem(
                            name: tool.name,
                            input: tool.input,
                            status: existingTool.status,
                            result: existingTool.result,
                            structuredResult: existingTool.structuredResult,
                            subagentTools: existingTool.subagentTools
                        )),
                        timestamp: message.timestamp
                    )
                    continue
                }

                if let item = createChatItem(
                    from: block, message: message, blockIndex: blockIndex,
                    existingIds: existingIds, completedTools: payload.completedToolIds,
                    toolResults: payload.toolResults, structuredResults: payload.structuredResults,
                    toolTracker: &session.toolTracker
                ) {
                    session.chatItems.append(item)
                }
            }
        }

        if !payload.isIncremental {
            session.chatItems.sort { $0.timestamp < $1.timestamp }
        }

        session.toolTracker.lastSyncTime = Date()

        await populateSubagentToolsFromAgentFiles(
            session: &session, cwd: payload.cwd, structuredResults: payload.structuredResults
        )

        sessions[payload.sessionId] = session

        await emitToolCompletionEvents(
            sessionId: payload.sessionId, session: session,
            completedToolIds: payload.completedToolIds,
            toolResults: payload.toolResults, structuredResults: payload.structuredResults
        )
    }

    // MARK: - History Loading

    func loadHistoryFromFile(sessionId: String, cwd: String) async {
        let messages = await ConversationParser.shared.parseFullConversation(sessionId: sessionId, cwd: cwd)
        let completedTools = await ConversationParser.shared.completedToolIds(for: sessionId)
        let toolResults = await ConversationParser.shared.toolResults(for: sessionId)
        let structuredResults = await ConversationParser.shared.structuredResults(for: sessionId)
        let conversationInfo = await ConversationParser.shared.parse(sessionId: sessionId, cwd: cwd)

        await process(.historyLoaded(
            sessionId: sessionId,
            messages: messages,
            completedTools: completedTools,
            toolResults: toolResults,
            structuredResults: structuredResults,
            conversationInfo: conversationInfo
        ))
    }

    func processHistoryLoaded(
        sessionId: String,
        messages: [ChatMessage],
        completedTools: Set<String>,
        toolResults: [String: ConversationParser.ToolResult],
        structuredResults: [String: ToolResultData],
        conversationInfo: ConversationInfo
    ) async {
        guard var session = sessions[sessionId] else { return }

        session.conversationInfo = conversationInfo
        let existingIds = Set(session.chatItems.map { $0.id })

        for message in messages {
            for (blockIndex, block) in message.content.enumerated() {
                if let item = createChatItem(
                    from: block, message: message, blockIndex: blockIndex,
                    existingIds: existingIds, completedTools: completedTools,
                    toolResults: toolResults, structuredResults: structuredResults,
                    toolTracker: &session.toolTracker
                ) {
                    session.chatItems.append(item)
                }
            }
        }

        session.chatItems.sort { $0.timestamp < $1.timestamp }
        sessions[sessionId] = session
    }

    // MARK: - Tool Completion

    func processToolCompleted(sessionId: String, toolUseId: String, result: ToolCompletionResult) async {
        guard var session = sessions[sessionId] else { return }

        // Skip if already completed
        if let existingItem = session.chatItems.first(where: { $0.id == toolUseId }),
           case .toolCall(let tool) = existingItem.type,
           tool.status == .success || tool.status == .error || tool.status == .interrupted {
            return
        }

        for i in 0..<session.chatItems.count {
            if session.chatItems[i].id == toolUseId,
               case .toolCall(var tool) = session.chatItems[i].type {
                tool.status = result.status
                tool.result = result.result
                tool.structuredResult = result.structuredResult
                session.chatItems[i] = ChatHistoryItem(
                    id: toolUseId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[i].timestamp
                )
                Self.logger.debug("Tool \(toolUseId.prefix(12), privacy: .public) completed with status: \(String(describing: result.status), privacy: .public)")
                break
            }
        }

        if case .waitingForApproval(let ctx) = session.phase, ctx.toolUseId == toolUseId {
            if let nextPending = findNextPendingTool(in: session, excluding: toolUseId) {
                session.phase = SessionPhase.waitingForApproval(PermissionContext(
                    toolUseId: nextPending.id,
                    toolName: nextPending.name,
                    toolInput: nil,
                    receivedAt: nextPending.timestamp
                ))
                Self.logger.debug("Switched to next pending tool after completion: \(nextPending.id.prefix(12), privacy: .public)")
            } else if session.phase.canTransition(to: .processing) {
                session.phase = .processing
            }
        }

        sessions[sessionId] = session
    }
}
