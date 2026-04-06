//
//  JSONLStreamReader.swift
//  ClaudeIsland
//
//  Handles incremental file I/O for JSONL session files.
//  Tracks read offset, detects file truncation (e.g. /clear), and returns new lines.
//

import Foundation

/// Tracks per-session incremental parse state (file offset + in-memory message buffers)
struct IncrementalParseState {
    var lastFileOffset: UInt64 = 0
    var messages: [ChatMessage] = []
    var seenToolIds: Set<String> = []
    var toolIdToName: [String: String] = [:]
    var completedToolIds: Set<String> = []
    var toolResults: [String: ParsedToolResult] = [:]
    var structuredResults: [String: ToolResultData] = [:]
    /// Offset of the most recent /clear command (0 = none)
    var lastClearOffset: UInt64 = 0
    /// True if a /clear was detected during the most recent read (consumed by caller)
    var clearPending: Bool = false
}

/// Reads new lines from a JSONL file since the last recorded offset.
/// Designed as a struct so it can be called directly within an actor context.
struct JSONLStreamReader {

    /// Reads all lines appended to `filePath` since `state.lastFileOffset`.
    /// Updates `state.lastFileOffset` to the new end-of-file position.
    /// Resets state if file was truncated (fileSize < lastOffset).
    ///
    /// - Returns: Tuple of (newLines, isIncrementalRead).
    ///   `isIncrementalRead` is true when this is NOT a first read from offset 0.
    static func readNewLines(
        filePath: String,
        state: inout IncrementalParseState
    ) -> (lines: [String], isIncrementalRead: Bool) {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return ([], false)
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return ([], false)
        }

        // File was truncated — reset state (e.g. session was restarted)
        if fileSize < state.lastFileOffset {
            state = IncrementalParseState()
        }

        if fileSize == state.lastFileOffset {
            return ([], state.lastFileOffset > 0)
        }

        let isIncrementalRead = state.lastFileOffset > 0

        do {
            try fileHandle.seek(toOffset: state.lastFileOffset)
        } catch {
            return ([], isIncrementalRead)
        }

        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return ([], isIncrementalRead)
        }

        state.lastFileOffset = fileSize

        let lines = newContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        return (lines, isIncrementalRead)
    }

    /// Reads the entire content of a file as a UTF-8 string.
    static func readFullFile(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
