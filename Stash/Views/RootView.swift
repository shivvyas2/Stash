//
//  RootView.swift
//  Stash
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var runtime: RuntimeManager
    @State private var showAddGame = false

    private var selectedGame: Game? { library.selection.flatMap { library[$0] } }

    var body: some View {
        Group {
            if runtime.phase != .ready {
                OnboardingView()
            } else {
                HStack(spacing: 0) {
                    SidebarView(showAddGame: $showAddGame)
                        .frame(width: 228)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                    Group {
                        if let game = selectedGame {
                            GameDetailView(game: game).id(game.id)
                        } else {
                            LibraryGridView(showAddGame: $showAddGame)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Theme.paper)
        .focusEffectDisabled()
        .ignoresSafeArea()
        .sheet(isPresented: $showAddGame) {
            AddGameView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashAddGame)) { _ in
            if runtime.phase == .ready { showAddGame = true }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .task { await runtime.checkForUpdate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runtime.recheckRosetta()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashNeedsRosetta)) { _ in
            runtime.recheckRosetta()
        }
    }
}

// MARK: - Library grid

struct LibraryGridView: View {
    @EnvironmentObject private var library: GameLibrary
    @Binding var showAddGame: Bool

    private var games: [Game] {
        library.games.sorted { ($0.lastPlayed ?? $0.addedAt) > ($1.lastPlayed ?? $1.addedAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("\(library.games.count) \(library.games.count == 1 ? "game" : "games")")
                        Text("Library").font(.display(44)).tracking(-1.2).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { showAddGame = true } label: { Label("Add Game", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.bottom, 20)
                Hairline().padding(.bottom, 28)

                if games.isEmpty {
                    EmptyLibrary(showAddGame: $showAddGame)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 28, alignment: .top)],
                              alignment: .leading, spacing: 36) {
                        ForEach(games) { game in
                            Button { library.selection = game.id } label: { GridCard(game: game) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 52)
            .padding(.bottom, 40)
        }
    }
}

private struct GridCard: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverArt(game: game, image: library.cover(for: game.id))
                .overlay(alignment: .bottomTrailing) {
                    if library.running.contains(game.id) {
                        Text("PLAYING").font(.eyebrow).tracking(1).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.positive, in: RoundedRectangle(cornerRadius: 5))
                            .padding(10)
                    }
                }
                .offset(y: hovering ? -3 : 0)
                .shadow(color: .black.opacity(hovering ? 0.14 : 0), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(meta).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { self.hovering = hovering } }
    }

    private var meta: String {
        let time = game.totalPlaytime > 0 ? "\(game.totalPlaytime.playtimeString) played" : "Not played yet"
        return "\(game.platform.title) · \(time)"
    }
}

private struct EmptyLibrary: View {
    @Binding var showAddGame: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nothing here yet.")
                .font(.display(28)).tracking(-0.6).foregroundStyle(Theme.ink)
                .padding(.bottom, 8)
            Text("Add a Windows game from an installer, disc image or folder, or a PlayStation, PSP, GameCube "
                 + "or Wii game you own.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.bottom, 24)
            Button { showAddGame = true } label: { Label("Add your first game", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 40)
    }
}
