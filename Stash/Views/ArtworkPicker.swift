//
//  ArtworkPicker.swift
//  Stash
//
//  Search SteamGridDB and pick a cover for a game.
//

import SwiftUI

struct ArtworkPicker: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var query = ""
    @State private var matches: [ArtworkGame] = []
    @State private var selected: ArtworkGame?
    @State private var covers: [Artwork] = []
    @State private var loading = false
    @State private var applying: Artwork.ID?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artwork").font(.display(28)).tracking(-0.8).foregroundStyle(Theme.ink)
                    Text("Covers from SteamGridDB").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(TextLinkStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    TextField("Game name", text: $query).textFieldStyle(.plain).onSubmit { Task { await search() } }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .card(radius: 8)
                Button("Search") { Task { await search() } }.buttonStyle(PrimaryButtonStyle(color: Theme.ink))
            }
            .padding(.bottom, 14)

            if !matches.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(matches.prefix(12)) { match in
                            Button { Task { await load(match) } } label: {
                                Text([match.name, match.year].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12, weight: selected == match ? .semibold : .regular))
                                    .foregroundStyle(selected == match ? Color.white : Theme.ink)
                                    .padding(.horizontal, 10).frame(height: 28)
                                    .background(selected == match ? Theme.ink : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(selected == match ? .clear : Theme.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding(.bottom, 14)
            }
            Hairline().padding(.bottom, 16)

            Group {
                if let message {
                    Text(message).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                            ForEach(covers) { cover in
                                Button { apply(cover) } label: {
                                    AsyncImage(url: cover.thumb) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Theme.hairline
                                    }
                                    .aspectRatio(2 / 3, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        if applying == cover.id {
                                            ZStack { Color.black.opacity(0.4); ProgressView().tint(.white) }
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(28)
        .frame(width: 680, height: 600)
        .background(Theme.paper)
        .task {
            query = game.knownGame?.title ?? game.name
            await search()
        }
    }

    private func search() async {
        message = nil
        loading = true
        defer { loading = false }
        do {
            matches = try await ArtworkService.search(query)
            if let first = matches.first {
                await load(first)
            } else {
                covers = []
                message = "No games found for “\(query)”. Try a shorter name."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func load(_ match: ArtworkGame) async {
        selected = match
        loading = true
        defer { loading = false }
        do {
            covers = try await ArtworkService.covers(for: match.id)
            message = covers.isEmpty ? "No covers for this game yet." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ cover: Artwork) {
        applying = cover.id
        Task {
            do {
                library.setCover(try await ArtworkService.image(at: cover.url), for: game.id)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            applying = nil
        }
    }
}
