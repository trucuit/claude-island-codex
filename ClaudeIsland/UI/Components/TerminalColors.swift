//
//  TerminalColors.swift
//  ClaudeIsland
//
//  Color palette: semantic tokens + legacy aliases
//

import SwiftUI

struct TerminalColors {

    // MARK: - Surface Hierarchy (dark-on-dark depth)

    static let surface0 = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let surface1 = Color(red: 0.09, green: 0.10, blue: 0.14)
    static let surface2 = Color(red: 0.13, green: 0.14, blue: 0.19)
    static let surface3 = Color(red: 0.17, green: 0.18, blue: 0.24)
    static let surfaceOverlay = Color.white.opacity(0.05)

    // MARK: - Semantic Status

    static let statusSuccess = Color(red: 0.34, green: 0.80, blue: 0.46)
    static let statusWarning = Color(red: 1.00, green: 0.76, blue: 0.28)
    static let statusDanger  = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let statusInfo    = Color(red: 0.42, green: 0.68, blue: 1.00)
    static let statusNeutral = Color.white.opacity(0.45)

    // MARK: - Brand Accents

    static let brandClaude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let brandCool   = Color(red: 0.34, green: 0.76, blue: 1.00)
    static let brandWarm   = Color(red: 0.99, green: 0.62, blue: 0.38)

    // MARK: - Text Hierarchy

    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary  = Color.white.opacity(0.42)
    static let textDisabled  = Color.white.opacity(0.22)

    // MARK: - Interactive States

    static let interactiveRest   = Color.white.opacity(0.08)
    static let interactiveHover  = Color.white.opacity(0.14)
    static let interactiveActive = Color.white.opacity(0.20)
    static let interactiveFocus  = brandCool.opacity(0.35)

    // MARK: - Stroke Hierarchy

    static let strokeSubtle  = Color.white.opacity(0.08)
    static let strokeDefault = Color.white.opacity(0.14)
    static let strokeStrong  = Color.white.opacity(0.22)

    // MARK: - Legacy Aliases (backward compat)

    static let green = statusSuccess
    static let amber = statusWarning
    static let red = statusDanger
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    static let blue = statusInfo
    static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)
    static let dim = textTertiary
    static let dimmer = textDisabled
    static let prompt = brandClaude
    static let background = interactiveRest
    static let backgroundHover = interactiveHover
    static let shellTop = surface1
    static let shellBottom = surface0
    static let shellStroke = strokeDefault
    static let shellStrokeStrong = strokeStrong
    static let shellHighlight = Color.white.opacity(0.34)
    static let shellCool = brandCool
    static let shellWarm = brandWarm
    static let card = interactiveRest
    static let cardHover = Color.white.opacity(0.1)
    static let cardStroke = strokeSubtle
    static let cardStrokeStrong = Color.white.opacity(0.18)
}
