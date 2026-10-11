//
//  LatestEngine.swift
//  Stash
//
//  A third Windows engine: current upstream Wine (Staging), built for macOS by Gcenx.
//  Today's Steam client needs it: its built-in browser hangs on the Game Porting
//  Toolkit's Wine 7.7, and CrossOver 24 can't answer the checks Steam makes on its
//  own local connections. Downloaded on first use, like the classic engine.
//

import Foundation
import WhiskyKit

enum LatestEngine {
    static let folder = StashPaths.engines.appending(path: "Latest")
    static var wine: URL { folder.appending(path: "wine/bin/wine") }
    static var wineserver: URL { folder.appending(path: "wine/bin/wineserver") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }

    static let version = "11.18"
    private static let engineURL = URL(string:
        "https://github.com/Gcenx/macOS_Wine_builds/releases/download/\(version)/wine-staging-\(version)-osx64.tar.xz")!

    static func install() async throws {
        guard !isInstalled else { return }
        let (archive, _) = try await URLSession.shared.download(from: engineURL)
        try await Task.detached {
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory.appending(path: "stash-latest-\(UUID().uuidString)")
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }
            try Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
            try? fileManager.removeItem(at: archive)

            let wineFolder = staging.appending(path: "Wine Staging.app/Contents/Resources/wine")
            guard fileManager.fileExists(atPath: wineFolder.appending(path: "bin/wine").path) else {
                throw StashError("The latest engine's download didn't contain Wine.")
            }
            try? fileManager.removeItem(at: folder)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.moveItem(at: wineFolder, to: folder.appending(path: "wine"))
            _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", folder.path])
        }.value
    }

    static func environment(prefix: URL, overrides: [String] = [GameLibrary.quietOverrides],
                            fpsOverlay: Bool = false) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "fixme-all"
        environment["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        if fpsOverlay { environment["MTL_HUD_ENABLED"] = "1" }
        return environment
    }

    /// Creates a new Windows environment
    static func createPrefix(_ prefix: URL) async throws {
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        // mscoree/mshtml off: otherwise wineboot waits on Mono and Gecko install prompts nobody sees
        let environment = environment(prefix: prefix, overrides: [GameLibrary.quietOverrides, "mscoree,mshtml="])
        try await run(wine, ["wineboot", "-u"], environment: environment)
        try await run(wineserver, ["-w"], environment: environment)
    }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String],
                    stuckMarker: String? = nil) async throws -> URL {
        try await ClassicEngine.run(executable, arguments, environment: environment, stuckMarker: stuckMarker,
                                    engineName: "latest (Wine \(version) Staging)")
    }

    /// Starts a program and returns its log when it exits
    @discardableResult
    static func launch(_ program: URL, workingFolder: URL, arguments: [String] = [],
                       environment: [String: String]) async throws -> URL {
        try await run(wine, ["start", "/wait", "/d", workingFolder.windowsPath,
                             "/unix", program.path(percentEncoded: false)] + arguments,
                      environment: environment, stuckMarker: ClassicEngine.noGraphicsDriver)
    }

    static func stop(prefix: URL) {
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = environment(prefix: prefix)
        try? process.run()
    }

    static func setRegistry(prefix: URL, key: String, name: String, value: String) async throws {
        try await run(wine, ["reg", "add", key, "/v", name, "/d", value, "/f"], environment: environment(prefix: prefix))
    }

    static func setWindowsVersion(prefix: URL, _ version: WinVersion) async throws {
        try await run(wine, ["winecfg", "-v", version.rawValue], environment: environment(prefix: prefix))
    }
}

/// Windows Steam, installed into its own environment on the latest engine
enum Steam {
    static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!
    /// Steamworks Common Redistributables: installed alongside games, never played
    private static let hiddenApps: Set<Int> = [228980]

    static func client(in prefix: URL) -> URL {
        prefix.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
    }

    struct InstalledGame: Hashable {
        let appID: Int
        let name: String
    }

    /// Games Steam has installed, read from its appmanifest files
    static func installedGames(in prefix: URL) -> [InstalledGame] {
        let steamapps = prefix.appending(path: "drive_c/Program Files (x86)/Steam/steamapps")
        let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { file in
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let appID = value("appid", in: text).flatMap(Int.init), !hiddenApps.contains(appID),
                      let name = value("name", in: text) else { return nil }
                return InstalledGame(appID: appID, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    /// The value of `"key"   "value"` in Valve's KeyValues text format
    private static func value(_ key: String, in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count == 2, parts[0].caseInsensitiveCompare(key) == .orderedSame { return parts[1] }
        }
        return nil
    }
}
