//
//  Catalog.swift
//  Stash
//
//  Games Stash recognises, and the community enhancement mods it can install
//  for them in one click.
//

import Foundation
import SwiftUI

struct KnownGame: Identifiable {
    let id: String
    let title: String
    /// Lowercased executable names that identify the game
    let executables: [String]
    let year: String
    let color: Color
    let mods: [String]
    let tips: [String]

    static let all: [KnownGame] = [
        KnownGame(
            id: "gtasa", title: "Grand Theft Auto: San Andreas",
            executables: ["gta_sa.exe", "gta-sa.exe"], year: "2004",
            color: Color(hex: 0xD9542B),
            mods: ["widescreen-sa", "silentpatch-sa", "skygfx-sa"],
            tips: [
                "Enhancements need the original v1.0 gta_sa.exe. Steam and Rockstar Launcher builds "
                + "may need downgrading first.",
                "Set the in-game resolution to your Mac's native size after installing the widescreen fix.",
                "SkyGfx brings back the PS2 look: brighter world, colour filter and car reflections."
            ]
        ),
        KnownGame(
            id: "gtavc", title: "Grand Theft Auto: Vice City",
            executables: ["gta-vc.exe", "gta_vc.exe"], year: "2002",
            color: Color(hex: 0xE0408A),
            mods: ["widescreen-vc", "silentpatch-vc"],
            tips: [
                "Enhancements need the original v1.0 gta-vc.exe.",
                "The widescreen fix also removes loading screens between islands."
            ]
        ),
        KnownGame(
            id: "gta3", title: "Grand Theft Auto III",
            executables: ["gta3.exe"], year: "2001",
            color: Color(hex: 0x2B2B2B),
            mods: ["widescreen-iii", "silentpatch-iii"],
            tips: ["Enhancements need the original v1.0 gta3.exe."]
        )
    ]

    static func byID(_ id: String) -> KnownGame? { all.first { $0.id == id } }

    static func matching(executable: URL) -> KnownGame? {
        let name = executable.lastPathComponent.lowercased()
        return all.first { $0.executables.contains(name) }
    }
}

/// A setting inside a mod's INI file that Stash exposes as a toggle
struct ModToggle: Identifiable {
    let file: String
    let section: String
    let key: String
    let title: String
    let detail: String
    var id: String { "\(file)#\(section).\(key)" }
}

/// A value Stash writes into a mod's INI file after installing it
struct ModSetting {
    let file: String
    let section: String
    let key: String
    let value: String
}

struct ModPackage: Identifiable {
    let id: String
    let title: String
    let summary: String
    let url: URL
    /// Archive folder whose contents go into the game folder (nil = archive root)
    var archiveRoot: String?
    /// DLL the mod replaces, which Wine must load as native
    var dllOverride: String?
    /// Original files to preserve under a new name before installing (from → to)
    var preserve: [String: String] = [:]
    var toggles: [ModToggle] = []
    var settings: [ModSetting] = []
    /// Ships the ASI loader that the other mods need in order to load
    var providesLoader: Bool { id.hasPrefix("widescreen-") }

    static func byID(_ id: String) -> ModPackage? { (all + scaling).first { $0.id == id } }

    /// dxwrapper, set to run the game in a window that is stretched to fill the display.
    /// The game never changes the Mac's screen mode, which most Mac displays can't do for 640×480.
    static let scaling: [ModPackage] = LegacyAPI.allCases.map { api in
        let ini = "dxwrapper.ini"
        let package: String
        var settings = [
            ModSetting(file: ini, section: "d3d9", key: "EnableWindowMode", value: "1"),
            ModSetting(file: ini, section: "FullScreen", key: "FullScreen", value: "1"),
            ModSetting(file: ini, section: "FullScreen", key: "ForceWindowResize", value: "1"),
            ModSetting(file: ini, section: "FullScreen", key: "WaitForWindowChanges", value: "1"),
            // These games were made for 60 FPS. Uncapped they run near 120 with uneven frame times, which
            // shows as stutter; a 60 FPS cap with VSync gives every frame the same time on a 120 Hz display.
            ModSetting(file: ini, section: "d3d9", key: "EnableVSync", value: "1"),
            ModSetting(file: ini, section: "d3d9", key: "LimitPerFrameFPS", value: "60"),
            // Sharper textures at an angle, like the pitch. Anti-aliasing is left off: it corrupts some 2D art.
            ModSetting(file: ini, section: "d3d9", key: "AnisotropicFiltering", value: "16")
        ]
        switch api {
        case .ddraw:
            package = "dx7"
            settings.append(ModSetting(file: ini, section: "Compatibility", key: "Dd7to9", value: "1"))
        case .d3d8:
            package = "dx8"
            settings.append(ModSetting(file: ini, section: "Compatibility", key: "D3d8to9", value: "1"))
        case .d3d9:
            package = "dx9"
            settings.append(ModSetting(file: ini, section: "Compatibility", key: "EnableD3d9Wrapper", value: "1"))
        }
        return ModPackage(
            id: "scaling-\(api.rawValue)", title: "Full-screen scaling",
            summary: "Runs the game at its own resolution and scales it to fill your display",
            url: URL(string: "https://github.com/elishacloud/dxwrapper/releases/download/v1.8.8600.25/\(package).games.zip")!,
            dllOverride: api.dll,
            settings: settings
        )
    }

    static func scaling(for api: LegacyAPI) -> ModPackage { byID("scaling-\(api.rawValue)")! }

    private static let widescreen = "https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/"
    private static let silentPatch = "https://github.com/CookiePLMonster/SilentPatch/releases/download/1.1-BUILD34.1-SA/"

    private static func graphicsToggles(_ ini: String) -> [ModToggle] {
        [
            ModToggle(file: ini, section: "GRAPHICS", key: "SMAA", title: "SMAA anti-aliasing",
                      detail: "Smooths jagged edges"),
            ModToggle(file: ini, section: "GRAPHICS", key: "ConsoleGamma", title: "Console colour grading",
                      detail: "GTA IV Xbox 360 style gamma curve")
        ]
    }

    static let all: [ModPackage] = [
        ModPackage(
            id: "widescreen-sa", title: "Widescreen & HD",
            summary: "Native widescreen, correct HUD and FOV at any resolution",
            url: URL(string: widescreen + "gtasa/GTASA.WidescreenFix.zip")!,
            preserve: ["vorbisFile.dll": "vorbisHooked.dll"],
            toggles: graphicsToggles("scripts/GTASA.WidescreenFix.ini") + [
                ModToggle(file: "scripts/GTASA.WidescreenFix.ini", section: "MISC", key: "HQRadarDisc",
                          title: "HD radar", detail: "Higher resolution minimap"),
                ModToggle(file: "scripts/GTASA.WidescreenFix.ini", section: "MISC", key: "FullscreenMap",
                          title: "Fullscreen map", detail: "Map fills the whole screen")
            ]
        ),
        ModPackage(
            id: "silentpatch-sa", title: "SilentPatch",
            summary: "Fixes hundreds of bugs, restores missing effects, frame-rate fixes",
            url: URL(string: silentPatch + "SilentPatchSA.zip")!
        ),
        ModPackage(
            id: "skygfx-sa", title: "SkyGfx shaders",
            summary: "PS2/Xbox rendering pipeline: colour filter, reflections, lighting",
            url: URL(string: "https://github.com/aap/skygfx/releases/download/v4.2b/SkyGfx_SA_4.2b.zip")!,
            archiveRoot: "SkyGfx_SA_4.2b",
            toggles: [
                ModToggle(file: "skygfx1.ini", section: "SkyGfx", key: "ps2Modulate", title: "PS2 brightness",
                          detail: "Brighter world and grass like the PS2"),
                ModToggle(file: "skygfx1.ini", section: "SkyGfx", key: "dualPass", title: "Dual-pass rendering",
                          detail: "Fixes transparency on trees and fences")
            ]
        ),
        ModPackage(
            id: "widescreen-vc", title: "Widescreen & HD",
            summary: "Native widescreen, correct HUD and FOV at any resolution",
            url: URL(string: widescreen + "gtavc/GTAVC.WidescreenFix.zip")!,
            dllOverride: "d3d8",
            toggles: graphicsToggles("scripts/GTAVC.WidescreenFix.ini") + [
                ModToggle(file: "scripts/GTAVC.WidescreenFix.ini", section: "MISC", key: "NoIslandLoading",
                          title: "No island loading", detail: "Seamless travel between islands"),
                ModToggle(file: "scripts/GTAVC.WidescreenFix.ini", section: "MISC", key: "CarSpeedDependantFOV",
                          title: "Speed FOV", detail: "Camera widens as cars go faster")
            ]
        ),
        ModPackage(
            id: "silentpatch-vc", title: "SilentPatch",
            summary: "Fixes bugs and restores effects missing from the PC port",
            url: URL(string: silentPatch + "SilentPatchVC.zip")!
        ),
        ModPackage(
            id: "widescreen-iii", title: "Widescreen & HD",
            summary: "Native widescreen, correct HUD and FOV at any resolution",
            url: URL(string: widescreen + "gta3/GTA3.WidescreenFix.zip")!,
            dllOverride: "d3d8",
            toggles: graphicsToggles("scripts/GTA3.WidescreenFix.ini")
        ),
        ModPackage(
            id: "silentpatch-iii", title: "SilentPatch",
            summary: "Fixes bugs and restores effects missing from the PC port",
            url: URL(string: silentPatch + "SilentPatchIII.zip")!
        )
    ]
}
