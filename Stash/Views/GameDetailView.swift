//
//  GameDetailView.swift
//  Stash
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct GameDetailView: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game

    enum Tab: String, CaseIterable { case enhancements = "Enhancements", graphics = "Graphics", files = "Files" }
    @State private var tab: Tab = .enhancements
    @State private var confirmRemove = false
    @State private var showArtwork = false

    private var current: Game { library[game.id] ?? game }
    private var isRunning: Bool { library.running.contains(game.id) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { library.selection = nil } label: { Label("Library", systemImage: "chevron.left") }
                        .buttonStyle(TextLinkStyle())
                        .padding(.bottom, 24)
                    header.padding(.bottom, 36)
                    stats.padding(.bottom, 36)
                    TextTabs(tabs: Tab.allCases, selection: $tab) { $0.rawValue }
                    Hairline().padding(.bottom, 24)
                    switch tab {
                    case .enhancements: EnhancementsPanel(game: current)
                    case .graphics: GraphicsPanel(game: current)
                    case .files: FilesPanel(game: current)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 48)
                .padding(.bottom, 40)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            ActivityPanel(game: current)
                .frame(width: 320)
        }
        .sheet(isPresented: $showArtwork) { ArtworkPicker(game: current) }
        .confirmationDialog("Remove \(current.name)?", isPresented: $confirmRemove) {
            Button("Remove from Stash") { library.remove(current, deleteFiles: false) }
            Button("Remove and Move Game Files to Trash", role: .destructive) {
                library.remove(current, deleteFiles: true)
            }
        } message: {
            Text("Game files live in \(current.environmentPath).")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 28) {
            CoverArt(game: current, image: library.cover(for: game.id), titleSize: 22)
                .frame(width: 210)
                .overlay {
                    if library.fetchingArtwork.contains(game.id) {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .onTapGesture { showArtwork = true }
                .onDrop(of: [.fileURL], isTargeted: nil, perform: dropCover)
                .help("Drop an image here to set the cover")

            VStack(alignment: .leading, spacing: 0) {
                Eyebrow([current.platform.title, current.knownGame?.year].compactMap { $0 }.joined(separator: " — "))
                    .padding(.bottom, 10)
                Text(current.name)
                    .font(.display(40)).tracking(-1.1)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 10)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 22)

                HStack(spacing: 8) {
                    if isRunning {
                        Button { library.stop(current) } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(PrimaryButtonStyle(color: Theme.ink))
                    } else {
                        Button { library.play(game.id) } label: { Label("Play", systemImage: "play.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([current.executableURL])
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Menu {
                        Button("Find Artwork…") { showArtwork = true }
                        Button("Choose Cover Image…", action: chooseCover)
                        if !current.platform.isConsole {
                            Button("Use Game Icon as Cover") {
                                library.setCover(GameLibrary.icon(for: current.executableURL), for: game.id)
                            }
                        }
                        Divider()
                        Button("Remove Game…", role: .destructive) { confirmRemove = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                    .card(radius: 8)
                }
            }
        }
    }

    private var subtitle: String {
        if isRunning { return "Playing now" }
        if let last = current.lastPlayed { return "Last played \(last.formatted(.relative(presentation: .named)))" }
        return "Ready to play"
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: 0) {
            stat("Playtime", current.totalPlaytime.playtimeString)
            divider
            stat("Sessions", "\(current.sessions.count)")
            divider
            if current.platform.isConsole {
                stat("Resolution", "\(current.upscale)×")
                divider
                stat("Aspect", current.widescreen ? "16:9" : "4:3")
            } else {
                stat("Renderer", current.graphics == .metal ? "Metal" : "DXVK")
                divider
                stat("Upgrades", "\(current.installedMods.count)")
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Hairline(color: Theme.ink) }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 44).padding(.horizontal, 20)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            Text(value).font(.display(26)).tracking(-0.6).foregroundStyle(Theme.ink).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cover helpers

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose cover art for \(current.name)"
        if panel.runModal() == .OK, let url = panel.url {
            library.setCover(NSImage(contentsOf: url), for: game.id)
        }
    }

    private func dropCover(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in library.setCover(image, for: game.id) }
        }
        return true
    }
}

// MARK: - Dark activity panel

private struct ActivityPanel: View {
    let game: Game

    private var week: [(label: String, value: TimeInterval)] {
        let values = game.playtimeByDay()
        let calendar = Calendar.current
        return values.enumerated().map { index, value in
            let day = calendar.date(byAdding: .day, value: index - (values.count - 1), to: Date())!
            return (day.formatted(.dateTime.weekday(.narrow)), value)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("This Week").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .padding(.bottom, 4)
                Text(weekTotal).font(.system(size: 12)).foregroundStyle(Theme.nightMuted)
                    .padding(.bottom, 20)
                chart.padding(.bottom, 36)

                Text("Activity").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .padding(.bottom, 8)
                if events.isEmpty {
                    Text("Your sessions show up here after you play.")
                        .font(.system(size: 12)).foregroundStyle(Theme.nightMuted)
                }
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 12) {
                        Image(systemName: event.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Theme.nightRaised, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(Theme.nightMuted)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    Hairline(color: Theme.nightRaised)
                }

                if let tips = game.knownGame?.tips, !tips.isEmpty {
                    Text("Notes").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        .padding(.top, 36).padding(.bottom, 8)
                    ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.nightMuted).monospacedDigit()
                            Text(tip).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                        Hairline(color: Theme.nightRaised)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 52)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .background(Theme.night)
    }

    private var weekTotal: String {
        let total = week.reduce(0) { $0 + $1.value }
        return total > 0 ? "\(total.playtimeString) played in the last 7 days" : "No play in the last 7 days"
    }

    private var chart: some View {
        let peak = max(week.map(\.value).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == week.count - 1 ? Theme.accent : (day.value > 0 ? Color.white : Theme.nightRaised))
                        .frame(width: 18, height: max(4, 72 * day.value / peak))
                    Text(day.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.nightMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92, alignment: .bottom)
    }

    private var events: [(date: Date, title: String, symbol: String)] {
        let sessions = game.sessions.map { (date: $0.start, title: "Played \($0.duration.playtimeString)", symbol: "gamecontroller.fill") }
        let mods = game.installedMods.compactMap { id, date in
            ModPackage.byID(id).map { (date: date, title: "Installed \($0.title)", symbol: "sparkles") }
        }
        return Array((sessions + mods).sorted { $0.date > $1.date }.prefix(25))
    }
}
