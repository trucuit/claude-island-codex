//
//  DesignTokens.swift
//  ClaudeIsland
//
//  Shared typography, spacing, and radius tokens.
//

import SwiftUI

// MARK: - Typography

enum TypeStyle {
    static let displayLarge  = Font.system(size: 16, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 14, weight: .semibold, design: .rounded)

    static let bodyLarge  = Font.system(size: 13, weight: .regular)
    static let bodyMedium = Font.system(size: 12, weight: .regular)
    static let bodySmall  = Font.system(size: 11, weight: .regular)

    static let labelLarge  = Font.system(size: 12, weight: .semibold)
    static let labelMedium = Font.system(size: 11, weight: .semibold)
    static let labelSmall  = Font.system(size: 10, weight: .semibold)

    static let captionLarge = Font.system(size: 11, weight: .medium)
    static let captionSmall = Font.system(size: 10, weight: .medium)

    static let codeLarge  = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let codeMedium = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let codeSmall  = Font.system(size: 10, weight: .regular, design: .monospaced)

    static let badge = Font.system(size: 9, weight: .bold, design: .rounded)
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat  = 2
    static let xs: CGFloat   = 4
    static let sm: CGFloat   = 6
    static let md: CGFloat   = 8
    static let lg: CGFloat   = 12
    static let xl: CGFloat   = 16
    static let xxl: CGFloat  = 20
    static let xxxl: CGFloat = 24
}

// MARK: - Corner Radius

enum Radius {
    static let sm: CGFloat   = 6
    static let md: CGFloat   = 10
    static let lg: CGFloat   = 14
    static let xl: CGFloat   = 18
    static let full: CGFloat = 999
}
