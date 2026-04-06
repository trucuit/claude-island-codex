//
//  CodexSessionMonitor.swift
//  ClaudeIsland
//
//  Safe prototype monitor for Codex Desktop session logs.
//

import Combine
import Foundation

@MainActor
final class CodexSessionMonitor: ObservableObject {
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private struct CacheEntry: Sendable {
        let modificationTime: TimeInterval
        let session: SessionState?
    }

    private struct RefreshResult: Sendable {
        let sessions: [SessionState]
        let cache: [String: CacheEntry]
    }

    private var timerCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var cache: [String: CacheEntry] = [:]

    private let maxAge: TimeInterval = 6 * 60 * 60
    private let refreshInterval: TimeInterval = 1.5
    private let maxSessions = 20

    func startMonitoring() {
        refresh()

        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func stopMonitoring() {
        timerCancellable?.cancel()
        timerCancellable = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        refreshTask?.cancel()

        let existingCache = cache
        let maxAge = maxAge
        let maxSessions = maxSessions

        refreshTask = Task.detached(priority: .utility) {
            let result = Self.scanSessions(
                existingCache: existingCache,
                maxAge: maxAge,
                maxSessions: maxSessions
            )

            await MainActor.run {
                self.cache = result.cache
                self.instances = result.sessions
                self.pendingInstances = result.sessions.filter(\.needsAttention)
            }
        }
    }

    nonisolated private static func scanSessions(
        existingCache: [String: CacheEntry],
        maxAge: TimeInterval,
        maxSessions: Int
    ) -> RefreshResult {
        let baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        let cutoff = Date().addingTimeInterval(-maxAge)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return RefreshResult(sessions: [], cache: [:])
        }

        var candidates: [(url: URL, modDate: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  modDate >= cutoff else {
                continue
            }

            candidates.append((fileURL, modDate))
        }

        candidates.sort { $0.modDate > $1.modDate }
        candidates = Array(candidates.prefix(maxSessions * 2))

        var sessions: [SessionState] = []
        var nextCache: [String: CacheEntry] = [:]

        for candidate in candidates {
            let path = candidate.url.path
            let modTime = candidate.modDate.timeIntervalSince1970

            if let cached = existingCache[path], cached.modificationTime == modTime {
                nextCache[path] = cached
                if let session = cached.session {
                    sessions.append(session)
                }
                continue
            }

            let parsed = parseSession(at: candidate.url, formatter: formatter)
            let entry = CacheEntry(modificationTime: modTime, session: parsed)
            nextCache[path] = entry

            if let parsed {
                sessions.append(parsed)
            }
        }

        sessions.sort { lhs, rhs in
            if lhs.phase.needsAttention != rhs.phase.needsAttention {
                return lhs.phase.needsAttention && !rhs.phase.needsAttention
            }
            return lhs.lastActivity > rhs.lastActivity
        }

        return RefreshResult(sessions: Array(sessions.prefix(maxSessions)), cache: nextCache)
    }

    private struct PendingApproval {
        let callId: String
        let toolName: String
        let input: [String: AnyCodable]?
        let timestamp: Date
    }

    nonisolated private static func parseSession(at url: URL, formatter: ISO8601DateFormatter) -> SessionState? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = FileManager.default.homeDirectoryForCurrentUser.path
        var createdAt = Date.distantPast
        var lastActivity = Date.distantPast
        var approvalPolicy = "never"
        var firstUserMessage: String?
        var lastUserMessage: String?
        var lastUserMessageDate: Date?
        var latestAssistantMessage: String?
        var latestAgentMessage: String?
        var latestTaskStart: Date?
        var latestTaskComplete: Date?
        var pendingApprovals: [String: PendingApproval] = [:]
        var isSubagent = false

        for line in content.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let timestamp = parseTimestamp(json["timestamp"], formatter: formatter)
            if let timestamp {
                lastActivity = max(lastActivity, timestamp)
            }

            switch json["type"] as? String {
            case "session_meta":
                if let payload = json["payload"] as? [String: Any] {
                    sessionId = payload["id"] as? String ?? sessionId
                    cwd = payload["cwd"] as? String ?? cwd
                    createdAt = parseTimestamp(payload["timestamp"], formatter: formatter) ?? timestamp ?? createdAt

                    if let source = payload["source"] as? [String: Any],
                       source["subagent"] != nil {
                        isSubagent = true
                    }
                }

            case "turn_context":
                if let payload = json["payload"] as? [String: Any] {
                    approvalPolicy = payload["approval_policy"] as? String ?? approvalPolicy
                    cwd = payload["cwd"] as? String ?? cwd
                }

            case "event_msg":
                guard let payload = json["payload"] as? [String: Any] else { break }

                switch payload["type"] as? String {
                case "task_started":
                    latestTaskStart = timestamp ?? latestTaskStart
                case "task_complete":
                    latestTaskComplete = timestamp ?? latestTaskComplete
                    if let lastAgentMessage = payload["last_agent_message"] as? String,
                       !lastAgentMessage.isEmpty {
                        latestAssistantMessage = truncate(lastAgentMessage, maxLength: 140)
                    }
                case "user_message":
                    if let message = payload["message"] as? String,
                       !message.isEmpty {
                        let truncated = truncate(message, maxLength: 140)
                        lastUserMessage = truncated
                        lastUserMessageDate = timestamp ?? lastUserMessageDate
                        if firstUserMessage == nil {
                            firstUserMessage = truncate(message, maxLength: 60)
                        }
                    }
                case "agent_message":
                    if let message = payload["message"] as? String,
                       !message.isEmpty {
                        latestAgentMessage = truncate(message, maxLength: 140)
                    }
                default:
                    break
                }

            case "response_item":
                guard let payload = json["payload"] as? [String: Any] else { break }

                switch payload["type"] as? String {
                case "function_call":
                    guard let callId = payload["call_id"] as? String,
                          let name = payload["name"] as? String else {
                        break
                    }

                    let arguments = decodeArguments(payload["arguments"] as? String)
                    let requiresEscalation = (arguments["sandbox_permissions"] as? String) == "require_escalated"

                    if requiresEscalation {
                        let command = (arguments["cmd"] as? String) ?? (arguments["command"] as? String)
                        let justification = arguments["justification"] as? String
                        var input: [String: AnyCodable] = [
                            "approval_policy": AnyCodable(approvalPolicy)
                        ]
                        if let command, !command.isEmpty {
                            input["command"] = AnyCodable(command)
                        }
                        if let justification, !justification.isEmpty {
                            input["justification"] = AnyCodable(justification)
                        }

                        pendingApprovals[callId] = PendingApproval(
                            callId: callId,
                            toolName: name,
                            input: input,
                            timestamp: timestamp ?? Date()
                        )
                    }

                case "function_call_output":
                    if let callId = payload["call_id"] as? String {
                        pendingApprovals.removeValue(forKey: callId)
                    }

                case "message":
                    if let role = payload["role"] as? String,
                       role == "assistant",
                       let content = payload["content"] as? [[String: Any]],
                       let text = content.compactMap({ $0["text"] as? String }).joined(separator: "\n").nilIfEmpty {
                        latestAssistantMessage = truncate(text, maxLength: 140)
                    }

                default:
                    break
                }

            default:
                break
            }
        }

        guard !isSubagent else {
            return nil
        }

        if lastActivity == .distantPast {
            lastActivity = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        }
        if createdAt == .distantPast {
            createdAt = lastActivity
        }

        let phase: SessionPhase
        if let pending = pendingApprovals.values.sorted(by: { $0.timestamp > $1.timestamp }).first {
            phase = .waitingForApproval(PermissionContext(
                toolUseId: pending.callId,
                toolName: pending.toolName,
                toolInput: pending.input,
                receivedAt: pending.timestamp
            ))
        } else if let latestTaskStart, latestTaskStart > (latestTaskComplete ?? .distantPast) {
            phase = .processing
        } else if latestTaskComplete != nil {
            phase = .waitingForInput
        } else {
            phase = .idle
        }

        let conversationInfo = ConversationInfo(
            summary: firstUserMessage,
            lastMessage: latestAssistantMessage ?? latestAgentMessage ?? lastUserMessage,
            lastMessageRole: latestAssistantMessage != nil ? "assistant" : (latestAgentMessage != nil ? "assistant" : "user"),
            lastToolName: phase.approvalToolName,
            firstUserMessage: firstUserMessage,
            lastUserMessageDate: lastUserMessageDate
        )

        return SessionState(
            agent: .codex,
            sessionId: sessionId,
            cwd: cwd,
            projectName: URL(fileURLWithPath: cwd).lastPathComponent,
            logPath: url.path,
            phase: phase,
            conversationInfo: conversationInfo,
            lastActivity: lastActivity,
            createdAt: createdAt
        )
    }

    nonisolated private static func parseTimestamp(_ raw: Any?, formatter: ISO8601DateFormatter) -> Date? {
        guard let string = raw as? String else { return nil }
        return formatter.date(from: string)
    }

    nonisolated private static func decodeArguments(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    nonisolated private static func truncate(_ text: String, maxLength: Int) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength - 3)) + "..."
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
