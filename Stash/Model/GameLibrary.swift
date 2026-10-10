//
//  GameLibrary.swift
//  Stash
//

import AppKit
import Foundation
import SemanticVersion
import WhiskyKit

@MainActor
final class GameLibrary: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var selection: Game.ID?
    @Published private(set) var running: Set<Game.ID> = []
    /// Mod ids currently being installed or removed, per game
    @Published private(set) var modsInFlight: [Game.ID: Set<String>] = [:]
    @Published var lastError: String?
    /// Games whose cover art is being fetched
    @Published private(set) var fetchingArtwork: Set<Game.ID> = []

    let engines = EngineManager()
    private var bottles: [Game.ID: Bottle] = [:]

    init() {
        load()
    }

    subscript(id: Game.ID) -> Game? { games.first { $0.id == id } }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: StashPaths.library),
              let decoded = try? JSONDecoder().decode([Game].self, from: data) else { return }
        games = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: StashPaths.data, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(games).write(to: StashPaths.library, options: .atomic)
        } catch {
            lastError = "Could not save your library: \(error.localizedDescription)"
        }
    }

    func update(_ id: Game.ID, _ change: (inout Game) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        change(&games[index])
        save()
    }

    func bottle(for game: Game) -> Bottle {
        if let bottle = bottles[game.id] { return bottle }
        let bottle = Bottle(bottleUrl: game.environmentURL, isAvailable: true)
        bottles[game.id] = bottle
        return bottle
    }

    // MARK: - Creating games

    /// Creates a fresh Windows environment in `location`/`name`
    func createEnvironment(name: String, in location: URL) async throws -> URL {
        var folder = location.appending(path: Self.safeFileName(name))
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = location.appending(path: "\(Self.safeFileName(name)) \(suffix)")
            suffix += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let bottle = Bottle(bottleUrl: folder, isAvailable: true)
        bottle.settings.name = name
        bottle.settings.windowsVersion = .win10
        _ = try await Wine.changeWinVersion(bottle: bottle, win: .win10)
        let wineVersion = try await Wine.wineVersion()
        bottle.settings.wineVersion = SemanticVersion(wineVersion) ?? SemanticVersion(0, 0, 0)
        try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)
        return folder
    }

    /// Runs a Windows installer (.exe or .msi) inside an environment and waits for it to exit
    func runInstaller(_ installer: URL, environment: URL) async throws {
        let bottle = Bottle(bottleUrl: environment, isAvailable: true)
        for await _ in try Wine.runWineProcess(
            name: installer.lastPathComponent,
            args: ["start", "/wait", "/d", installer.deletingLastPathComponent().windowsPath,
                   "/unix", installer.path(percentEncoded: false)],
            bottle: bottle
        ) { }
    }

    /// Executables inside `folder` that are likely the game, best guess first
    nonisolated static func findExecutables(in folder: URL) -> [URL] {
        let skip = ["unins", "setup", "install", "redist", "vcredist", "dxsetup", "crash", "report",
                    "update", "helper", "dotnet", "directx", "physx", "launcherpatcher"]
        let systemFolders = ["windows", "programdata", "users", "microsoft.net"]
        // Wine ships stub apps in Program Files; they are never the game
        let wineStubFolders = ["internet explorer", "windows media player", "windows nt", "common files"]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [(url: URL, score: Int)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
                if (systemFolders.contains(name) && parent == "drive_c")
                    || (wineStubFolders.contains(name) && parent.hasPrefix("program files")) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "exe", !skip.contains(where: name.contains) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var score = size / 100_000
            if KnownGame.matching(executable: url) != nil { score += 1_000_000 }
            results.append((url, score))
        }
        return results.sorted { $0.score > $1.score }.map(\.url)
    }

    @discardableResult
    func addGame(name: String, environment: URL, executable: URL, cover: NSImage?) -> Game {
        let game = Game(
            name: name,
            environmentPath: environment.path(percentEncoded: false),
            executablePath: executable.path(percentEncoded: false),
            knownGameID: KnownGame.matching(executable: executable)?.id
        )
        games.append(game)
        save()
        setCover(cover ?? Self.icon(for: executable), for: game.id)
        selection = game.id
        fetchArtwork(for: game.id)
        return game
    }

    /// Adds a console game. When `copyTo` is set the file is copied into a folder Stash owns;
    /// otherwise it's played in place and Stash never deletes anything around it.
    func addConsoleGame(name: String, platform: Platform, file: URL, copyTo location: URL?) async throws -> Game {
        var gameFile = file
        var home = file
        if let location {
            home = location.appending(path: Self.safeFileName(name))
            let folder = home
            gameFile = try await Task.detached {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Multi-file discs (.cue + .bin, .m3u) need their companion files alongside
                let siblings = try FileManager.default.contentsOfDirectory(
                    at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil
                ).filter { $0.deletingPathExtension().lastPathComponent == file.deletingPathExtension().lastPathComponent }
                for sibling in Set(siblings + [file]) {
                    try FileManager.default.copyItem(at: sibling, to: folder.appending(path: sibling.lastPathComponent))
                }
                return folder.appending(path: file.lastPathComponent)
            }.value
        }
        var game = Game(name: name, platform: platform, environmentPath: home.path(percentEncoded: false),
                        executablePath: gameFile.path(percentEncoded: false))
        game.retina = true
        games.append(game)
        save()
        selection = game.id
        fetchArtwork(for: game.id)
        return game
    }

    func remove(_ game: Game, deleteFiles: Bool) {
        if running.contains(game.id) { stop(game) }
        games.removeAll { $0.id == game.id }
        bottles[game.id] = nil
        save()
        try? FileManager.default.removeItem(at: StashPaths.cover(for: game.id))
        try? FileManager.default.removeItem(at: StashPaths.backups.appending(path: game.id.uuidString))
        for engine in ["pcsx2", "ppsspp"] {
            try? FileManager.default.removeItem(at: StashPaths.engines.appending(path: "\(engine)-\(game.id.uuidString).ini"))
        }
        if deleteFiles {
            NSWorkspace.shared.recycle([game.environmentURL])
        }
        if selection == game.id { selection = games.first?.id }
    }

    // MARK: - Playing

    func play(_ id: Game.ID) {
        guard let game = self[id], !running.contains(id) else { return }
        guard FileManager.default.fileExists(atPath: game.executablePath) else {
            lastError = "\(game.name) can't be found at \(game.executablePath). It may have been moved or deleted."
            return
        }
        if game.platform.isConsole {
            track(id) { try await self.engines.run(game) }
            return
        }

        let bottle = bottle(for: game)
        bottle.settings.metalHud = game.fpsOverlay
        bottle.settings.dxvk = game.graphics == .dxvk
        bottle.settings.enhancedSync = .msync

        // No Wine crash dialogs: a crash should end the game, not leave a debugger window behind
        var overrides = ["winedbg.exe=d"]
        if game.graphics == .dxvk { overrides.append("dxgi,d3d9,d3d10core,d3d11=n,b") }
        overrides += game.dllOverrides.map { "\($0)=n,b" }
        let environment = ["WINEDLLOVERRIDES": overrides.joined(separator: ";")]

        let arguments = game.arguments.split { $0.isWhitespace }.map(String.init)
        track(id) {
            if game.graphics == .dxvk { try Wine.enableDXVK(bottle: bottle) }
            // /wait keeps the stream open until the game exits so playtime can be tracked
            for await _ in try Wine.runWineProcess(
                name: game.executableURL.lastPathComponent,
                args: ["start", "/wait", "/d", game.gameFolderURL.windowsPath,
                       "/unix", game.executablePath] + arguments,
                bottle: bottle, environment: environment
            ) { }
        }
    }

    /// Marks a game as running for the duration of `session` and records the playtime
    private func track(_ id: Game.ID, session: @escaping () async throws -> Void) {
        guard let game = self[id] else { return }
        running.insert(id)
        let start = Date()
        Task {
            do {
                try await session()
            } catch {
                lastError = "\(game.name) failed to start: \(error.localizedDescription)"
            }
            running.remove(id)
            let duration = Date().timeIntervalSince(start)
            if !game.platform.isConsole, duration < 60, let log = Self.crashLog(since: start) {
                lastError = "\(game.name) crashed while starting. The details are in \(log.path(percentEncoded: false))."
            }
            update(id) { game in
                game.lastPlayed = start
                if duration > 30 { game.sessions.append(PlaySession(start: start, duration: duration)) }
            }
        }
    }

    /// The newest Wine log written since `date`, if it records a crash
    nonisolated static func crashLog(since date: Date) -> URL? {
        let logs = (try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let recent = logs.filter {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= date
        }
        let markers = ["Unhandled page fault", "Unhandled exception", "Assertion failed"]
        return recent.first { log in
            guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
            return markers.contains(where: text.contains)
        }
    }

    func stopAll() {
        running.compactMap { self[$0] }.forEach(stop)
    }

    func stop(_ game: Game) {
        if game.platform.isConsole {
            engines.stop(game)
        } else {
            try? Wine.killBottle(bottle: bottle(for: game))
        }
    }

    func setRetina(_ enabled: Bool, for id: Game.ID) {
        guard let game = self[id] else { return }
        update(id) { $0.retina = enabled }
        guard !game.platform.isConsole else { return }
        let bottle = bottle(for: game)
        Task { try? await Wine.changeRetinaMode(bottle: bottle, retinaMode: enabled) }
    }

    func setWindowsVersion(_ version: WinVersion, for id: Game.ID) {
        guard let game = self[id] else { return }
        update(id) { $0.windowsVersion = version }
        let bottle = bottle(for: game)
        bottle.settings.windowsVersion = version
        Task { _ = try? await Wine.changeWinVersion(bottle: bottle, win: version) }
    }

    // MARK: - Enhancements

    func isWorking(on mod: ModPackage, for id: Game.ID) -> Bool {
        modsInFlight[id]?.contains(mod.id) ?? false
    }

    func install(_ mod: ModPackage, for id: Game.ID) {
        guard let game = self[id] else { return }
        // Mods load through the ASI loader that ships with the widescreen pack
        var queue = [mod]
        if !mod.providesLoader,
           let loader = game.knownGame?.mods.compactMap(ModPackage.byID).first(where: \.providesLoader),
           game.installedMods[loader.id] == nil {
            queue.insert(loader, at: 0)
        }
        queue.forEach { modsInFlight[id, default: []].insert($0.id) }

        Task {
            for package in queue {
                do {
                    try await ModInstaller.install(package, into: game)
                    update(id) { $0.installedMods[package.id] = Date() }
                } catch {
                    lastError = "\(package.title) could not be installed: \(error.localizedDescription)"
                }
                modsInFlight[id]?.remove(package.id)
            }
        }
    }

    func uninstall(_ mod: ModPackage, for id: Game.ID) {
        guard let game = self[id] else { return }
        // Removing the loader disables every mod that depends on it
        let removing = mod.providesLoader
            ? game.installedMods.keys.compactMap(ModPackage.byID)
            : [mod]
        for package in removing.sorted(by: { !$0.providesLoader && $1.providesLoader }) {
            do {
                try ModInstaller.uninstall(package, from: game)
            } catch {
                lastError = "\(package.title) could not be fully removed: \(error.localizedDescription)"
            }
            update(id) { $0.installedMods[package.id] = nil }
        }
    }

    // MARK: - Covers

    func cover(for id: Game.ID) -> NSImage? {
        NSImage(contentsOf: StashPaths.cover(for: id))
    }

    func setCover(_ image: NSImage?, for id: Game.ID) {
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: StashPaths.covers, withIntermediateDirectories: true)
        try? png.write(to: StashPaths.cover(for: id))
        objectWillChange.send()
    }

    func hasArtwork(_ id: Game.ID) -> Bool {
        (cover(for: id)?.size.width ?? 0) >= 300
    }

    /// Downloads a cover from SteamGridDB when a key is set. Quietly does nothing otherwise.
    func fetchArtwork(for id: Game.ID, replacing: Bool = false) {
        guard ArtworkService.isConfigured, let game = self[id], !fetchingArtwork.contains(id),
              replacing || !hasArtwork(id) else { return }
        fetchingArtwork.insert(id)
        Task {
            if let image = try? await ArtworkService.bestCover(for: game.knownGame?.title ?? game.name) {
                setCover(image, for: id)
            }
            fetchingArtwork.remove(id)
        }
    }

    func fetchMissingArtwork() {
        games.map(\.id).forEach { fetchArtwork(for: $0) }
    }

    nonisolated static func icon(for executable: URL) -> NSImage? {
        guard let icon = try? PEFile(url: executable).bestIcon(), icon.isValid, icon.size.width > 0 else { return nil }
        return icon
    }

    // MARK: - Mac app export

    /// Creates a double-clickable Mac app that launches the game through Stash
    func exportMacApp(_ game: Game, to folder: URL) throws -> URL {
        let app = folder.appending(path: "\(Self.safeFileName(game.name)).app")
        let contents = app.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundleIdentifier": "app.stash.game.\(game.id.uuidString)",
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "LSApplicationCategoryType": "public.app-category.games",
            "LSUIElement": true
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))

        let script = macOS.appending(path: "launch")
        try "#!/bin/sh\nopen \"stash://play/\(game.id.uuidString)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        if let cover = cover(for: game.id) {
            NSWorkspace.shared.setIcon(cover, forFile: app.path, options: [])
        }
        return app
    }

    /// stash://play/<id> launches a game, stash://open/<id> shows its page
    func handle(url: URL) {
        guard url.scheme == "stash", let id = UUID(uuidString: url.lastPathComponent), self[id] != nil else { return }
        selection = id
        if url.host == "play" { play(id) }
    }

    nonisolated static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "Game" : cleaned
    }
}
