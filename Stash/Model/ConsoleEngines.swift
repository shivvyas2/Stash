//
//  ConsoleEngines.swift
//  Stash
//
//  Console games run on open-source engines (DuckStation, PCSX2, PPSSPP,
//  Dolphin) that Stash downloads, configures and drives itself. Games boot
//  straight into fullscreen with the engine's own interface hidden, and quitting
//  the game returns to Stash.
//

import AppKit
import Foundation

enum ConsoleEngine: String, CaseIterable, Identifiable {
    case duckstation, pcsx2, ppsspp, dolphin

    var id: String { rawValue }

    static func `for`(_ platform: Platform) -> ConsoleEngine? {
        switch platform {
        case .windows: return nil
        case .ps1: return .duckstation
        case .ps2: return .pcsx2
        case .psp: return .ppsspp
        case .gamecube, .wii: return .dolphin
        }
    }

    /// What players see: the console, not the emulator
    var displayName: String {
        switch self {
        case .duckstation: return "PlayStation engine"
        case .pcsx2: return "PlayStation 2 engine"
        case .ppsspp: return "PSP engine"
        case .dolphin: return "GameCube & Wii engine"
        }
    }

    var credit: String {
        switch self {
        case .duckstation: return "DuckStation"
        case .pcsx2: return "PCSX2"
        case .ppsspp: return "PPSSPP"
        case .dolphin: return "Dolphin"
        }
    }

    var needsBIOS: Bool { self == .duckstation || self == .pcsx2 }

    var supportsWidescreen: Bool { self != .ppsspp }

    var app: URL { StashPaths.engines.appending(path: "\(rawValue).app") }
    var dataFolder: URL { StashPaths.engines.appending(path: "\(credit) Data") }

    var biosFolder: URL {
        switch self {
        // DuckStation always keeps its data in its standard Application Support folder
        case .duckstation:
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "DuckStation/bios")
        default: return dataFolder.appending(path: "bios")
        }
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: app.path) }

    var hasBIOS: Bool {
        guard needsBIOS else { return true }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: biosFolder, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.contains { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) >= 256 * 1024 }
    }

    var executable: URL? {
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
              let name = info["CFBundleExecutable"] as? String else { return nil }
        return app.appending(path: "Contents/MacOS/\(name)")
    }

    /// Resolves the current download for this engine's latest stable release
    func downloadURL() async throws -> URL {
        switch self {
        case .duckstation:
            return URL(string: "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-mac-release.zip")!
        case .pcsx2:
            return try await Self.latestGitHubAsset(repo: "PCSX2/pcsx2", matching: "macos-Qt.tar.xz")
        case .ppsspp:
            return try await Self.latestGitHubAsset(repo: "hrydgard/ppsspp", matching: "PPSSPPSDL-macOS")
        case .dolphin:
            struct Update: Decodable { struct Artifact: Decodable { let system: String; let url: URL }; let artifacts: [Artifact] }
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://dolphin-emu.org/update/latest/beta/")!)
            let update = try JSONDecoder().decode(Update.self, from: data)
            guard let mac = update.artifacts.first(where: { $0.system.lowercased().contains("macos") }) else {
                throw StashError("No Mac download is available for the GameCube & Wii engine right now.")
            }
            return mac.url
        }
    }

    private static func latestGitHubAsset(repo: String, matching: String) async throws -> URL {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let assets: [Asset]
        }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.contains(matching) }) else {
            throw StashError("No Mac download was found for \(repo).")
        }
        return asset.browser_download_url
    }

    // MARK: Launching

    /// Writes this game's graphics settings and returns the engine's arguments
    func prepareLaunch(_ game: Game) throws -> [String] {
        let path = game.executablePath
        let scale = max(1, game.upscale)
        switch self {
        case .duckstation:
            let settings = biosFolder.deletingLastPathComponent().appending(path: "settings.ini")
            try IniFile.upsert(file: settings, section: "Main", key: "SetupWizardIncomplete", value: "false")
            try IniFile.upsert(file: settings, section: "GPU", key: "ResolutionScale", value: "\(scale)")
            try IniFile.upsert(file: settings, section: "GPU", key: "WidescreenHack", value: game.widescreen ? "true" : "false")
            try IniFile.upsert(file: settings, section: "Display", key: "AspectRatio",
                               value: game.widescreen ? "16:9" : "Auto (Game Native)")
            return ["-batch", "-nogui", "-fullscreen", "--", path]

        case .pcsx2:
            let main = dataFolder.appending(path: "inis/PCSX2.ini")
            try IniFile.upsert(file: main, section: "UI", key: "SetupWizardIncomplete", value: "false")
            let perGame = StashPaths.engines.appending(path: "pcsx2-\(game.id.uuidString).ini")
            try? FileManager.default.removeItem(at: perGame)
            try IniFile.upsert(file: perGame, section: "EmuCore/GS", key: "upscale_multiplier", value: "\(scale)")
            try IniFile.upsert(file: perGame, section: "EmuCore", key: "EnableWideScreenPatches",
                               value: game.widescreen ? "true" : "false")
            return ["-batch", "-nogui", "-fullscreen", "-datapath", dataFolder.path,
                    "-gamecfg", perGame.path, "--", path]

        case .ppsspp:
            let config = StashPaths.engines.appending(path: "ppsspp-\(game.id.uuidString).ini")
            try? FileManager.default.removeItem(at: config)
            try IniFile.upsert(file: config, section: "Graphics", key: "InternalResolution", value: "\(scale)")
            return ["--fullscreen", "--pause-menu-exit", "--escape-exit", "--appendconfig=\(config.path)", path]

        case .dolphin:
            return ["-u", dataFolder.path, "-b", "-v", "Metal",
                    "-C", "Dolphin.Display.Fullscreen=True",
                    "-C", "Dolphin.Analytics.PermissionAsked=True",
                    "-C", "GFX.Settings.InternalResolution=\(scale)",
                    "-C", "GFX.Settings.wideScreenHack=\(game.widescreen ? "True" : "False")",
                    "-e", path]
        }
    }
}

@MainActor
final class EngineManager: ObservableObject {
    /// Engines currently downloading or installing
    @Published private(set) var installing: Set<ConsoleEngine> = []
    private var processes: [Game.ID: Process] = [:]

    func install(_ engine: ConsoleEngine) async throws {
        guard !engine.isInstalled else { return }
        installing.insert(engine)
        defer { installing.remove(engine) }

        let url = try await engine.downloadURL()
        let (download, _) = try await URLSession.shared.download(from: url)
        try await Task.detached {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory.appending(path: "stash-engine-\(UUID().uuidString)")
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            let archive = staging.appending(path: url.lastPathComponent)
            try fileManager.moveItem(at: download, to: archive)
            let extracted = staging.appending(path: "out")
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)

            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".zip") {
                try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            } else if name.hasSuffix(".dmg") {
                let output = try Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", archive.path])
                guard let line = output.split(separator: "\n").last(where: { $0.contains("/Volumes/") }),
                      let range = line.range(of: "/Volumes/") else { throw StashError("Couldn't open the engine download.") }
                let volume = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                defer { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", volume, "-quiet"]) }
                try Shell.run("/usr/bin/ditto", [volume, extracted.path])
            } else {
                try Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", extracted.path])
            }

            guard let app = Self.findApp(in: extracted) else { throw StashError("The engine download had no app inside.") }
            try fileManager.createDirectory(at: StashPaths.engines, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: engine.app)
            try fileManager.moveItem(at: app, to: engine.app)
            _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", engine.app.path])
        }.value
    }

    func remove(_ engine: ConsoleEngine) {
        try? FileManager.default.removeItem(at: engine.app)
        objectWillChange.send()
    }

    /// Copies a user-supplied BIOS file into the engine's BIOS folder
    func addBIOS(_ file: URL, for engine: ConsoleEngine) throws {
        try FileManager.default.createDirectory(at: engine.biosFolder, withIntermediateDirectories: true)
        let target = engine.biosFolder.appending(path: file.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: file, to: target)
        objectWillChange.send()
    }

    /// Runs a console game and returns when the player quits
    func run(_ game: Game) async throws {
        guard let engine = ConsoleEngine.for(game.platform) else { return }
        if !engine.isInstalled { try await install(engine) }
        guard engine.hasBIOS else {
            throw StashError("\(game.platform.title) games need a BIOS file from your console. Add it in Settings → Consoles.")
        }
        guard let executable = engine.executable else { throw StashError("The \(engine.displayName) is damaged. Reinstall it in Settings.") }

        let process = Process()
        process.executableURL = executable
        process.arguments = try engine.prepareLaunch(game)
        var environment = ProcessInfo.processInfo.environment
        if game.fpsOverlay { environment["MTL_HUD_ENABLED"] = "1" }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        processes[game.id] = process
        defer { processes[game.id] = nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }
    }

    func stop(_ game: Game) {
        processes[game.id]?.terminate()
    }

    nonisolated private static func findApp(in folder: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "app" { return url }
            if enumerator?.level ?? 0 > 2 { enumerator?.skipDescendants() }
        }
        return nil
    }
}

extension Platform {
    static let consoleFileExtensions = ["iso", "cue", "bin", "chd", "pbp", "cso", "img", "rvz", "gcm", "gcz",
                                        "wbfs", "wia", "ciso", "wad", "elf", "dol", "m3u"]

    /// Best guess of a console game file's platform from its extension and disc header
    static func detect(_ file: URL) -> Platform? {
        switch file.pathExtension.lowercased() {
        case "cue", "pbp", "m3u": return .ps1
        case "cso": return .psp
        case "gcm", "gcz", "dol": return .gamecube
        case "wbfs", "wad": return .wii
        case "rvz", "wia", "ciso", "iso", "bin", "img", "chd": break
        default: return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        // Nintendo discs carry a magic word in the header; RVZ/WIA keep the original header after theirs
        let header = (try? handle.read(upToCount: 0x100)) ?? Data()
        func word(_ offset: Int) -> UInt32? {
            guard header.count >= offset + 4 else { return nil }
            return header[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        let ext = file.pathExtension.lowercased()
        let base = (ext == "rvz" || ext == "wia") ? 0x58 : 0
        if word(base + 0x18) == 0x5D1C9EA3 { return .wii }
        if word(base + 0x1C) == 0xC2339F3D { return .gamecube }
        if ext == "rvz" || ext == "wia" || ext == "ciso" { return .gamecube }

        // ISO 9660 primary volume descriptor: system identifier at 0x8008
        try? handle.seek(toOffset: 0x8008)
        let system = String(data: (try? handle.read(upToCount: 16)) ?? Data(), encoding: .ascii) ?? ""
        if system.hasPrefix("PSP GAME") { return .psp }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        if system.hasPrefix("PLAYSTATION") { return size > 800_000_000 ? .ps2 : .ps1 }
        if ext == "chd" { return .ps2 }
        return size > 800_000_000 ? .ps2 : .ps1
    }
}
