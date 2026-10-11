//
//  DiscDrive.swift
//  Stash
//
//  A CD drive for Windows installers. The disc image is mounted in a folder
//  Stash owns, and the game's Windows space sees that folder as a CD drive
//  with a fixed letter. Games on several discs ask for the next one in the
//  same drive, so swapping the image keeps the letter and the installer finds
//  the new disc where it expects it.
//

import Foundation
import WhiskyKit

@MainActor
final class DiscDrive {
    /// Lowercase drive letter, e.g. "s"
    let letter: String
    /// Where the current disc's files appear on the Mac
    let mountPoint: URL
    private(set) var image: URL
    private let environment: URL

    private var dosdevices: URL { environment.appending(path: "dosdevices") }

    /// Mounts `image` and gives it to the environment as a CD drive
    init(image: URL, environment: URL) async throws {
        self.image = image
        self.environment = environment
        mountPoint = StashPaths.data.appending(path: "Disc Drive/\(UUID().uuidString)")

        // Wine gives every mounted volume a letter of its own, so take one before mounting
        let dosdevices = environment.appending(path: "dosdevices")
        let used = Set((try? FileManager.default.contentsOfDirectory(atPath: dosdevices.path)) ?? [])
        guard let free = "defghijklmnopqrstuvwxy".map(String.init).first(where: { !used.contains("\($0):") }) else {
            throw StashError("This game's Windows space has no free drive letter for the disc.")
        }
        letter = free
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dosdevices.appending(path: "\(letter):"),
                                                   withDestinationURL: mountPoint)
        // Installers check that the disc really is in a CD drive
        try await Wine.runWine(["reg", "add", #"HKLM\Software\Wine\Drives"#, "/v", "\(letter):", "/d", "cdrom", "/f"],
                               bottle: Bottle(bottleUrl: environment, isAvailable: true))
        try mount(image)
    }

    /// The drive as Windows programs see it, e.g. S:\
    var windowsRoot: String { "\(letter.uppercased()):\\" }

    /// Windows path of a file on the current disc
    func windowsPath(of file: URL) -> String {
        let inside = file.path(percentEncoded: false).dropFirst(mountPoint.path(percentEncoded: false).count)
        return windowsRoot + inside.split(separator: "/").joined(separator: "\\")
    }

    /// Takes out the current disc and puts `image` in its place
    func swap(to image: URL) throws {
        try unmount()
        do {
            try mount(image)
        } catch {
            // Put the previous disc back so the installer isn't left with an empty drive
            try? mount(self.image)
            throw error
        }
        self.image = image
    }

    /// Unmounts the disc and removes the drive from the environment
    func eject() {
        try? unmount()
        try? FileManager.default.removeItem(at: dosdevices.appending(path: "\(letter):"))
        try? FileManager.default.removeItem(at: mountPoint)
    }

    private func mount(_ image: URL) throws {
        let output: String
        do {
            output = try Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                                        "-mountpoint", mountPoint.path, image.path])
        } catch {
            throw StashError("\(image.lastPathComponent) couldn't be opened as a disc.")
        }
        // The line naming the mount point holds the disc's device, e.g. /dev/disk31
        // Wine reads the disc's label from the device, and installers often check the label
        if let line = output.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(mountPoint.path) }),
           let device = line.split(whereSeparator: \.isWhitespace).first, device.hasPrefix("/dev/disk") {
            let link = dosdevices.appending(path: "\(letter)::")
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/dev/r" + device.dropFirst(5))
        }
    }

    private func unmount() throws {
        try? FileManager.default.removeItem(at: dosdevices.appending(path: "\(letter)::"))
        do {
            try Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
        } catch {
            // An installer may still hold a file open on the disc while it waits for the next one
            do {
                try Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
            } catch {
                throw StashError("The current disc is still in use. Close any message about it, then try again.")
            }
        }
    }
}
