//
//  PaginatedTextView.swift
//  ClaudeIsland
//
//  Reusable paginated text view for large tool outputs.
//  Short results (<pageSize lines) render with no pagination UI.
//

import SwiftUI

struct PaginatedTextView: View {
    let text: String
    let pageSize: Int
    let monospacedFont: Bool
    let textColor: Color

    @State private var visibleLineCount: Int

    init(
        text: String,
        pageSize: Int = 100,
        monospacedFont: Bool = true,
        textColor: Color = .white.opacity(0.85)
    ) {
        self.text = text
        self.pageSize = pageSize
        self.monospacedFont = monospacedFont
        self.textColor = textColor
        self._visibleLineCount = State(initialValue: pageSize)
    }

    // Split preserving empty lines so line counts stay accurate
    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private var totalLines: Int { lines.count }
    private var needsPagination: Bool { totalLines > pageSize }
    private var visibleText: String {
        lines.prefix(visibleLineCount).joined(separator: "\n")
    }
    private var hasMore: Bool { visibleLineCount < totalLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(visibleText)
                .font(monospacedFont
                    ? .system(size: 11, design: .monospaced)
                    : .system(size: 12))
                .foregroundColor(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if needsPagination {
                HStack(spacing: 12) {
                    Text("\(min(visibleLineCount, totalLines)) of \(totalLines) lines")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))

                    if hasMore {
                        Button("Show more") {
                            visibleLineCount = min(visibleLineCount + pageSize, totalLines)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(TerminalColors.blue)

                        Button("Show all") {
                            visibleLineCount = totalLines
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(TerminalColors.blue)
                    }
                }
                .font(.system(size: 11))
            }
        }
    }
}
