//
//  ModInstaller.swift
//  Stash
//
//  Installs mod archives into a game folder. Every file a mod overwrites is
//  backed up first, so removing a mod restores the game exactly as it was.
//

import Foundation

struct ModManifest: Codable {
    /// Files the mod added or replaced, relative to the game folder
    var files: [String] = []
    /// Files that existed before and were backed up
    var backedUp: [String] = []
    /// Files Stash created to preserve originals (e.g. vorbisHooked.dll)
    var preserved: [String] = []
}

enum ModInstaller {
    static func backupFolder(game: Game, mod: ModPackage) -> URL {
        StashPaths.backups.appending(path: game.id.uuidString).appending(path: mod.id)
    }

    static func install(_ mod: ModPackage, into game: Game) async throws {
        let fileManager = FileManager.default
        let gameFolder = game.gameFolderURL
        let backup = backupFolder(game: game, mod: mod)
        let staging = fileManager.temporaryDirectory.appending(path: "stash-mod-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let (download, response) = try await URLSession.shared.download(from: mod.url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StashError("Download failed for \(mod.title) (HTTP \(http.statusCode))")
        }
        let archive = staging.appending(path: "mod.zip")
        try fileManager.moveItem(at: download, to: archive)
        let extracted = staging.appending(path: "files")
        try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])

        let root = mod.archiveRoot.map { extracted.appending(path: $0) } ?? extracted
        let files = try relativeFiles(in: root)
        var manifest = ModManifest(files: files)

        try? fileManager.removeItem(at: backup)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)

        for (original, keptAs) in mod.preserve {
            let source = gameFolder.appending(path: original)
            let target = gameFolder.appending(path: keptAs)
            if fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: source, to: target)
                manifest.preserved.append(keptAs)
            }
        }

        for file in files {
            let source = root.appending(path: file)
            let target = gameFolder.appending(path: file)
            if fileManager.fileExists(atPath: target.path) {
                let saved = backup.appending(path: file)
                try fileManager.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: target, to: saved)
                manifest.backedUp.append(file)
                try fileManager.removeItem(at: target)
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
        }

        try applySettings(of: mod, to: game)
        try JSONEncoder().encode(manifest).write(to: backup.appending(path: "manifest.json"))
    }

    static func applySettings(of mod: ModPackage, to game: Game) throws {
        for setting in mod.settings {
            try IniFile.upsert(file: game.gameFolderURL.appending(path: setting.file),
                               section: setting.section, key: setting.key, value: setting.value)
        }
    }

    static func uninstall(_ mod: ModPackage, from game: Game) throws {
        let fileManager = FileManager.default
        let gameFolder = game.gameFolderURL
        let backup = backupFolder(game: game, mod: mod)
        let manifest = try JSONDecoder().decode(
            ModManifest.self, from: Data(contentsOf: backup.appending(path: "manifest.json"))
        )

        for file in manifest.files {
            try? fileManager.removeItem(at: gameFolder.appending(path: file))
        }
        for file in manifest.backedUp {
            try fileManager.copyItem(at: backup.appending(path: file), to: gameFolder.appending(path: file))
        }
        for file in manifest.preserved {
            try? fileManager.removeItem(at: gameFolder.appending(path: file))
        }
        try? fileManager.removeItem(at: backup)
    }

    private static func relativeFiles(in folder: URL) throws -> [String] {
        let base = folder.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            return String(url.standardizedFileURL.path.dropFirst(base.count + 1))
        }
    }
}

/// Minimal INI editing that keeps comments and layout intact
enum IniFile {
    static func value(file: URL, section: String, key: String) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var current = ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                current = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            } else if current.caseInsensitiveCompare(section) == .orderedSame,
                      let parsed = parse(line), parsed.key.caseInsensitiveCompare(key) == .orderedSame {
                return parsed.value
            }
        }
        return nil
    }

    static func set(file: URL, section: String, key: String, value: String) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var current = ""
        let lines = text.components(separatedBy: newline).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                current = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                return line
            }
            guard current.caseInsensitiveCompare(section) == .orderedSame,
                  let parsed = parse(line), parsed.key.caseInsensitiveCompare(key) == .orderedSame
            else { return line }
            return line.replacingCharacters(in: parsed.valueRange, with: value)
        }
        try lines.joined(separator: newline).write(to: file, atomically: true, encoding: .utf8)
    }

    /// Sets a value, creating the file, section or key when missing
    static func upsert(file: URL, section: String, key: String, value: String) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "".write(to: file, atomically: true, encoding: .utf8)
        }
        if self.value(file: file, section: section, key: key) != nil
            || hasEmptyKey(file: file, section: section, key: key) {
            try set(file: file, section: section, key: key, value: value)
            return
        }
        var lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        let header = "[\(section)]"
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(header) == .orderedSame
        }) {
            lines.insert("\(key) = \(value)", at: index + 1)
        } else {
            if let last = lines.last, last.isEmpty { lines.removeLast() }
            lines += ["", header, "\(key) = \(value)", ""]
        }
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func hasEmptyKey(file: URL, section: String, key: String) -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        var current = ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                current = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            } else if current.caseInsensitiveCompare(section) == .orderedSame, let parsed = parse(line),
                      parsed.key.caseInsensitiveCompare(key) == .orderedSame {
                return true
            }
        }
        return false
    }

    private static func parse(_ line: String) -> (key: String, value: String, valueRange: Range<String.Index>)? {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix(";"),
              let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let afterEquals = line.index(after: equals)
        let valueEnd = line[afterEquals...].firstIndex(of: ";") ?? line.endIndex
        let rawValue = line[afterEquals..<valueEnd]
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, let start = rawValue.range(of: value)?.lowerBound else {
            return (key, "", afterEquals..<valueEnd)
        }
        return (key, value, start..<line.index(start, offsetBy: value.count))
    }
}
