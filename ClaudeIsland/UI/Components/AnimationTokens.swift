//
//  AnimationTokens.swift
//  ClaudeIsland
//
//  Centralized animation presets for consistent motion language.
//

import SwiftUI

// MARK: - Animation Presets

enum NotchAnimation {
    // Shell
    static let shellOpen       = Animation.spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)
    static let shellClose      = Animation.spring(response: 0.38, dampingFraction: 1.0,  blendDuration: 0)
    static let shellExpand     = Animation.smooth(duration: 0.3)
    // Content
    static let contentSwitch   = Animation.spring(response: 0.30, dampingFraction: 0.85)
    static let containerResize = Animation.spring(response: 0.35, dampingFraction: 0.85)
    // Interaction
    static let hover           = Animation.spring(response: 0.25, dampingFraction: 0.80)
    static let press           = Animation.spring(response: 0.20, dampingFraction: 0.60)
    static let disclosure      = Animation.spring(response: 0.25, dampingFraction: 0.80)
    // Status
    static let statusChange    = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let staggeredReveal = Animation.spring(response: 0.30, dampingFraction: 0.70)
    static let listEntrance    = Animation.spring(response: 0.35, dampingFraction: 0.80)
    static func listDelay(index: Int) -> Animation { listEntrance.delay(Double(index) * 0.035) }
    // Attention
    static let attentionPulse  = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    static let breathe         = Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)
    static let bounce          = Animation.spring(response: 0.25, dampingFraction: 0.40)
    static let flash           = Animation.easeOut(duration: 0.6)
    // Scroll
    static let scrollToBottom  = Animation.easeOut(duration: 0.30)
}

// MARK: - Reduced Motion Modifier

extension View {
    /// Applies `animation` only when the user has not requested reduced motion.
    func motionSafe<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionSafeModifier(animation: animation, value: value))
    }
}

private struct MotionSafeModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Named Transitions

extension AnyTransition {
    /// Sessions → chat (slide left)
    static var slideToChat: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96))
        )
    }
    /// Chat → sessions (slide right)
    static var slideToSessions: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
        )
    }
    /// Approval / input bar rising from bottom
    static var riseFromBottom: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity)
    }
    /// Panel content fade (menu, settings)
    static var panelFade: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 4)), removal: .opacity)
    }
}
