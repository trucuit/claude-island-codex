//
//  TerminalColors.swift
//  ClaudeIsland
//
//  Color palette for terminal-style UI
//

import SwiftUI

struct TerminalColors {
    static let green = Color(red: 0.4, green: 0.75, blue: 0.45)
    static let amber = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    static let blue = Color(red: 0.4, green: 0.6, blue: 1.0)
    static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)
    static let dim = Color.white.opacity(0.4)
    static let dimmer = Color.white.opacity(0.2)
    static let prompt = Color(red: 0.85, green: 0.47, blue: 0.34)  // #d97857
    static let background = Color.white.opacity(0.05)
    static let backgroundHover = Color.white.opacity(0.1)
    static let shellTop = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let shellBottom = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let shellStroke = Color.white.opacity(0.14)
    static let shellStrokeStrong = Color.white.opacity(0.24)
    static let shellHighlight = Color.white.opacity(0.34)
    static let shellCool = Color(red: 0.34, green: 0.76, blue: 1.0)
    static let shellWarm = Color(red: 0.99, green: 0.62, blue: 0.38)
    static let card = Color.white.opacity(0.08)
    static let cardHover = Color.white.opacity(0.1)
    static let cardStroke = Color.white.opacity(0.1)
    static let cardStrokeStrong = Color.white.opacity(0.18)
}
