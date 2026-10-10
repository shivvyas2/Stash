//
//  WhiskyWineInstaller.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import SemanticVersion

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    /// Wine runtime: Game Porting Toolkit (Wine + D3DMetal) built by Gcenx
    public static let runtimeURL = URL(
        string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/"
        + "Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz"
    )!
    /// DXVK for macOS (DirectX 10/11 -> Vulkan -> Metal via MoltenVK)
    static let dxvkURL = URL(
        string: "https://github.com/Gcenx/DXVK-macOS/releases/download/"
        + "v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
    )!
    /// Bump this when `runtimeURL` changes so existing installs get updated
    public static let runtimeVersion = SemanticVersion(3, 0, 3)

    public static func isWhiskyWineInstalled() -> Bool {
        return whiskyWineVersion() != nil
    }

    public static func install(from: URL) {
        do {
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            try Tar.untar(tarBall: from, toURL: staging)
            try FileManager.default.removeItem(at: from)
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(
                at: staging.appending(path: "Game Porting Toolkit.app/Contents/Resources/wine"),
                to: libraryFolder.appending(path: "Wine")
            )

            let dxvkTarball = staging.appending(path: "dxvk.tar.gz")
            try Data(contentsOf: dxvkURL).write(to: dxvkTarball)
            try Tar.untar(tarBall: dxvkTarball, toURL: staging)
            try FileManager.default.moveItem(
                at: staging.appending(path: "dxvk-macOS-async-v1.10.3-20230507-repack"),
                to: libraryFolder.appending(path: "DXVK")
            )

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try encoder.encode(WhiskyWineVersion(version: runtimeVersion))
                .write(to: libraryFolder.appending(path: "WhiskyWineVersion").appendingPathExtension("plist"))
        } catch {
            print("Failed to install WhiskyWine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        if let localVersion = whiskyWineVersion(), localVersion < runtimeVersion {
            return (true, runtimeVersion)
        }
        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
                .appending(path: "WhiskyWineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersion.self, from: data)
            return info.version
        } catch {
            print(error)
            return nil
        }
    }
}

struct WhiskyWineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
