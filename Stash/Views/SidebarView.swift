//
//  SidebarView.swift
//  Stash
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var library: GameLibrary
    @Binding var showAddGame: Bool
    @State private var search = ""

    private var filtered: [Game] {
        let sorted = library.games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stash.")
                .font(.display(22)).tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .padding(.top, 48)
                .padding(.bottom, 22)
                .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField("Search", text: $search).textFieldStyle(.plain).font(.system(size: 12.5))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .padding(.bottom, 18)

            NavRow(title: "Library", symbol: "square.grid.2x2", selected: library.selection == nil) {
                library.selection = nil
            }
            NavRow(title: "Add Game", symbol: "plus", selected: false) { showAddGame = true }

            HStack {
                Eyebrow("Games")
                Spacer()
                Text("\(library.games.count)").font(.eyebrow).foregroundStyle(Theme.muted).monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filtered) { game in
                        GameRow(game: game, selected: library.selection == game.id,
                                running: library.running.contains(game.id))
                            .onTapGesture { library.selection = game.id }
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            Hairline()
            SettingsLink {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.system(size: 12))
                    Text("Settings").font(.system(size: 12.5))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}

private struct NavRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(selected ? Theme.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GameRow: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game
    let selected: Bool
    let running: Bool

    var body: some View {
        HStack(spacing: 10) {
            CoverThumbnail(game: game, image: library.cover(for: game.id))
            Text(game.name).font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 4)
            if running {
                Circle().fill(Theme.positive).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(selected ? Theme.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
