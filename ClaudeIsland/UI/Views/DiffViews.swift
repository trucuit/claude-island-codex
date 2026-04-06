//
//  DiffViews.swift
//  ClaudeIsland
//
//  Shared diff rendering: DiffView (patch hunks), SimpleDiffView (LCS inline diff),
//  DiffLineView, DiffLineType, SimpleDiffLineView, RoundedCorner shape.
//

import SwiftUI

// MARK: - Patch Hunk Diff View

struct DiffView: View {
    let patches: [PatchHunk]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(patches.prefix(3).enumerated()), id: \.offset) { _, patch in
                VStack(alignment: .leading, spacing: 1) {
                    Text("@@ -\(patch.oldStart),\(patch.oldLines) +\(patch.newStart),\(patch.newLines) @@")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.7))

                    ForEach(Array(patch.lines.prefix(10).enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }

                    if patch.lines.count > 10 {
                        Text("... (\(patch.lines.count - 10) more lines)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            if patches.count > 3 {
                Text("... and \(patches.count - 3) more hunks")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }
}

// MARK: - Diff Line View (for patch hunks, prefixed +/-)

struct DiffLineView: View {
    let line: String

    private var lineType: DiffLineType {
        if line.hasPrefix("+") { return .added }
        if line.hasPrefix("-") { return .removed }
        return .context
    }

    var body: some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(lineType.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(lineType.backgroundColor)
    }
}

// MARK: - Diff Line Type

enum DiffLineType {
    case added, removed, context

    var textColor: Color {
        switch self {
        case .added:   return Color(red: 0.4, green: 0.8, blue: 0.4)
        case .removed: return Color(red: 0.9, green: 0.5, blue: 0.5)
        case .context: return .white.opacity(0.5)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added:   return Color(red: 0.2, green: 0.4, blue: 0.2).opacity(0.3)
        case .removed: return Color(red: 0.4, green: 0.2, blue: 0.2).opacity(0.3)
        case .context: return .clear
        }
    }
}

// MARK: - Simple Diff View (LCS-based inline diff)

struct SimpleDiffView: View {
    let oldString: String
    let newString: String
    var filename: String? = nil

    private struct DiffLine {
        let text: String
        let type: DiffLineType
        let lineNumber: Int
    }

    private var diffLines: [DiffLine] {
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")
        let lcs = computeLCS(oldLines, newLines)

        var result: [DiffLine] = []
        var oldIdx = 0, newIdx = 0, lcsIdx = 0

        while oldIdx < oldLines.count || newIdx < newLines.count {
            if result.count >= 12 { break }
            let lcsLine = lcsIdx < lcs.count ? lcs[lcsIdx] : nil

            if oldIdx < oldLines.count && (lcsLine == nil || oldLines[oldIdx] != lcsLine) {
                result.append(DiffLine(text: oldLines[oldIdx], type: .removed, lineNumber: oldIdx + 1))
                oldIdx += 1
            } else if newIdx < newLines.count && (lcsLine == nil || newLines[newIdx] != lcsLine) {
                result.append(DiffLine(text: newLines[newIdx], type: .added, lineNumber: newIdx + 1))
                newIdx += 1
            } else {
                oldIdx += 1; newIdx += 1; lcsIdx += 1
            }
        }
        return result
    }

    private func computeLCS(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var lcs: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] { lcs.append(a[i-1]); i -= 1; j -= 1 }
            else if dp[i-1][j] > dp[i][j-1] { i -= 1 } else { j -= 1 }
        }
        return lcs.reversed()
    }

    private var hasMoreChanges: Bool {
        let ol = oldString.components(separatedBy: "\n")
        let nl = newString.components(separatedBy: "\n")
        let lcs = computeLCS(ol, nl)
        return (ol.count - lcs.count) + (nl.count - lcs.count) > 12
    }

    private var hasLinesBefore: Bool {
        (diffLines.first?.lineNumber ?? 1) > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name = filename {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text(name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedCorner(radius: 6, corners: [.topLeft, .topRight] as RoundedCorner.RectCorner))
            }

            if hasLinesBefore {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 46)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedCorner(radius: 6, corners: filename == nil
                        ? [.topLeft, .topRight] as RoundedCorner.RectCorner
                        : [] as RoundedCorner.RectCorner))
            }

            ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                let isFirst = index == 0 && filename == nil && !hasLinesBefore
                let isLast = index == diffLines.count - 1 && !hasMoreChanges
                SimpleDiffLineView(line: line.text, type: line.type,
                                   lineNumber: line.lineNumber, isFirst: isFirst, isLast: isLast)
            }

            if hasMoreChanges {
                Text("...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 46)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedCorner(radius: 6, corners: [.bottomLeft, .bottomRight] as RoundedCorner.RectCorner))
            }
        }
    }
}

// MARK: - Simple Diff Line View (numbered +/- rows)

struct SimpleDiffLineView: View {
    let line: String
    let type: DiffLineType
    let lineNumber: Int
    let isFirst: Bool
    let isLast: Bool

    private var corners: RoundedCorner.RectCorner {
        if isFirst && isLast { return .allCorners }
        if isFirst { return [.topLeft, .topRight] }
        if isLast  { return [.bottomLeft, .bottomRight] }
        return []
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(type.textColor.opacity(0.6))
                .frame(width: 28, alignment: .trailing)
                .padding(.trailing, 4)
            Text(type == .added ? "+" : "-")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(type.textColor)
                .frame(width: 14)
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(type.textColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(type.backgroundColor)
        .clipShape(RoundedCorner(radius: 6, corners: corners))
    }
}

// MARK: - RoundedCorner Shape (macOS compatible selective corner rounding)

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: RectCorner

    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft     = RectCorner(rawValue: 1 << 0)
        static let topRight    = RectCorner(rawValue: 1 << 1)
        static let bottomLeft  = RectCorner(rawValue: 1 << 2)
        static let bottomRight = RectCorner(rawValue: 1 << 3)
        static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                                 radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                                 radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                                 radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}
