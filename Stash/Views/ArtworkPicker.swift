//
//  ArtworkPicker.swift
//  Stash
//
//  Search SteamGridDB and pick a cover, or an app icon, for a game.
//

import SwiftUI

struct ArtworkPicker: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    let game: Game
    /// Covers show in Stash; icons go on the game's Mac app. They're separate images.
    enum Kind { case cover, icon }
    var kind: Kind = .cover

    @State private var query = ""
    @State private var matches: [ArtworkGame] = []
    @State private var selected: ArtworkGame?
    @State private var covers: [Artwork] = []
    @State private var loading = false
    @State private var applying: Artwork.ID?
    @State private var message: String?
    @State private var officialIcons: [(name: String, image: NSImage)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind == .cover ? "Artwork" : "App Icon").font(.display(28)).tracking(-0.8)
                        .foregroundStyle(Theme.ink)
                    Text(kind == .cover ? "Covers from SteamGridDB" : "Icons from SteamGridDB, for the game's Mac app")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
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

            if kind == .icon && !officialIcons.isEmpty {
                Text("From the game's files").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 8)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(officialIcons.indices, id: \.self) { index in
                            let icon = officialIcons[index]
                            Button {
                                library.setAppIcon(icon.image, for: game.id)
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: icon.image).resizable().interpolation(.high)
                                        .aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                                    Text(icon.name).font(.system(size: 11)).foregroundStyle(Theme.ink)
                                        .lineLimit(1).frame(width: 76)
                                }
                                .padding(6)
                                .card(radius: 8)
                            }
                            .buttonStyle(.plain)
                            .help("\(icon.name).exe · \(Int(icon.image.size.width)) px")
                        }
                    }
                }
                .scrollIndicators(.never)
                .padding(.bottom, 14)
            }

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
                                        image.resizable().aspectRatio(contentMode: kind == .cover ? .fill : .fit)
                                    } placeholder: {
                                        Theme.hairline
                                    }
                                    .aspectRatio(kind == .cover ? 2 / 3 : 1, contentMode: .fit)
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
            query = ArtworkService.searchTitle(for: game.knownGame?.title ?? game.name)
            if kind == .icon {
                let game = game
                officialIcons = await Task.detached { GameLibrary.officialIcons(for: game) }.value
            }
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
            switch kind {
            case .cover:
                covers = try await ArtworkService.covers(for: match.id)
                message = covers.isEmpty ? "No covers for this game yet." : nil
            case .icon:
                covers = try await ArtworkService.icons(for: match.id)
                message = covers.isEmpty ? "No icons for this game yet. Try another match above." : nil
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ cover: Artwork) {
        applying = cover.id
        Task {
            do {
                let image = try await ArtworkService.image(at: cover.url)
                switch kind {
                case .cover: library.setCover(image, for: game.id)
                case .icon: library.setAppIcon(image, for: game.id)
                }
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            applying = nil
        }
    }
}
