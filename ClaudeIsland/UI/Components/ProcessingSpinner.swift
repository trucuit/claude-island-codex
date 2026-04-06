//
//  ProcessingSpinner.swift
//  ClaudeIsland
//
//  Smooth arc spinner for processing state. Replaces the legacy
//  timer-based unicode symbol cycler with a 60fps angular gradient arc.
//

import SwiftUI

// MARK: - ProcessingArc

struct ProcessingArc: View {
    let color: Color
    let size: CGFloat

    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(color: Color = TerminalColors.brandClaude, size: CGFloat = 10) {
        self.color = color
        self.size = size
    }

    var body: some View {
        Group {
            if reduceMotion {
                // Static dot — no spinning for reduced-motion users
                Circle()
                    .fill(color)
                    .frame(width: size * 0.4, height: size * 0.4)
            } else {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0), color]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(234)
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
        }
    }
}

// MARK: - ProcessingSpinner (backward-compatibility wrapper)

/// Thin wrapper kept so existing call sites compile without changes.
/// Internally delegates to ProcessingArc.
struct ProcessingSpinner: View {
    var body: some View {
        ProcessingArc(color: TerminalColors.brandClaude, size: 12)
    }
}

// MARK: - Previews

#Preview("Arc — default") {
    ProcessingArc()
        .frame(width: 30, height: 30)
        .background(.black)
}

#Preview("Spinner wrapper") {
    ProcessingSpinner()
        .frame(width: 30, height: 30)
        .background(.black)
}
