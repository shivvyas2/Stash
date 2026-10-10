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

    static func environment(prefix: URL, overrides: [String], fpsOverlay: Bool = false) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "fixme-all"
        environment["WINEMSYNC"] = "1"
        environment["WINEESYNC"] = "1"
        environment["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        if fpsOverlay { environment["MTL_HUD_ENABLED"] = "1" }
        return environment
    }

    /// Upgrades a prefix created by the modern engine. Runs once per game.
    static func prepare(prefix: URL) async throws {
        guard !FileManager.default.fileExists(atPath: marker(in: prefix).path) else { return }
        let environment = environment(prefix: prefix, overrides: [GameLibrary.quietOverrides])
        try await run(wine, ["wineboot", "-u"], environment: environment)
        try await run(wineserver, ["-w"], environment: environment)
        try Data().write(to: marker(in: prefix))
    }

    /// Runs a program inside the prefix and returns when it exits. Output goes to the Wine log folder.
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let log = try Wine.makeFileHandle()
        log.write(Data("Engine: classic (CrossOver 24.0.7)\nArguments: \(arguments.joined(separator: " "))\n\n".utf8))
        process.standardOutput = log
        process.standardError = log
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }
        try? log.close()
    }

    static func launch(_ program: URL, workingFolder: URL, arguments: [String] = [],
                       environment: [String: String]) async throws {
        try await run(wine, ["start", "/wait", "/d", workingFolder.windowsPath,
                             "/unix", program.path(percentEncoded: false)] + arguments, environment: environment)
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
