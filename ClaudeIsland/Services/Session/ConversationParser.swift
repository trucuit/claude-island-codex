//
//  ConversationParser.swift
//  ClaudeIsland
//
//  Orchestrator actor: delegates file I/O to JSONLStreamReader, JSON extraction to
//  ToolCallExtractor, and subagent tool parsing to SubagentParser.
//  Public API is unchanged — all callers continue to work without modification.
//

import Foundation
import os.log

// MARK: - Public Types

struct ConversationInfo: Equatable {
    let summary: String?
    let lastMessage: String?
    let lastMessageRole: String?
    let lastToolName: String?
    let firstUserMessage: String?
    let lastUserMessageDate: Date?
}

/// Top-level so IncrementalParseState (in JSONLStreamReader.swift) can reference it
/// without a circular dependency on the ConversationParser actor type.
/// All callers use `ConversationParser.ToolResult` via the typealias below.
struct ParsedToolResult {
    let content: String?
    let stdout: String?
    let stderr: String?
    let isError: Bool
    let isInterrupted: Bool

    init(content: String?, stdout: String?, stderr: String?, isError: Bool) {
        self.content = content
        self.stdout = stdout
        self.stderr = stderr
        self.isError = isError
        self.isInterrupted = isError && (
            content?.contains("Interrupted by user") == true ||
            content?.contains("interrupted by user") == true ||
            content?.contains("user doesn't want to proceed") == true
        )
    }
}

// MARK: - Actor

actor ConversationParser {
    static let shared = ConversationParser()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "Parser")

    private var cache: [String: CachedInfo] = [:]
    private var incrementalState: [String: IncrementalParseState] = [:]

    private struct CachedInfo {
        let modificationDate: Date
        let info: ConversationInfo
    }

    // Preserve `ConversationParser.ToolResult` for all existing callers (SessionStore, SessionEvent, etc.)
    typealias ToolResult = ParsedToolResult

    // MARK: - IncrementalParseResult (public — returned by parseIncremental)

    struct IncrementalParseResult {
        let newMessages: [ChatMessage]
        let allMessages: [ChatMessage]
        let completedToolIds: Set<String>
        let toolResults: [String: ToolResult]
        let structuredResults: [String: ToolResultData]
        let clearDetected: Bool
    }

    // MARK: - Summary Parse (cached, full-file read)

    func parse(sessionId: String, cwd: String) -> ConversationInfo {
        let sessionFile = Self.sessionFilePath(sessionId: sessionId, cwd: cwd)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sessionFile),
              let attrs = try? fileManager.attributesOfItem(atPath: sessionFile),
              let modDate = attrs[.modificationDate] as? Date else {
            return .empty
        }

        if let cached = cache[sessionFile], cached.modificationDate == modDate {
            return cached.info
        }

        guard let content = JSONLStreamReader.readFullFile(at: sessionFile) else {
            return .empty
        }

        let info = parseContent(content)
        cache[sessionFile] = CachedInfo(modificationDate: modDate, info: info)
        return info
    }

    // MARK: - Full Conversation Parse

    func parseFullConversation(sessionId: String, cwd: String) -> [ChatMessage] {
        let sessionFile = Self.sessionFilePath(sessionId: sessionId, cwd: cwd)
        guard FileManager.default.fileExists(atPath: sessionFile) else { return [] }

        var state = incrementalState[sessionId] ?? IncrementalParseState()
        _ = parseNewLines(filePath: sessionFile, state: &state)
        incrementalState[sessionId] = state
        return state.messages
    }

    // MARK: - Incremental Parse

    func parseIncremental(sessionId: String, cwd: String) -> IncrementalParseResult {
        let sessionFile = Self.sessionFilePath(sessionId: sessionId, cwd: cwd)

        guard FileManager.default.fileExists(atPath: sessionFile) else {
            return IncrementalParseResult(
                newMessages: [], allMessages: [],
                completedToolIds: [], toolResults: [:],
                structuredResults: [:], clearDetected: false
            )
        }

        var state = incrementalState[sessionId] ?? IncrementalParseState()
        let newMessages = parseNewLines(filePath: sessionFile, state: &state)
        let clearDetected = state.clearPending
        if clearDetected { state.clearPending = false }
        incrementalState[sessionId] = state

        return IncrementalParseResult(
            newMessages: newMessages,
            allMessages: state.messages,
            completedToolIds: state.completedToolIds,
            toolResults: state.toolResults,
            structuredResults: state.structuredResults,
            clearDetected: clearDetected
        )
    }

    // MARK: - Accessors

    func completedToolIds(for sessionId: String) -> Set<String> {
        incrementalState[sessionId]?.completedToolIds ?? []
    }

    func toolResults(for sessionId: String) -> [String: ToolResult] {
        incrementalState[sessionId]?.toolResults ?? [:]
    }

    func structuredResults(for sessionId: String) -> [String: ToolResultData] {
        incrementalState[sessionId]?.structuredResults ?? [:]
    }

    func resetState(for sessionId: String) {
        incrementalState.removeValue(forKey: sessionId)
    }

    func checkAndConsumeClearDetected(for sessionId: String) -> Bool {
        guard var state = incrementalState[sessionId], state.clearPending else { return false }
        state.clearPending = false
        incrementalState[sessionId] = state
        return true
    }

    // MARK: - Subagent Tools (async variant)

    func parseSubagentTools(agentId: String, cwd: String) -> [SubagentToolInfo] {
        SubagentParser.parseSubagentTools(agentId: agentId, cwd: cwd)
    }

    // MARK: - Subagent Tools (nonisolated static — preserves API for AgentFileWatcher)

    nonisolated static func parseSubagentToolsSync(agentId: String, cwd: String) -> [SubagentToolInfo] {
        SubagentParser.parseSubagentToolsSync(agentId: agentId, cwd: cwd)
    }

    // MARK: - Private Helpers

    private static func sessionFilePath(sessionId: String, cwd: String) -> String {
        let projectDir = cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + projectDir + "/" + sessionId + ".jsonl"
    }

    /// Read new lines from file and apply them to state. Returns newly added ChatMessages.
    private func parseNewLines(filePath: String, state: inout IncrementalParseState) -> [ChatMessage] {
        let (lines, isIncrementalRead) = JSONLStreamReader.readNewLines(filePath: filePath, state: &state)
        guard !lines.isEmpty else { return state.messages }

        state.clearPending = false
        var newMessages: [ChatMessage] = []

        for line in lines {
            if line.contains("<command-name>/clear</command-name>") {
                state.messages = []
                state.seenToolIds = []
                state.toolIdToName = [:]
                state.completedToolIds = []
                state.toolResults = [:]
                state.structuredResults = [:]
                if isIncrementalRead {
                    state.clearPending = true
                    state.lastClearOffset = state.lastFileOffset
                    Self.logger.debug("/clear detected (new), will notify UI")
                }
                continue
            }

            if line.contains("\"tool_result\"") {
                processToolResultLine(line, state: &state)
            } else if line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") {
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let message = ToolCallExtractor.parseMessageLine(
                       json,
                       seenToolIds: &state.seenToolIds,
                       toolIdToName: &state.toolIdToName
                   ) {
                    newMessages.append(message)
                    state.messages.append(message)
                }
            }
        }

        return newMessages
    }

    private func processToolResultLine(_ line: String, state: inout IncrementalParseState) {
        guard let lineData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let messageDict = json["message"] as? [String: Any],
              let contentArray = messageDict["content"] as? [[String: Any]] else { return }

        let toolUseResult = json["toolUseResult"] as? [String: Any]
        let topLevelToolName = json["toolName"] as? String
        let stdout = toolUseResult?["stdout"] as? String
        let stderr = toolUseResult?["stderr"] as? String

        for block in contentArray {
            guard block["type"] as? String == "tool_result",
                  let toolUseId = block["tool_use_id"] as? String else { continue }

            state.completedToolIds.insert(toolUseId)

            let content = block["content"] as? String
            let isError = block["is_error"] as? Bool ?? false
            state.toolResults[toolUseId] = ToolResult(
                content: content, stdout: stdout, stderr: stderr, isError: isError
            )

            let toolName = topLevelToolName ?? state.toolIdToName[toolUseId]
            if let toolUseResult = toolUseResult, let name = toolName {
                state.structuredResults[toolUseId] = ToolCallExtractor.parseStructuredResult(
                    toolName: name, toolUseResult: toolUseResult, isError: isError
                )
            }
        }
    }

    // MARK: - Content Summary Parsing (full file)

    private func parseContent(_ content: String) -> ConversationInfo {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var summary: String?
        var lastMessage: String?
        var lastMessageRole: String?
        var lastToolName: String?
        var firstUserMessage: String?
        var lastUserMessageDate: Date?

        // Forward pass: find first real user message (used as fallback title)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "user",
                  json["isMeta"] as? Bool != true,
                  let message = json["message"] as? [String: Any],
                  let msgContent = message["content"] as? String,
                  !msgContent.hasPrefix("<command-name>"),
                  !msgContent.hasPrefix("<local-command"),
                  !msgContent.hasPrefix("Caveat:") else { continue }
            firstUserMessage = Self.truncateMessage(msgContent, maxLength: 50)
            break
        }

        // Reverse pass: find summary, last message, last user timestamp
        var foundLastUserMessage = false
        for line in lines.reversed() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String

            if lastMessage == nil, type == "user" || type == "assistant" {
                let isMeta = json["isMeta"] as? Bool ?? false
                if !isMeta, let message = json["message"] as? [String: Any] {
                    extractLastMessage(from: message, type: type ?? "",
                                       lastMessage: &lastMessage,
                                       lastMessageRole: &lastMessageRole,
                                       lastToolName: &lastToolName)
                }
            }

            if !foundLastUserMessage, type == "user" {
                let isMeta = json["isMeta"] as? Bool ?? false
                if !isMeta, let message = json["message"] as? [String: Any],
                   let msgContent = message["content"] as? String,
                   !msgContent.hasPrefix("<command-name>"),
                   !msgContent.hasPrefix("<local-command"),
                   !msgContent.hasPrefix("Caveat:") {
                    if let ts = json["timestamp"] as? String {
                        lastUserMessageDate = formatter.date(from: ts)
                    }
                    foundLastUserMessage = true
                }
            }

            if summary == nil, type == "summary", let summaryText = json["summary"] as? String {
                summary = summaryText
            }

            if summary != nil && lastMessage != nil && foundLastUserMessage { break }
        }

        return ConversationInfo(
            summary: summary,
            lastMessage: Self.truncateMessage(lastMessage, maxLength: 80),
            lastMessageRole: lastMessageRole,
            lastToolName: lastToolName,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )
    }

    private func extractLastMessage(
        from message: [String: Any],
        type: String,
        lastMessage: inout String?,
        lastMessageRole: inout String?,
        lastToolName: inout String?
    ) {
        if let msgContent = message["content"] as? String {
            if !msgContent.hasPrefix("<command-name>") && !msgContent.hasPrefix("<local-command") && !msgContent.hasPrefix("Caveat:") {
                lastMessage = msgContent
                lastMessageRole = type
            }
        } else if let contentArray = message["content"] as? [[String: Any]] {
            for block in contentArray.reversed() {
                let blockType = block["type"] as? String
                if blockType == "tool_use" {
                    let toolName = block["name"] as? String ?? "Tool"
                    lastMessage = Self.formatToolInput(block["input"] as? [String: Any], toolName: toolName)
                    lastMessageRole = "tool"
                    lastToolName = toolName
                    break
                } else if blockType == "text", let text = block["text"] as? String {
                    if !text.hasPrefix("[Request interrupted by user") {
                        lastMessage = text
                        lastMessageRole = type
                        break
                    }
                }
            }
        }
    }

    private static func formatToolInput(_ input: [String: Any]?, toolName: String) -> String {
        guard let input = input else { return "" }
        switch toolName {
        case "Read", "Write", "Edit":
            if let p = input["file_path"] as? String { return (p as NSString).lastPathComponent }
        case "Bash":
            if let c = input["command"] as? String { return c }
        case "Grep", "Glob":
            if let p = input["pattern"] as? String { return p }
        case "Task":
            if let d = input["description"] as? String { return d }
        case "WebFetch":
            if let u = input["url"] as? String { return u }
        case "WebSearch":
            if let q = input["query"] as? String { return q }
        default:
            for (_, value) in input {
                if let s = value as? String, !s.isEmpty { return s }
            }
        }
        return ""
    }

    private static func truncateMessage(_ message: String?, maxLength: Int = 80) -> String? {
        guard let msg = message else { return nil }
        let cleaned = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return cleaned.count > maxLength ? String(cleaned.prefix(maxLength - 3)) + "..." : cleaned
    }
}

// MARK: - ConversationInfo convenience

private extension ConversationInfo {
    static let empty = ConversationInfo(
        summary: nil, lastMessage: nil, lastMessageRole: nil,
        lastToolName: nil, firstUserMessage: nil, lastUserMessageDate: nil
    )
}
