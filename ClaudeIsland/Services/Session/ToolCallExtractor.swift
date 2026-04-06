//
//  ToolCallExtractor.swift
//  ClaudeIsland
//
//  Pure extraction logic: parses JSON lines into ChatMessage and ToolResultData domain objects.
//  No state — all functions are static. Called within ConversationParser actor context.
//

import Foundation

/// Extracts structured domain objects from raw JSONL lines.
struct ToolCallExtractor {

    // MARK: - Message Line Parsing

    /// Parse a JSON dict (from a user/assistant line) into a ChatMessage.
    static func parseMessageLine(
        _ json: [String: Any],
        seenToolIds: inout Set<String>,
        toolIdToName: inout [String: String]
    ) -> ChatMessage? {
        guard let type = json["type"] as? String,
              let uuid = json["uuid"] as? String,
              type == "user" || type == "assistant",
              json["isMeta"] as? Bool != true,
              let messageDict = json["message"] as? [String: Any] else {
            return nil
        }

        let timestamp: Date = {
            if let ts = json["timestamp"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: ts) ?? Date()
            }
            return Date()
        }()

        var blocks: [MessageBlock] = []

        if let content = messageDict["content"] as? String {
            if content.hasPrefix("<command-name>") || content.hasPrefix("<local-command") || content.hasPrefix("Caveat:") {
                return nil
            }
            blocks.append(content.hasPrefix("[Request interrupted by user") ? .interrupted : .text(content))
        } else if let contentArray = messageDict["content"] as? [[String: Any]] {
            for block in contentArray {
                guard let blockType = block["type"] as? String else { continue }
                switch blockType {
                case "text":
                    if let text = block["text"] as? String {
                        blocks.append(text.hasPrefix("[Request interrupted by user") ? .interrupted : .text(text))
                    }
                case "tool_use":
                    if let toolId = block["id"] as? String {
                        guard !seenToolIds.contains(toolId) else { continue }
                        seenToolIds.insert(toolId)
                        if let toolName = block["name"] as? String {
                            toolIdToName[toolId] = toolName
                        }
                    }
                    if let toolBlock = parseToolUse(block) {
                        blocks.append(.toolUse(toolBlock))
                    }
                case "thinking":
                    if let thinking = block["thinking"] as? String {
                        blocks.append(.thinking(thinking))
                    }
                default:
                    break
                }
            }
        }

        guard !blocks.isEmpty else { return nil }

        return ChatMessage(
            id: uuid,
            role: type == "user" ? .user : .assistant,
            timestamp: timestamp,
            content: blocks
        )
    }

    /// Parse a tool_use block dict into a ToolUseBlock.
    static func parseToolUse(_ block: [String: Any]) -> ToolUseBlock? {
        guard let id = block["id"] as? String,
              let name = block["name"] as? String else { return nil }

        var input: [String: String] = [:]
        if let inputDict = block["input"] as? [String: Any] {
            for (key, value) in inputDict {
                if let s = value as? String { input[key] = s }
                else if let i = value as? Int { input[key] = String(i) }
                else if let b = value as? Bool { input[key] = b ? "true" : "false" }
            }
        }
        return ToolUseBlock(id: id, name: name, input: input)
    }

    // MARK: - Structured Result Parsing

    /// Dispatch tool result data to the correct typed parser.
    static func parseStructuredResult(
        toolName: String,
        toolUseResult: [String: Any],
        isError: Bool
    ) -> ToolResultData {
        if toolName.hasPrefix("mcp__") {
            let parts = toolName.dropFirst(5).split(separator: "_", maxSplits: 2)
            let serverName = parts.count > 0 ? String(parts[0]) : "unknown"
            let mcpToolName = parts.count > 1 ? String(parts[1].dropFirst()) : toolName
            return .mcp(MCPResult(serverName: serverName, toolName: mcpToolName, rawResult: toolUseResult))
        }

        switch toolName {
        case "Read":        return parseReadResult(toolUseResult)
        case "Edit":        return parseEditResult(toolUseResult)
        case "Write":       return parseWriteResult(toolUseResult)
        case "Bash":        return parseBashResult(toolUseResult)
        case "Grep":        return parseGrepResult(toolUseResult)
        case "Glob":        return parseGlobResult(toolUseResult)
        case "TodoWrite":   return parseTodoWriteResult(toolUseResult)
        case "Task":        return parseTaskResult(toolUseResult)
        case "WebFetch":    return parseWebFetchResult(toolUseResult)
        case "WebSearch":   return parseWebSearchResult(toolUseResult)
        case "AskUserQuestion": return parseAskUserQuestionResult(toolUseResult)
        case "BashOutput":  return parseBashOutputResult(toolUseResult)
        case "KillShell":   return parseKillShellResult(toolUseResult)
        case "ExitPlanMode": return parseExitPlanModeResult(toolUseResult)
        default:
            let content = toolUseResult["content"] as? String
                ?? toolUseResult["stdout"] as? String
                ?? toolUseResult["result"] as? String
            return .generic(GenericResult(rawContent: content, rawData: toolUseResult))
        }
    }

    // MARK: - Individual Tool Result Parsers

    private static func parseReadResult(_ data: [String: Any]) -> ToolResultData {
        let src = (data["file"] as? [String: Any]) ?? data
        return .read(ReadResult(
            filePath: src["filePath"] as? String ?? "",
            content: src["content"] as? String ?? "",
            numLines: src["numLines"] as? Int ?? 0,
            startLine: src["startLine"] as? Int ?? 1,
            totalLines: src["totalLines"] as? Int ?? 0
        ))
    }

    private static func parsePatchHunks(_ data: [String: Any]) -> [PatchHunk]? {
        guard let arr = data["structuredPatch"] as? [[String: Any]] else { return nil }
        return arr.compactMap { patch -> PatchHunk? in
            guard let oldStart = patch["oldStart"] as? Int,
                  let oldLines = patch["oldLines"] as? Int,
                  let newStart = patch["newStart"] as? Int,
                  let newLines = patch["newLines"] as? Int,
                  let lines = patch["lines"] as? [String] else { return nil }
            return PatchHunk(oldStart: oldStart, oldLines: oldLines,
                             newStart: newStart, newLines: newLines, lines: lines)
        }
    }

    private static func parseEditResult(_ data: [String: Any]) -> ToolResultData {
        return .edit(EditResult(
            filePath: data["filePath"] as? String ?? "",
            oldString: data["oldString"] as? String ?? "",
            newString: data["newString"] as? String ?? "",
            replaceAll: data["replaceAll"] as? Bool ?? false,
            userModified: data["userModified"] as? Bool ?? false,
            structuredPatch: parsePatchHunks(data)
        ))
    }

    private static func parseWriteResult(_ data: [String: Any]) -> ToolResultData {
        let typeStr = data["type"] as? String ?? "create"
        return .write(WriteResult(
            type: typeStr == "overwrite" ? .overwrite : .create,
            filePath: data["filePath"] as? String ?? "",
            content: data["content"] as? String ?? "",
            structuredPatch: parsePatchHunks(data)
        ))
    }

    private static func parseBashResult(_ data: [String: Any]) -> ToolResultData {
        return .bash(BashResult(
            stdout: data["stdout"] as? String ?? "",
            stderr: data["stderr"] as? String ?? "",
            interrupted: data["interrupted"] as? Bool ?? false,
            isImage: data["isImage"] as? Bool ?? false,
            returnCodeInterpretation: data["returnCodeInterpretation"] as? String,
            backgroundTaskId: data["backgroundTaskId"] as? String
        ))
    }

    private static func parseGrepResult(_ data: [String: Any]) -> ToolResultData {
        let mode: GrepResult.Mode
        switch data["mode"] as? String ?? "" {
        case "content": mode = .content
        case "count":   mode = .count
        default:        mode = .filesWithMatches
        }
        return .grep(GrepResult(
            mode: mode,
            filenames: data["filenames"] as? [String] ?? [],
            numFiles: data["numFiles"] as? Int ?? 0,
            content: data["content"] as? String,
            numLines: data["numLines"] as? Int,
            appliedLimit: data["appliedLimit"] as? Int
        ))
    }

    private static func parseGlobResult(_ data: [String: Any]) -> ToolResultData {
        return .glob(GlobResult(
            filenames: data["filenames"] as? [String] ?? [],
            durationMs: data["durationMs"] as? Int ?? 0,
            numFiles: data["numFiles"] as? Int ?? 0,
            truncated: data["truncated"] as? Bool ?? false
        ))
    }

    private static func parseTodoWriteResult(_ data: [String: Any]) -> ToolResultData {
        func parseTodos(_ array: [[String: Any]]?) -> [TodoItem] {
            guard let array = array else { return [] }
            return array.compactMap { item -> TodoItem? in
                guard let content = item["content"] as? String,
                      let status = item["status"] as? String else { return nil }
                return TodoItem(content: content, status: status, activeForm: item["activeForm"] as? String)
            }
        }
        return .todoWrite(TodoWriteResult(
            oldTodos: parseTodos(data["oldTodos"] as? [[String: Any]]),
            newTodos: parseTodos(data["newTodos"] as? [[String: Any]])
        ))
    }

    private static func parseTaskResult(_ data: [String: Any]) -> ToolResultData {
        return .task(TaskResult(
            agentId: data["agentId"] as? String ?? "",
            status: data["status"] as? String ?? "unknown",
            content: data["content"] as? String ?? "",
            prompt: data["prompt"] as? String,
            totalDurationMs: data["totalDurationMs"] as? Int,
            totalTokens: data["totalTokens"] as? Int,
            totalToolUseCount: data["totalToolUseCount"] as? Int
        ))
    }

    private static func parseWebFetchResult(_ data: [String: Any]) -> ToolResultData {
        return .webFetch(WebFetchResult(
            url: data["url"] as? String ?? "",
            code: data["code"] as? Int ?? 0,
            codeText: data["codeText"] as? String ?? "",
            bytes: data["bytes"] as? Int ?? 0,
            durationMs: data["durationMs"] as? Int ?? 0,
            result: data["result"] as? String ?? ""
        ))
    }

    private static func parseWebSearchResult(_ data: [String: Any]) -> ToolResultData {
        let results: [SearchResultItem] = (data["results"] as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String, let url = item["url"] as? String else { return nil }
            return SearchResultItem(title: title, url: url, snippet: item["snippet"] as? String ?? "")
        }
        return .webSearch(WebSearchResult(
            query: data["query"] as? String ?? "",
            durationSeconds: data["durationSeconds"] as? Double ?? 0,
            results: results
        ))
    }

    private static func parseAskUserQuestionResult(_ data: [String: Any]) -> ToolResultData {
        let questions: [QuestionItem] = (data["questions"] as? [[String: Any]] ?? []).compactMap { q in
            guard let question = q["question"] as? String else { return nil }
            let options: [QuestionOption] = (q["options"] as? [[String: Any]] ?? []).compactMap { opt in
                guard let label = opt["label"] as? String else { return nil }
                return QuestionOption(label: label, description: opt["description"] as? String)
            }
            return QuestionItem(question: question, header: q["header"] as? String, options: options)
        }
        let answers = data["answers"] as? [String: String] ?? [:]
        return .askUserQuestion(AskUserQuestionResult(questions: questions, answers: answers))
    }

    private static func parseBashOutputResult(_ data: [String: Any]) -> ToolResultData {
        return .bashOutput(BashOutputResult(
            shellId: data["shellId"] as? String ?? "",
            status: data["status"] as? String ?? "",
            stdout: data["stdout"] as? String ?? "",
            stderr: data["stderr"] as? String ?? "",
            stdoutLines: data["stdoutLines"] as? Int ?? 0,
            stderrLines: data["stderrLines"] as? Int ?? 0,
            exitCode: data["exitCode"] as? Int,
            command: data["command"] as? String,
            timestamp: data["timestamp"] as? String
        ))
    }

    private static func parseKillShellResult(_ data: [String: Any]) -> ToolResultData {
        return .killShell(KillShellResult(
            shellId: data["shell_id"] as? String ?? data["shellId"] as? String ?? "",
            message: data["message"] as? String ?? ""
        ))
    }

    private static func parseExitPlanModeResult(_ data: [String: Any]) -> ToolResultData {
        return .exitPlanMode(ExitPlanModeResult(
            filePath: data["filePath"] as? String,
            plan: data["plan"] as? String,
            isAgent: data["isAgent"] as? Bool ?? false
        ))
    }
}
