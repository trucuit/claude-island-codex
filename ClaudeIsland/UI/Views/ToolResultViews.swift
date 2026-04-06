//
//  ToolResultViews.swift
//  ClaudeIsland
//
//  ToolResultContent dispatcher + shared helper views used across tool result files:
//  FileCodeView, CodePreview, FileListView, DiffView, SimpleDiffView, RoundedCorner
//
//  Extracted result views:
//  - FileToolResults.swift   — Read, Edit, Write, EditInputDiff
//  - SearchToolResults.swift — Grep, Glob, WebFetch, WebSearch
//  - SystemToolResults.swift — Bash, BashOutput, KillShell, TodoWrite, Task,
//                              AskUserQuestion, ExitPlanMode, MCP, Generic
//

import SwiftUI

// MARK: - Tool Result Content Dispatcher

struct ToolResultContent: View {
    let tool: ToolCallItem

    var body: some View {
        if let structured = tool.structuredResult {
            switch structured {
            case .read(let r):
                ReadResultContent(result: r)
            case .edit(let r):
                EditResultContent(result: r, toolInput: tool.input)
            case .write(let r):
                WriteResultContent(result: r)
            case .bash(let r):
                BashResultContent(result: r)
            case .grep(let r):
                GrepResultContent(result: r)
            case .glob(let r):
                GlobResultContent(result: r)
            case .todoWrite(let r):
                TodoWriteResultContent(result: r)
            case .task(let r):
                TaskResultContent(result: r)
            case .webFetch(let r):
                WebFetchResultContent(result: r)
            case .webSearch(let r):
                WebSearchResultContent(result: r)
            case .askUserQuestion(let r):
                AskUserQuestionResultContent(result: r)
            case .bashOutput(let r):
                BashOutputResultContent(result: r)
            case .killShell(let r):
                KillShellResultContent(result: r)
            case .exitPlanMode(let r):
                ExitPlanModeResultContent(result: r)
            case .mcp(let r):
                MCPResultContent(result: r)
            case .generic(let r):
                GenericResultContent(result: r)
            }
        } else if tool.name == "Edit" {
            // Special fallback for Edit - show diff from input params
            EditInputDiffView(input: tool.input)
        } else if let result = tool.result {
            // Fallback to raw text display
            GenericTextContent(text: result)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Helper Views

/// File code view with filename header and line numbers (matches Edit tool styling)
struct FileCodeView: View {
    let filename: String
    let content: String
    let startLine: Int
    let totalLines: Int
    let maxLines: Int

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    private var displayLines: [String] {
        Array(lines.prefix(maxLines))
    }

    private var hasMoreAfter: Bool {
        lines.count > maxLines
    }

    private var hasLinesBefore: Bool {
        startLine > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Filename header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Text(filename)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedCorner(radius: 6, corners: [.topLeft, .topRight]))

            if hasLinesBefore {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 46)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
            }

            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                let lineNumber = startLine + index
                let isLast = index == displayLines.count - 1 && !hasMoreAfter
                CodeLineView(line: line, lineNumber: lineNumber, isLast: isLast)
            }

            if hasMoreAfter {
                Text("... (\(lines.count - maxLines) more lines)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 46)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedCorner(radius: 6, corners: [.bottomLeft, .bottomRight]))
            }
        }
    }

    private struct CodeLineView: View {
        let line: String
        let lineNumber: Int
        let isLast: Bool

        var body: some View {
            HStack(spacing: 0) {
                Text("\(lineNumber)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 28, alignment: .trailing)
                    .padding(.trailing, 8)

                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedCorner(radius: 6, corners: isLast ? [.bottomLeft, .bottomRight] : []))
        }
    }
}

struct CodePreview: View {
    let content: String
    let maxLines: Int

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        let displayLines = Array(lines.prefix(maxLines))
        let hasMore = lines.count > maxLines

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            if hasMore {
                Text("... (\(lines.count - maxLines) more lines)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
    }
}

struct FileListView: View {
    let files: [String]
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(files.prefix(limit).enumerated()), id: \.offset) { _, file in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                    Text(URL(fileURLWithPath: file).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            if files.count > limit {
                Text("... and \(files.count - limit) more files")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}

// Diff views and RoundedCorner shape extracted to DiffViews.swift
