//
//  Steam.swift
//  Stash
//
//  Windows Steam, installed into its own environment on the classic engine (CrossOver 24).
//  Upstream Wine connects but can't show Steam's window: its contents are drawn by
//  another process (the browser), which the macOS driver doesn't support. CrossOver does.
//

import Foundation

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
