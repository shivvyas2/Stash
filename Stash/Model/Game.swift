//
//  Game.swift
//  Stash
//
//  A game in the library. Each game owns a private Windows environment (a Wine
//  prefix, which Whisky calls a "bottle") so games can never break each other.
//

import Foundation
import WhiskyKit

enum GraphicsMode: String, Codable, CaseIterable, Identifiable {
    /// GPTK picks per-API: D3DMetal for DirectX 11/12, WineD3D for DirectX 8/9
    case metal
    /// DXVK translates DirectX 10/11 to Vulkan, then MoltenVK to Metal
    case dxvk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metal: return "Apple Metal"
        case .dxvk: return "DXVK"
        }
    }

    var detail: String {
        switch self {
        case .metal: return "Best for most games. DirectX 8–12 → Metal."
        case .dxvk: return "Try if a DirectX 10/11 game renders incorrectly."
        }
    }
}

enum Platform: String, Codable, CaseIterable, Identifiable {
    case windows, ps1, ps2, ps3, psp, gamecube, wii

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .ps1: return "PlayStation"
        case .ps2: return "PlayStation 2"
        case .ps3: return "PlayStation 3"
        case .psp: return "PSP"
        case .gamecube: return "GameCube"
        case .wii: return "Wii"
        }
    }

    var symbol: String {
        switch self {
        case .windows: return "pc"
        case .ps1, .ps2, .ps3: return "playstation.logo"
        case .psp: return "gamecontroller"
        case .gamecube, .wii: return "gamecontroller.fill"
        }
    }

    var isConsole: Bool { self != .windows }
}

struct PlaySession: Codable, Hashable {
    var start: Date
    var duration: TimeInterval
}

struct Game: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var platform: Platform = .windows
    /// Windows: folder holding the game's Windows environment. Consoles: folder holding the game file.
    var environmentPath: String
    /// Windows: the .exe that starts the game. Consoles: the disc image or game file.
    var executablePath: String
    var arguments: String = ""
    var knownGameID: String?
    /// Release year the player typed in. Nil falls back to the catalog's year.
    var customYear: String?
    /// The player's own notes, shown beside the catalog tips
    var notes: String = ""
    /// Set for games installed by Steam, which are started through the Steam entry's environment
    var steamAppID: Int?

    var engine: WineEngine = .modern
    /// Set for 32-bit DirectX 7/8/9 games, which get full-screen scaling on the classic engine
    var legacyAPI: LegacyAPI?
    var graphics: GraphicsMode = .metal
    var retina: Bool = true
    var fpsOverlay: Bool = false
    /// Classic games: UID of the speaker picked at first launch. Empty means automatic, nil means not asked yet.
    var audioDevice: String?
    var windowsVersion: WinVersion = .win10
    /// Screen the game plays on (GameDisplay.key). Nil means whichever screen has the menu bar.
    var display: String?
    /// Consoles: internal render resolution multiplier (1 = original)
    var upscale: Int = 3
    var widescreen: Bool = true

    var addedAt = Date()
    var lastPlayed: Date?
    var sessions: [PlaySession] = []
    /// Mod id → install date
    var installedMods: [String: Date] = [:]

    init(name: String, platform: Platform = .windows, environmentPath: String, executablePath: String,
         knownGameID: String? = nil) {
        self.name = name
        self.platform = platform
        self.environmentPath = environmentPath
        self.executablePath = executablePath
        self.knownGameID = knownGameID
    }

    /// Tolerant decoding: fields added in later versions fall back to their defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        environmentPath = try container.decode(String.self, forKey: .environmentPath)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        platform = value(.platform, Platform.windows)
        arguments = value(.arguments, "")
        knownGameID = value(.knownGameID, String?.none)
        customYear = value(.customYear, String?.none)
        notes = value(.notes, "")
        steamAppID = value(.steamAppID, Int?.none)
        // Games added before the classic engine existed are detected from their executable
        if container.contains(.engine) {
            engine = value(.engine, WineEngine.modern)
            legacyAPI = value(.legacyAPI, LegacyAPI?.none)
        } else if platform == .windows {
            legacyAPI = LegacyAPI.detect(in: URL(fileURLWithPath: executablePath))
            engine = legacyAPI == nil ? .modern : .classic
        }
        graphics = value(.graphics, GraphicsMode.metal)
        retina = value(.retina, true)
        fpsOverlay = value(.fpsOverlay, false)
        audioDevice = value(.audioDevice, String?.none)
        windowsVersion = value(.windowsVersion, WinVersion.win10)
        display = value(.display, String?.none)
        upscale = value(.upscale, 3)
        widescreen = value(.widescreen, true)
        addedAt = value(.addedAt, Date())
        lastPlayed = value(.lastPlayed, Date?.none)
        sessions = value(.sessions, [PlaySession]())
        installedMods = value(.installedMods, [String: Date]())
    }

    var environmentURL: URL { URL(fileURLWithPath: environmentPath) }
    var executableURL: URL { URL(fileURLWithPath: executablePath) }
    var gameFolderURL: URL { executableURL.deletingLastPathComponent() }
    /// The Steam client itself, as opposed to a game installed by it
    var isSteamClient: Bool { steamAppID == nil && executableURL.lastPathComponent.lowercased() == "steam.exe" }
    /// Steam, or a game played through it
    var isSteam: Bool { isSteamClient || steamAppID != nil }
    var knownGame: KnownGame? { knownGameID.flatMap(KnownGame.byID) }
    /// An empty custom year hides the catalog year
    var year: String? { customYear.map { $0.isEmpty ? nil : $0 } ?? knownGame?.year }

    static func upscaleOptions(for platform: Platform) -> [(scale: Int, title: String, detail: String)] {
        // PS3 games already draw in HD, so each step is a much bigger jump
        if platform == .ps3 { return [(1, "1×", "Original"), (2, "2×", "1440p"), (3, "3×", "4K")] }
        return [(1, "1×", "Original"), (2, "2×", "HD"), (3, "3×", "Full HD"), (4, "4×", "QHD"), (6, "6×", "4K")]
    }

    var totalPlaytime: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }

    /// Playtime per day for the last `days` days, oldest first
    func playtimeByDay(days: Int = 7) -> [TimeInterval] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return sessions
                .filter { calendar.isDate($0.start, inSameDayAs: day) }
                .reduce(0) { $0 + $1.duration }
        }
    }

    /// DLLs that installed mods ship and Wine must load instead of its own copies
    var dllOverrides: [String] {
        installedMods.keys.compactMap { ModPackage.byID($0)?.dllOverride }
    }
}

extension TimeInterval {
    var playtimeString: String {
        let minutes = Int(self / 60)
        if minutes < 1 { return "0m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
