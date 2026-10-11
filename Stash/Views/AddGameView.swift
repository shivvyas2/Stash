//
//  AddGameView.swift
//  Stash
//
//  The guided "Add Game" flow: pick what you have, choose where it goes, and
//  Stash does the rest. No bottles, prefixes or Wine jargon.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case installer, disc, folder, console, steam
        var id: String { rawValue }

        var title: String {
            switch self {
            case .installer: return "Installer"
            case .disc: return "Disc image"
            case .folder: return "Game folder"
            case .console: return "Console game"
            case .steam: return "Steam"
            }
        }

        var detail: String {
            switch self {
            case .installer: return "A setup.exe or .msi from a website, store or download"
            case .disc: return "An .iso, .cue or .dmg copied from a game disc"
            case .folder: return "A game that's already installed, e.g. copied from a Windows PC"
            case .console: return "A PlayStation, PS2, PS3, PSP, GameCube or Wii game you own"
            case .steam: return "Install Steam, sign in, and your Steam games appear in your library"
            }
        }

        var symbol: String {
            switch self {
            case .installer: return "shippingbox.fill"
            case .disc: return "opticaldisc.fill"
            case .folder: return "folder.fill"
            case .console: return "gamecontroller.fill"
            case .steam: return "cloud.fill"
            }
        }
    }

    enum Step { case source, details, working, bios, choose, done }

    @State private var step: Step = .source
    @State private var source: Source = .installer
    @State private var sourceURL: URL?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var installLocation = Self.savedInstallLocation
    @State private var copyFolder = true
    @State private var makeMacApp = true
    @State private var platform: Platform = .ps2
    @State private var appLocation = StashPaths.defaultAppsLocation

    @State private var status: [String] = []
    @State private var waitingForInstaller = false
    @State private var environment: URL?
    @State private var candidates: [URL] = []
    @State private var chosen: URL?
    @State private var addedGame: Game?
    @State private var failure: String?

    private static var savedInstallLocation: URL {
        UserDefaults.standard.url(forKey: "installLocation") ?? StashPaths.defaultInstallLocation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            Group {
                switch step {
                case .source: sourceStep
                case .details: detailsStep
                case .working: workingStep
                case .bios: biosStep
                case .choose: chooseStep
                case .done: doneStep
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 640, height: 560)
        .background(Theme.paper)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(28)).tracking(-0.8).foregroundStyle(Theme.ink).lineLimit(2)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if step != .working {
                Button("Cancel") { dismiss() }
                    .buttonStyle(TextLinkStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 22)
    }

    private var title: String {
        switch step {
        case .source: return "Add a game"
        case .details: return "Where should it go?"
        case .working: return "Setting up \(name)"
        case .bios: return "One more thing"
        case .choose: return "Which one starts the game?"
        case .done: return "\(name) is ready"
        }
    }

    private var subtitle: String {
        switch step {
        case .source: return "Choose what you have, or drop it anywhere in this window."
        case .details: return "Every game gets its own private space, so games never interfere with each other."
        case .working: return "This takes a minute. Stash is preparing everything the game needs."
        case .bios: return "\(platform.title) games need the BIOS from your own console to start."
        case .choose: return "Stash found several programs. Pick the one you'd double-click on Windows."
        case .done: return "Find it in your library, or press Play now."
        }
    }

    // MARK: Step 1: source

    private var sourceStep: some View {
        VStack(spacing: 0) {
            ForEach(Array(Source.allCases.enumerated()), id: \.element) { index, option in
                Button { pick(option) } label: {
                    HStack(spacing: 20) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.muted)
                            .frame(width: 22, alignment: .leading)
                        Image(systemName: option.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(option.detail).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
            Spacer()
            Text("Tip: drop a file or folder anywhere on this window.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in accept(url) }
            }
            return true
        }
    }

    private func pick(_ option: Source) {
        if option == .steam {
            startSteam()
            return
        }
        let panel = NSOpenPanel()
        switch option {
        case .installer:
            panel.allowedContentTypes = [.exe, .msi]
            panel.message = "Choose the game's installer"
        case .disc:
            panel.allowedContentTypes = [.diskImage, UTType(filenameExtension: "iso") ?? .diskImage,
                                         UTType(filenameExtension: "cue") ?? .data]
            panel.message = "Choose the disc image"
        case .folder:
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Choose the folder that contains the game"
        case .console:
            panel.allowedContentTypes = Platform.consoleFileExtensions.compactMap { UTType(filenameExtension: $0) }
            panel.canChooseDirectories = true
            panel.message = "Choose the game file (.iso, .chd, .cue, .rvz, .cso, .wbfs…) or a PS3 game folder"
        case .steam:
            return
        }
        if panel.runModal() == .OK, let url = panel.url { accept(url, as: option) }
    }

    private func accept(_ url: URL, as option: Source? = nil) {
        // PS3 games are folders, or the EBOOT.BIN inside one
        let ps3Game = Platform.ps3GameRoot(for: url)
        let url = ps3Game ?? url
        let ext = url.pathExtension.lowercased()
        let detected = ps3Game != nil ? .ps3 : url.hasDirectoryPath ? nil : Platform.detect(url)
        if ps3Game != nil {
            source = .console
        } else if let option {
            source = option
        } else if url.hasDirectoryPath {
            source = .folder
        } else if ext == "dmg" || (detected == nil && ["iso", "img"].contains(ext)) {
            source = .disc
        } else if detected != nil {
            source = .console
        } else {
            source = .installer
        }
        if source == .console { platform = detected ?? .ps2 }
        sourceURL = url
        if !nameEdited { name = Self.guessName(from: url, source: source) }
        step = .details
    }

    static func guessName(from url: URL, source: Source) -> String {
        if let title = Platform.ps3Title(at: url) { return title }
        var base = url.deletingPathExtension().lastPathComponent
        if source == .installer, ["setup", "install", "installer"].contains(base.lowercased()) {
            base = url.deletingLastPathComponent().lastPathComponent
        }
        return base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "setup", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Step 2: details

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Name") {
                TextField("Game name", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
                    .textFieldStyle(.roundedBorder)
            }
            if source == .console {
                field("Console") {
                    Picker("", selection: $platform) {
                        ForEach(Platform.allCases.filter(\.isConsole)) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                Toggle("Copy the game into this location", isOn: $copyFolder)
                    .help("Turn off to play the file from where it is now")
            }
            field("Install to") {
                locationPicker(installLocation, prompt: "Install Here") { installLocation = $0 }
            }
            if source == .folder {
                Toggle("Copy the game into this location (recommended)", isOn: $copyFolder)
                    .help("Turn off to play straight from the folder you picked, e.g. an external drive")
            }
            Toggle("Also create a Mac app for this game", isOn: $makeMacApp)
            if makeMacApp {
                field("Mac app in") {
                    locationPicker(appLocation, prompt: "Put App Here") { appLocation = $0 }
                }
            }
            Spacer()
            HStack {
                Button("Back") { step = .source }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Set Up Game") { start() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.switch)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            content()
        }
    }

    private func locationPicker(_ url: URL, prompt: String, set: @escaping (URL) -> Void) -> some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(Theme.muted)
            Text(url.path(percentEncoded: false)).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Change…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.directoryURL = url
                panel.prompt = prompt
                if panel.runModal() == .OK, let chosen = panel.url { set(chosen) }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 40)
        .card(radius: 8)
    }

    // MARK: Step 3: working

    private var workingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(status.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 12) {
                    if index == status.count - 1 && failure == nil {
                        ProgressView().controlSize(.small).frame(width: 18)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.positive).frame(width: 18)
                    }
                    Text(line).font(.system(size: 14))
                }
            }
            if waitingForInstaller {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.ink)
                    Text("Follow the installer's steps in its own window. Keep the suggested install folder, "
                         + "and untick options like \"Launch game\" or \"Install DirectX\". Stash already handles them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .card(radius: 10)
            }
            if let failure {
                Text(failure).font(.system(size: 13)).foregroundStyle(Theme.warning)
                Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
        }
    }

    private func start() {
        guard let sourceURL else { return }
        UserDefaults.standard.set(installLocation, forKey: "installLocation")
        step = .working
        if source == .console {
            startConsole(sourceURL)
            return
        }
        Task {
            do {
                status = ["Preparing a private Windows space"]
                try FileManager.default.createDirectory(at: installLocation, withIntermediateDirectories: true)
                let environment = try await library.createEnvironment(name: name, in: installLocation)
                self.environment = environment
                var searchIn = environment.appending(path: "drive_c")

                switch source {
                case .installer:
                    status.append("Running the installer")
                    waitingForInstaller = true
                    try await library.runInstaller(sourceURL, environment: environment)
                case .disc:
                    status.append("Opening the disc")
                    let volume = try mount(sourceURL)
                    defer { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", volume.path, "-quiet"]) }
                    let setup = try discInstaller(on: volume)
                    status.append("Running the installer")
                    waitingForInstaller = true
                    try await library.runInstaller(setup, environment: environment)
                case .folder:
                    if copyFolder {
                        status.append("Copying game files")
                        let target = environment.appending(path: "drive_c/Games")
                            .appending(path: sourceURL.lastPathComponent)
                        try await Task.detached {
                            try FileManager.default.createDirectory(
                                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
                            )
                            try FileManager.default.copyItem(at: sourceURL, to: target)
                        }.value
                        searchIn = target
                    } else {
                        searchIn = sourceURL
                    }
                case .console, .steam:
                    return // handled by startConsole and startSteam
                }
                waitingForInstaller = false

                status.append("Finding the game")
                let folder = searchIn
                candidates = await Task.detached { GameLibrary.findExecutables(in: folder) }.value
                guard let best = candidates.first else {
                    throw StashError("No game program was found. If the installer was cancelled, try again. "
                                     + "Otherwise remove the game and add its folder instead.")
                }
                chosen = best
                if candidates.count == 1 || KnownGame.matching(executable: best) != nil {
                    finish(with: best)
                } else {
                    step = .choose
                }
            } catch {
                waitingForInstaller = false
                failure = error.localizedDescription
            }
        }
    }

    private func startSteam() {
        if let existing = library.steamClient {
            library.selection = existing.id
            dismiss()
            return
        }
        source = .steam
        name = "Steam"
        step = .working
        Task {
            do {
                status = ["Getting Steam ready"]
                try FileManager.default.createDirectory(at: installLocation, withIntermediateDirectories: true)
                let game = try await library.addSteam(to: installLocation) { line in status.append(line) }
                addedGame = game
                step = .done
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func startConsole(_ file: URL) {
        guard let engine = ConsoleEngine.for(platform) else { return }
        Task {
            do {
                status = ["Getting the \(engine.displayName) ready"]
                try await library.engines.install(engine)
                if engine.needsBIOS && !engine.hasBIOS {
                    step = .bios
                    return
                }
                try await finishConsole(file)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func finishConsole(_ file: URL) async throws {
        step = .working
        status.append(copyFolder ? "Copying the game" : "Adding to your library")
        let game = try await library.addConsoleGame(
            name: name, platform: platform, file: file, copyTo: copyFolder ? installLocation : nil
        )
        if makeMacApp { _ = try? library.exportMacApp(game, to: appLocation) }
        addedGame = game
        step = .done
    }

    // MARK: BIOS (PlayStation only)

    private var biosStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cpu")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.ink)
                Text("Sony doesn't allow the BIOS to be shared, so Stash can't include it. Dump it from your own "
                     + "\(platform.title) (it's a .bin file, usually 512 KB for PlayStation or 4 MB for PS2) and choose it "
                     + "here. You only need to do this once.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button("Skip for Now") { Task { try? await finishConsole(sourceURL!) } }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Choose BIOS File…") {
                    let panel = NSOpenPanel()
                    panel.message = "Choose your \(platform.title) BIOS file"
                    guard panel.runModal() == .OK, let url = panel.url,
                          let engine = ConsoleEngine.for(platform), let sourceURL else { return }
                    Task {
                        do {
                            try library.engines.addBIOS(url, for: engine)
                            try await finishConsole(sourceURL)
                        } catch {
                            failure = error.localizedDescription
                            step = .working
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func mount(_ image: URL) throws -> URL {
        let output = try Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", image.path])
        guard let line = output.split(separator: "\n").last(where: { $0.contains("/Volumes/") }),
              let range = line.range(of: "/Volumes/") else {
            throw StashError("The disc image couldn't be opened.")
        }
        return URL(fileURLWithPath: String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces))
    }

    private func discInstaller(on volume: URL) throws -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: nil)) ?? []
        let preferred = ["setup.exe", "install.exe", "autorun.exe"]
        for name in preferred {
            if let match = files.first(where: { $0.lastPathComponent.lowercased() == name }) { return match }
        }
        if let exe = files.first(where: { $0.pathExtension.lowercased() == "exe" }) { return exe }
        throw StashError("No installer was found on this disc.")
    }

    // MARK: Step 4: choose executable

    private var chooseStep: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(candidates.prefix(20), id: \.self) { url in
                        Button { chosen = url } label: {
                            HStack(spacing: 12) {
                                if let icon = GameLibrary.icon(for: url) {
                                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: "app.dashed").frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold))
                                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                Image(systemName: chosen == url ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen == url ? Theme.accent : Theme.muted)
                            }
                            .padding(10)
                            .background(chosen == url ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen == url ? Theme.ink : Theme.hairline))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Continue") { if let chosen { finish(with: chosen) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(chosen == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish(with executable: URL) {
        guard let environment else { return }
        if !nameEdited, let known = KnownGame.matching(executable: executable) { name = known.title }
        let game = library.addGame(name: name, environment: environment, executable: executable, cover: nil)
        if makeMacApp { _ = try? library.exportMacApp(game, to: appLocation) }
        addedGame = game
        step = .done
    }

    // MARK: Step 5: done

    private var doneStep: some View {
        VStack(spacing: 18) {
            if let game = addedGame {
                CoverArt(game: game, image: library.cover(for: game.id), titleSize: 16).frame(width: 150)
                if game.platform.isConsole {
                    Label("Starts fullscreen at 3× resolution. Quit the game (⌘Q) to come back to Stash.",
                          systemImage: "sparkles")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                } else if game.isSteamClient {
                    Label("Sign in to Steam and install games there. They appear in your Stash library after you close Steam.",
                          systemImage: "sparkles")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                } else if game.knownGame != nil {
                    Label("Stash recognised this game. One-click upgrades are waiting under Enhancements.",
                          systemImage: "sparkles")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                HStack {
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        library.play(game.id)
                        dismiss()
                    } label: { Label("Play now", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
