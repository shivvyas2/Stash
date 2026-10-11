//
//  ClassicEngine.swift
//  Stash
//
//  A second Windows engine for 2000s-era 32-bit DirectX 7/8/9 games: CrossOver 24
//  (Wine 9), built by the Sikarugir project. The Game Porting Toolkit build is
//  based on Wine 7.7, whose 32-bit support crashes some older games; D3DMetal only
//  helps DirectX 11/12 anyway.
//

import Foundation
import WhiskyKit

enum WineEngine: String, Codable, CaseIterable, Identifiable {
    case modern, classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modern: return "Modern"
        case .classic: return "Classic"
        }
    }

    var detail: String {
        switch self {
        case .modern: return "Game Porting Toolkit with D3DMetal. Best for games from about 2010 on."
        case .classic: return "CrossOver 24 with full-screen scaling. Best for 32-bit games from the 2000s."
        }
    }
}

/// The DirectX API an older game draws with, which decides the scaling wrapper it gets
enum LegacyAPI: String, Codable, CaseIterable {
    case ddraw, d3d8, d3d9

    var dll: String { rawValue }

    /// Reads the executable's import names. Only 32-bit games count as classic.
    static func detect(in executable: URL) -> LegacyAPI? {
        guard let pe = try? PEFile(url: executable), pe.architecture == .x32,
              let data = try? Data(contentsOf: executable) else { return nil }
        let text = String(decoding: data, as: UTF8.self).lowercased()
        if text.contains("d3d8.dll") { return .d3d8 }
        if text.contains("d3d9.dll") { return .d3d9 }
        if text.contains("ddraw.dll") { return .ddraw }
        return nil
    }
}

enum ClassicEngine {
    static let folder = StashPaths.engines.appending(path: "Classic")
    static var bundle: URL { folder.appending(path: "wswine.bundle") }
    static var wine: URL { bundle.appending(path: "bin/wine") }
    static var wineserver: URL { bundle.appending(path: "bin/wineserver") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }

    private static let engineURL = URL(string:
        "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz")!
    /// The engine links against libraries that ship in Sikarugir's wrapper template
    private static let librariesURL = URL(string:
        "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.21.tar.xz")!

    /// Marks a prefix that has been upgraded to this engine
    private static func marker(in prefix: URL) -> URL { prefix.appending(path: ".stash-classic") }

    static func install() async throws {
        guard !isInstalled else { return }
        async let engineDownload = URLSession.shared.download(from: engineURL)
        async let librariesDownload = URLSession.shared.download(from: librariesURL)
        let (engineArchive, _) = try await engineDownload
        let (librariesArchive, _) = try await librariesDownload

        try await Task.detached {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory.appending(path: "stash-classic-\(UUID().uuidString)")
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            try Shell.run("/usr/bin/tar", ["-xf", engineArchive.path, "-C", staging.path])
            try Shell.run("/usr/bin/tar", ["-xf", librariesArchive.path, "-C", staging.path])
            try? fileManager.removeItem(at: engineArchive)
            try? fileManager.removeItem(at: librariesArchive)

            guard let frameworks = fileManager.enumerator(at: staging, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL })
                .first(where: { $0.lastPathComponent == "Frameworks" && $0.path.contains(".app/Contents/") })
            else { throw StashError("The classic engine's libraries were missing from the download.") }

            try? fileManager.removeItem(at: folder)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging.appending(path: "wswine.bundle"), to: bundle)
            // wine looks for its libraries two folders above bin/
            for library in try fileManager.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)
            where library.pathExtension == "dylib" {
                try fileManager.copyItem(at: library, to: folder.appending(path: library.lastPathComponent))
            }
            _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", folder.path])
        }.value
    }

    static func environment(prefix: URL, overrides: [String], fpsOverlay: Bool = false,
                            audioDevice: String? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "fixme-all"
        environment["WINEMSYNC"] = "1"
        environment["WINEESYNC"] = "1"
        environment["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        // Wine's graphics and audio modules dlopen MoltenVK and friends by bare name
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = [folder.path, bundle.appending(path: "lib").path, "/usr/lib"]
            .joined(separator: ":")
        if fpsOverlay { environment["MTL_HUD_ENABLED"] = "1" }
        // Read by StashAudio/AudioFilter.c
        if let audioDevice, !audioDevice.isEmpty { environment["STASH_AUDIO_DEVICE"] = audioDevice }
        return environment
    }

    /// A 32-bit system library only this engine ships. Older Stash builds could mark a prefix
    /// as upgraded while wineboot was stuck behind an invisible Mono prompt, leaving it out.
    private static func upgradeComplete(_ prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: prefix.appending(path: "drive_c/windows/syswow64/coml2.dll").path)
    }

    /// Upgrades a prefix created by the modern engine. Runs once per game, and again if a past upgrade was cut short.
    static func prepare(prefix: URL) async throws {
        if FileManager.default.fileExists(atPath: marker(in: prefix).path), upgradeComplete(prefix) { return }
        // mscoree/mshtml off: otherwise wineboot waits on Mono and Gecko install prompts nobody sees
        let environment = environment(prefix: prefix,
                                      overrides: [GameLibrary.quietOverrides, "mscoree,mshtml="])
        try await run(wine, ["wineboot", "-u"], environment: environment)
        try await run(wineserver, ["-w"], environment: environment)
        guard upgradeComplete(prefix) else {
            throw StashError("Windows couldn't finish setting up for this game. Try playing it again.")
        }
        try Data().write(to: marker(in: prefix))
    }

    /// Runs a program inside the prefix and returns its log when it exits. Output goes to the Wine log folder.
    /// When `stuckMarker` shows up in the log, the program is hung: the prefix is stopped so this returns.
    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String],
                    stuckMarker: String? = nil) async throws -> URL {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        try FileManager.default.createDirectory(at: Wine.logsFolder, withIntermediateDirectories: true)
        let logURL = Wine.logsFolder.appending(path: "\(Date.now.ISO8601Format())-\(UUID().uuidString.prefix(4)).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        log.write(Data("Engine: classic (CrossOver 24.0.7)\nArguments: \(arguments.joined(separator: " "))\n\n".utf8))
        process.standardOutput = log
        process.standardError = log
        defer { try? log.close() }

        let watcher = stuckMarker.flatMap { marker in
            environment["WINEPREFIX"].map { prefix in
                Task.detached {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(1))
                        if let text = try? String(contentsOf: logURL, encoding: .utf8), text.contains(marker) {
                            stop(prefix: URL(fileURLWithPath: prefix))
                            return
                        }
                    }
                }
            }
        }
        defer { watcher?.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        return logURL
    }

    /// Wine writes this when the game process couldn't load the Mac graphics driver. The game then hangs.
    static let noGraphicsDriver = "nodrv_CreateWindow"

    /// Fixes Stash applies to the engine's macOS drivers. Done in place so they need no developer tools,
    /// and repeated after an engine reinstall. Originals are kept next to the patched files.
    static func installFixes() throws {
        // The audio driver shows games a single speaker (StashAudio/AudioFilter.c)
        try patchLibraryReference(in: "winecoreaudio.so",
                                  from: "/System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio",
                                  to: StashPaths.audioFilter)
        // The network driver can list connections on macOS 26 (StashNet/NetworkFix.c)
        try patchLibraryReference(in: "nsiproxy.so", from: "/usr/lib/libSystem.B.dylib", to: StashPaths.networkFix)
    }

    /// Makes `driver` load `replacement` instead of the library at `original`. The replacement re-exports the
    /// original, so only the functions it defines change. The new path must fit in the old one's space.
    private static func patchLibraryReference(in driver: String, from original: String, to replacement: URL?) throws {
        guard let replacement else { return }
        let fileManager = FileManager.default
        let unixFolder = bundle.appending(path: "lib/wine/x86_64-unix")
        let installed = unixFolder.appending(path: replacement.lastPathComponent)
        if !fileManager.contentsEqual(atPath: replacement.path, andPath: installed.path) {
            try? fileManager.removeItem(at: installed)
            try fileManager.copyItem(at: replacement, to: installed)
        }

        let driverURL = unixFolder.appending(path: driver)
        var data = try Data(contentsOf: driverURL)
        let originalPath = Data(original.utf8)
        let newPath = Data("@loader_path/\(replacement.lastPathComponent)".utf8)
        guard let range = data.range(of: originalPath), newPath.count <= originalPath.count else { return }
        let backup = unixFolder.appending(path: "\(driver).original")
        if !fileManager.fileExists(atPath: backup.path) { try fileManager.copyItem(at: driverURL, to: backup) }
        // The load command keeps its size: the shorter path is padded with zeros
        data.replaceSubrange(range, with: newPath + Data(count: originalPath.count - newPath.count))
        try data.write(to: driverURL)
        try Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", driverURL.path])
    }

    /// Starts a game and returns its log when it exits
    @discardableResult
    static func launch(_ program: URL, workingFolder: URL, arguments: [String] = [],
                       environment: [String: String]) async throws -> URL {
        try await run(wine, ["start", "/wait", "/d", workingFolder.windowsPath,
                                    "/unix", program.path(percentEncoded: false)] + arguments,
                             environment: environment, stuckMarker: noGraphicsDriver)
    }

    static func stop(prefix: URL) {
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = environment(prefix: prefix, overrides: [])
        try? process.run()
    }

    /// Sets a value in the prefix registry with this engine, so an upgraded prefix is never touched by the old one
    static func setRegistry(prefix: URL, key: String, name: String, value: String) async throws {
        try await run(wine, ["reg", "add", key, "/v", name, "/d", value, "/f"],
                      environment: environment(prefix: prefix, overrides: [GameLibrary.quietOverrides]))
    }

    static func setWindowsVersion(prefix: URL, _ version: WinVersion) async throws {
        try await run(wine, ["winecfg", "-v", version.rawValue],
                      environment: environment(prefix: prefix, overrides: [GameLibrary.quietOverrides]))
    }
}
