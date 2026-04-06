//
//  SessionSearchBar.swift
//  ClaudeIsland
//
//  Search bar and quick filter chips for the sessions list.
//

import SwiftUI

// MARK: - SessionFilter

enum SessionFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case today = "Today"
    case thisWeek = "This Week"

    func matches(_ session: SessionState) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            // Active = not idle and not ended
            switch session.phase {
            case .idle, .ended: return false
            default: return true
            }
        case .today:
            return Calendar.current.isDateInToday(session.lastActivity)
        case .thisWeek:
            return Calendar.current.isDate(session.lastActivity, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }
}

// MARK: - SessionSearchBar

struct SessionSearchBar: View {
    @Binding var searchText: String
    @Binding var activeFilter: SessionFilter

    var body: some View {
        VStack(spacing: 6) {
            searchField
            filterChips
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            TextField("Search sessions…", text: $searchText)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.88))
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func filterChip(_ filter: SessionFilter) -> some View {
        let isActive = activeFilter == filter
        return Button {
            activeFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isActive ? .black : .white.opacity(0.65))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? TerminalColors.blue : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
