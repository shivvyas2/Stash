//
//  GamePanels.swift
//  Stash
//
//  The Enhancements / Graphics / Files tabs on a game's page.
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// Section heading used inside the tabs
private struct SectionHeading: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(title, color: Theme.ink)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted) }
        }
        .padding(.bottom, 10)
    }
}

// MARK: - Enhancements

struct EnhancementsPanel: View {
    let game: Game

    private var mods: [ModPackage] {
        var mods = game.knownGame?.mods.compactMap(ModPackage.byID) ?? []
        if game.engine == .classic, let api = game.legacyAPI { mods.insert(ModPackage.scaling(for: api), at: 0) }
        return mods
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mods.isEmpty {
                Text(game.platform.isConsole
                     ? "Resolution and widescreen for this game live under Graphics."
                     : "No one-click upgrades for this game yet. Retina rendering and the performance overlay "
                       + "under Graphics work with every game.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                SectionHeading(title: "Upgrades",
                               detail: "Community mods. Every file they change is backed up, so removing one restores the original game.")
                Hairline()
                ForEach(Array(mods.enumerated()), id: \.element.id) { index, mod in
                    ModRow(game: game, mod: mod, index: index + 1)
                    Hairline()
                }

                let toggles = mods.filter { game.installedMods[$0.id] != nil }.flatMap(\.toggles)
                if !toggles.isEmpty {
                    SectionHeading(title: "Fine-tune").padding(.top, 32)
                    Hairline()
                    ForEach(toggles) { toggle in
                        IniToggleRow(game: game, toggle: toggle)
                        Hairline()
                    }
                }
            }
        }
    }
}

private struct ModRow: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game
    let mod: ModPackage
    let index: Int

    private var installed: Bool { game.installedMods[mod.id] != nil }
    private var working: Bool { library.isWorking(on: mod, for: game.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(String(format: "%02d", index))
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(Theme.muted)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(mod.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    if installed {
                        Text("ON").font(.eyebrow).tracking(1).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.positive, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(mod.summary).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            if working {
                ProgressView().controlSize(.small).frame(width: 80)
            } else if installed {
                Button("Remove") { library.uninstall(mod, for: game.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(library.running.contains(game.id))
            } else {
                Button("Install") { library.install(mod, for: game.id) }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.ink))
                    .disabled(library.running.contains(game.id))
            }
        }
        .padding(.vertical, 16)
    }
}

private struct IniToggleRow: View {
    let game: Game
    let toggle: ModToggle
    @State private var isOn = false

    private var file: URL { game.gameFolderURL.appending(path: toggle.file) }

    var body: some View {
        SettingToggle(title: toggle.title, detail: toggle.detail, isOn: $isOn)
            .onAppear { isOn = IniFile.value(file: file, section: toggle.section, key: toggle.key) == "1" }
            .onChange(of: isOn) { _, value in
                try? IniFile.set(file: file, section: toggle.section, key: toggle.key, value: value ? "1" : "0")
            }
    }
}

// MARK: - Graphics

/// A row of mutually exclusive options; the selected one is solid ink
private struct OptionStrip<Value: Hashable>: View {
    let options: [(value: Value, title: String, detail: String)]
    let selection: Value
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Button { select(option.value) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.title).font(.system(size: 14, weight: .bold))
                        Text(option.detail).font(.system(size: 11))
                            .opacity(0.7)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundStyle(selected ? Color.white : Theme.ink)
                    .background(selected ? Theme.ink : Theme.surface)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 1) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct GraphicsPanel: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if game.platform.isConsole, let engine = ConsoleEngine.for(game.platform) {
                SectionHeading(title: "Resolution", detail: "How sharp the game is drawn. Higher needs more GPU.")
                OptionStrip(options: Game.upscaleOptions(for: game.platform).map { ($0.scale, $0.title, $0.detail) },
                            selection: game.upscale) { value in library.update(game.id) { $0.upscale = value } }
                    .padding(.bottom, 28)
                if engine.supportsWidescreen {
                    Hairline()
                    SettingToggle(title: "Widescreen",
                                  detail: "Shows more of the world in 16:9 instead of stretching 4:3",
                                  isOn: Binding(get: { game.widescreen },
                                                set: { value in library.update(game.id) { $0.widescreen = value } }))
                }
            } else {
                // Steam needs the classic engine: its window doesn't show on the modern one
                if !game.isSteam {
                    SectionHeading(title: "Engine")
                    OptionStrip(options: WineEngine.allCases.map { ($0, $0.title, $0.detail) },
                                selection: game.engine, select: chooseEngine)
                        .padding(.bottom, 28)
                }
                if game.engine == .modern {
                    SectionHeading(title: "Renderer")
                    OptionStrip(options: GraphicsMode.allCases.map { ($0, $0.title, $0.detail) },
                                selection: game.graphics) { value in library.update(game.id) { $0.graphics = value } }
                        .padding(.bottom, 28)
                }
                Hairline()
                SettingToggle(title: "High resolution (Retina)",
                              detail: "Render at your display's full pixel density instead of upscaling",
                              isOn: Binding(get: { game.retina }, set: { library.setRetina($0, for: game.id) }))
            }
            Hairline()
            SettingToggle(title: "Performance overlay", detail: "Shows FPS, frame time and GPU use while you play",
                          isOn: Binding(get: { game.fpsOverlay },
                                        set: { value in library.update(game.id) { $0.fpsOverlay = value } }))
            Hairline()
            if !game.platform.isConsole {
                HStack {
                    label("Windows version", "Some older games prefer Windows XP or 7")
                    Spacer()
                    Picker("", selection: Binding(get: { game.windowsVersion },
                                                  set: { library.setWindowsVersion($0, for: game.id) })) {
                        ForEach(WinVersion.allCases.reversed(), id: \.self) { Text($0.pretty()).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Hairline()
                HStack {
                    label("Launch options", "Extra arguments passed to the game")
                    Spacer()
                    TextField("e.g. -windowed", text: Binding(
                        get: { game.arguments },
                        set: { value in library.update(game.id) { $0.arguments = value } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                }
                Hairline()
            }
        }
    }

    private func chooseEngine(_ engine: WineEngine) {
        let upgraded = FileManager.default.fileExists(atPath: game.environmentURL.appending(path: ".stash-classic").path)
        if engine == .modern && upgraded {
            library.lastError = "\(game.name) has already been set up for the classic engine and can't switch back. "
                + "To try the modern engine, uninstall the game and add it again."
            return
        }
        library.setEngine(engine, for: game.id)
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Files

struct FilesPanel: View {
    @EnvironmentObject private var library: GameLibrary
    let game: Game
    @State private var size: Int64?
    @State private var runningTool = false
    @State private var exportedApp: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            row("Location", game.environmentPath) {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([game.environmentURL]) }
            }
            row("Size", size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Calculating…") {
                EmptyView()
            }
            row("Starts with", game.executableURL.lastPathComponent) {
                Button("Change…", action: changeExecutable)
            }
            if !game.platform.isConsole {
                row("Patches & tools", "Run an update, mod installer or launcher inside this game") {
                    if runningTool { ProgressView().controlSize(.small) } else { Button("Run…", action: runTool) }
                }
            }
            row("Mac app", exportedApp?.path(percentEncoded: false) ?? "Launch from Launchpad, the Dock or Spotlight") {
                Button("Create…", action: exportApp)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .task(id: game.environmentPath) {
            let url = game.environmentURL
            size = await Task.detached { url.folderSize }.value
        }
    }

    private func row<Accessory: View>(
        _ title: String, _ value: String, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Eyebrow(title).frame(width: 120, alignment: .leading)
                Text(value).font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                accessory()
            }
            .frame(minHeight: 52)
            Hairline()
        }
    }

    private func changeExecutable() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = game.platform.isConsole ? [.data] : [.exe]
        panel.directoryURL = game.gameFolderURL
        panel.message = "Choose the file that starts \(game.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.update(game.id) {
            $0.executablePath = url.path(percentEncoded: false)
            $0.knownGameID = KnownGame.matching(executable: url)?.id ?? $0.knownGameID
        }
    }

    private func runTool() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe, .msi]
        panel.message = "Choose a Windows program to run inside \(game.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runningTool = true
        Task {
            do {
                try await library.runInstaller(url, environment: game.environmentURL, engine: game.engine)
            } catch {
                library.lastError = error.localizedDescription
            }
            runningTool = false
        }
    }

    private func exportApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = StashPaths.defaultAppsLocation
        panel.prompt = "Create App Here"
        panel.message = "Where should the \(game.name) app go?"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let app = try library.exportMacApp(game, to: folder)
            exportedApp = app
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            library.lastError = "Couldn't create the app: \(error.localizedDescription)"
        }
    }
}

extension UTType {
    static let msi = UTType(filenameExtension: "msi") ?? .data
}
