//
//  SubagentParser.swift
//  ClaudeIsland
//
//  Parses agent JSONL files to extract subagent tool call listings.
//  Both async (actor-context) and nonisolated sync variants live here.
//

import Foundation

/// Info about a subagent tool call parsed from a JSONL file.
struct SubagentToolInfo: Sendable {
    let id: String
    let name: String
    let input: [String: String]
    let isCompleted: Bool
    let timestamp: String?
}

/// Reads an agent JSONL file and returns all tool calls with completion status.
struct SubagentParser {

    // MARK: - File Path Helper

    static func agentFilePath(agentId: String, cwd: String) -> String {
        let projectDir = cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + projectDir + "/agent-" + agentId + ".jsonl"
    }

    // MARK: - Core Parsing

    /// Parse subagent tools from a JSONL file content string.
    /// Two-pass: first collect completed tool IDs, then collect tool use blocks.
    static func parseTools(from content: String) -> [SubagentToolInfo] {
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Pass 1: collect completed tool IDs from tool_result lines
        var completedToolIds: Set<String> = []
        for line in lines where line.contains("\"tool_result\"") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let messageDict = json["message"] as? [String: Any],
                  let contentArray = messageDict["content"] as? [[String: Any]] else { continue }
            for block in contentArray {
                if block["type"] as? String == "tool_result",
                   let toolUseId = block["tool_use_id"] as? String {
                    completedToolIds.insert(toolUseId)
                }
            }
        }

        // Pass 2: collect tool_use blocks
        var tools: [SubagentToolInfo] = []
        var seenToolIds: Set<String> = []

        for line in lines where line.contains("\"tool_use\"") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let messageDict = json["message"] as? [String: Any],
                  let contentArray = messageDict["content"] as? [[String: Any]] else { continue }

            for block in contentArray {
                guard block["type"] as? String == "tool_use",
                      let toolId = block["id"] as? String,
                      let toolName = block["name"] as? String,
                      !seenToolIds.contains(toolId) else { continue }

                seenToolIds.insert(toolId)

                var input: [String: String] = [:]
                if let inputDict = block["input"] as? [String: Any] {
                    for (key, value) in inputDict {
                        if let s = value as? String { input[key] = s }
                        else if let i = value as? Int { input[key] = String(i) }
                        else if let b = value as? Bool { input[key] = b ? "true" : "false" }
                    }
                }

                tools.append(SubagentToolInfo(
                    id: toolId,
                    name: toolName,
                    input: input,
                    isCompleted: completedToolIds.contains(toolId),
                    timestamp: json["timestamp"] as? String
                ))
            }
        }

        return tools
    }

    // MARK: - Public Entry Points

    /// Async variant — called within actor context (ConversationParser).
    static func parseSubagentTools(agentId: String, cwd: String) -> [SubagentToolInfo] {
        guard !agentId.isEmpty else { return [] }
        let path = agentFilePath(agentId: agentId, cwd: cwd)
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return parseTools(from: content)
    }

    /// Nonisolated sync variant — called from non-actor contexts (e.g. AgentFileWatcher).
    static func parseSubagentToolsSync(agentId: String, cwd: String) -> [SubagentToolInfo] {
        // Identical logic; separate entry point preserves nonisolated callability.
        return parseSubagentTools(agentId: agentId, cwd: cwd)
    }
}
