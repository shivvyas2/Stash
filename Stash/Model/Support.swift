//
//  Support.swift
//  Stash
//

import Foundation

struct StashError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum StashPaths {
    /// Stash's own data. Kept apart from the runtime folder, which is wiped on runtime reinstall.
    static let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Stash")
    static let library = data.appending(path: "Library.json")
    static let covers = data.appending(path: "Covers")
    static let backups = data.appending(path: "Mod Backups")
    static let engines = data.appending(path: "Engines")
    /// The classic engine's stand-in for CoreAudio, which shows games one speaker. See StashAudio/AudioFilter.c.
    static let audioFilter = Bundle.main.url(forResource: "libStashAudio", withExtension: "dylib")
    /// Lets the classic engine list network connections on macOS 26. See StashNet/NetworkFix.c.
    static let networkFix = Bundle.main.url(forResource: "libsn", withExtension: "dylib")

    static var defaultInstallLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games")
    }

    static var defaultAppsLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
    }

    static func cover(for id: UUID) -> URL {
        covers.appending(path: "\(id.uuidString).png")
    }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw StashError("\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(output)")
        }
        return output
    }
}

extension URL {
    /// The path Windows programs see for this macOS location: C: inside a prefix's drive_c, else Z: (mapped to /).
    /// Some mods crash on a Z: working folder, like San Andreas with SilentPatch and the widescreen fix.
    var windowsPath: String {
        let path = path(percentEncoded: false)
        if let range = (path + "/").range(of: "/drive_c/", options: .backwards),
           FileManager.default.fileExists(atPath: path[..<range.lowerBound] + "/dosdevices") {
            let inside = (path + "/")[range.upperBound...].split(separator: "/").joined(separator: "\\")
            return "C:\\" + inside
        }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }

    var folderSize: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: self, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]
        ) else { return 0 }
        return enumerator.reduce(Int64(0)) { total, item in
            guard let url = item as? URL,
                  let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
            else { return total }
            return total + Int64(size)
        }
    }
}
