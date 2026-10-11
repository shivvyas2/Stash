//
//  SettingsView.swift
//  Stash
//

import SwiftUI
import WhiskyKit

struct SettingsView: View {
    @EnvironmentObject private var runtime: RuntimeManager
    @EnvironmentObject private var engines: EngineManager
    @EnvironmentObject private var library: GameLibrary
    @AppStorage("installLocation") private var installLocation = StashPaths.defaultInstallLocation
    @State private var engineVersion = "…"
    @State private var artworkKey = ""
    @State private var artworkStatus: String?
    @State private var checkingKey = false

    var body: some View {
        Form {
            Section("Stash") {
                LabeledContent("Version", value: Self.appVersion)
            }
            Section("Games") {
                LabeledContent("New games install to") {
                    HStack {
                        Text(installLocation.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle)
                        Button("Change…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { installLocation = url }
                        }
                    }
                }
            }
            Section("Artwork") {
                LabeledContent("SteamGridDB API key") {
                    HStack {
                        SecureField("", text: $artworkKey).frame(width: 220)
                        if checkingKey {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Save", action: saveKey).disabled(artworkKey.isEmpty)
                        }
                    }
                }
                HStack {
                    Text(artworkStatus ?? (ArtworkService.isConfigured ? "Key saved. New games get covers automatically."
                                                                         : "Free key from your SteamGridDB account."))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer()
                    Link("Get a Key", destination: ArtworkService.keyPage)
                    Button("Fetch Missing Covers") { library.fetchMissingArtwork() }
                        .disabled(!ArtworkService.isConfigured)
                }
            }
            Section("Game engine") {
                LabeledContent("Version", value: engineVersion)
                LabeledContent("Runtime package", value: WhiskyWineInstaller.whiskyWineVersion().map { "\($0)" } ?? "Not installed")
                LabeledContent("Graphics", value: "Apple D3DMetal, WineD3D, DXVK")
                HStack {
                    Button("Show Logs") { NSWorkspace.shared.open(Wine.logsFolder) }
                    Button("Reinstall Engine") {
                        WhiskyWineInstaller.uninstall()
                        runtime.phase = .idle
                    }
                }
            }
            Section("Consoles") {
                ForEach(ConsoleEngine.allCases) { engine in
                    LabeledContent {
                        HStack {
                            if engine.needsBIOS {
                                Text(engine.hasBIOS ? "BIOS ✓" : "No BIOS")
                                    .foregroundStyle(engine.hasBIOS ? Theme.positive : Theme.muted)
                                Button("Add BIOS…") { addBIOS(for: engine) }
                            }
                            if engine.needsFirmware, engine.isInstalled, !engines.installing.contains(engine) {
                                Text(engine.hasFirmware ? "System software ✓" : "No system software")
                                    .foregroundStyle(engine.hasFirmware ? Theme.positive : Theme.muted)
                            }
                            if engines.installing.contains(engine) {
                                ProgressView().controlSize(.small)
                            } else if engine.isInstalled, engine.hasFirmware {
                                Button("Remove") { engines.remove(engine) }
                            } else {
                                Button("Install") { Task { try? await engines.install(engine) } }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(engine.displayName)
                            Text("Powered by \(engine.credit)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("Stash is built on Whisky, Wine and Apple's Game Porting Toolkit (GPL-3.0). "
                     + "Enhancements are community mods by ThirteenAG, CookiePLMonster (Silent) and aap. "
                     + "Console games run on DuckStation, PCSX2, RPCS3, PPSSPP and Dolphin. Only play games you own.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 720)
        .task {
            engineVersion = (try? await Wine.wineVersion()) ?? "Not installed"
        }
    }

    private func saveKey() {
        let key = artworkKey.trimmingCharacters(in: .whitespacesAndNewlines)
        checkingKey = true
        Task {
            if await ArtworkService.validate(key: key) {
                ArtworkService.apiKey = key
                artworkKey = ""
                artworkStatus = "Key saved. Fetching covers…"
                library.fetchMissingArtwork()
            } else {
                artworkStatus = "SteamGridDB didn't accept that key."
            }
            checkingKey = false
        }
    }

    /// e.g. "1.0.0 (build 11)"
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (build \(build))"
    }

    private func addBIOS(for engine: ConsoleEngine) {
        let panel = NSOpenPanel()
        panel.message = "Choose the BIOS file dumped from your console"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? engines.addBIOS(url, for: engine)
    }
}
