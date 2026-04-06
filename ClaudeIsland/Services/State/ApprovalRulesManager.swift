//
//  ApprovalRulesManager.swift
//  ClaudeIsland
//
//  Manages auto-approval allowlist for Claude tool permission requests.
//  Rules are stored in UserDefaults as [String: Bool] keyed by tool name.
//

import Foundation
import Combine

class ApprovalRulesManager: ObservableObject {
    static let shared = ApprovalRulesManager()

    static let defaultTools = [
        "Read", "Glob", "Grep", "Write", "Edit",
        "Bash", "WebFetch", "WebSearch",
        "NotebookEdit", "TodoRead", "TodoWrite"
    ]

    /// Tools that can modify the system — show a warning when user enables auto-approval
    static let dangerousTools: Set<String> = ["Bash", "Write", "Edit"]

    private let defaults = UserDefaults.standard
    private let rulesKey = "autoApprovalRules"
    private let masterKey = "autoApprovalEnabled"
    private let customToolsKey = "autoApprovalCustomTools"

    @Published var masterEnabled: Bool {
        didSet { defaults.set(masterEnabled, forKey: masterKey) }
    }

    @Published private(set) var customTools: [String]

    private init() {
        masterEnabled = defaults.bool(forKey: masterKey)
        customTools = defaults.stringArray(forKey: "autoApprovalCustomTools") ?? []
    }

    // MARK: - Public API

    /// Thread-safe: reads directly from UserDefaults (not @Published) so it's safe
    /// to call from HookSocketServer's background DispatchQueue.
    func isAutoApproved(toolName: String) -> Bool {
        guard defaults.bool(forKey: masterKey) else { return false }
        let rules = defaults.dictionary(forKey: rulesKey) as? [String: Bool] ?? [:]
        return rules[toolName] == true
    }

    func setAutoApproved(toolName: String, enabled: Bool) {
        var rules = loadRules()
        rules[toolName] = enabled
        saveRules(rules)
        objectWillChange.send()
    }

    func allRules() -> [(name: String, enabled: Bool)] {
        let rules = loadRules()
        let allTools = ApprovalRulesManager.defaultTools + customTools
        return allTools.map { name in
            (name: name, enabled: rules[name] == true)
        }
    }

    func addCustomTool(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !ApprovalRulesManager.defaultTools.contains(trimmed),
              !customTools.contains(trimmed) else { return }
        customTools.append(trimmed)
        defaults.set(customTools, forKey: customToolsKey)
    }

    func resetAll() {
        defaults.removeObject(forKey: rulesKey)
        defaults.set(false, forKey: masterKey)
        masterEnabled = false
        objectWillChange.send()
    }

    // MARK: - Private

    private func loadRules() -> [String: Bool] {
        defaults.dictionary(forKey: rulesKey) as? [String: Bool] ?? [:]
    }

    private func saveRules(_ rules: [String: Bool]) {
        defaults.set(rules, forKey: rulesKey)
    }
}
