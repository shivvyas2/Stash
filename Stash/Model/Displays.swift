//
//  Displays.swift
//  Stash
//
//  The Mac's screens, for choosing where a game plays. Every engine opens
//  fullscreen on the main screen, so the chosen screen becomes the main one
//  while the game runs. The change is made for Stash only, so macOS puts the
//  screens back by itself if Stash quits before restoring them.
//

import AppKit
import CoreGraphics

struct GameDisplay: Identifiable, Hashable {
    /// Survives reconnects and restarts, unlike the display ID
    let key: String
    let displayID: CGDirectDisplayID
    let name: String

    var id: String { key }
}

enum Displays {
    static func all() -> [GameDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return GameDisplay(key: key(for: id), displayID: id, name: screen.localizedName)
        }
    }

    static func display(for key: String?) -> GameDisplay? {
        guard let key else { return nil }
        return all().first { $0.key == key }
    }

    private static func key(for id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Makes `display` the main screen by moving every screen so it sits at the origin.
    /// Returns false when it already is, or macOS refused.
    static func makeMain(_ display: GameDisplay) -> Bool {
        guard display.displayID != CGMainDisplayID() else { return false }
        let shift = CGDisplayBounds(display.displayID).origin
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        for screen in all() {
            let origin = CGDisplayBounds(screen.displayID).origin
            CGConfigureDisplayOrigin(config, screen.displayID, Int32(origin.x - shift.x), Int32(origin.y - shift.y))
        }
        guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return true
    }

    /// Puts the screens back the way they're set in System Settings
    static func restore() {
        CGRestorePermanentDisplayConfiguration()
    }
}
