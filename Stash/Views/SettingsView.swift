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
    @AppStorage(AudioDevices.settingKey) private var audioDevice = ""
    @State private var audioOutputs: [AudioOutputDevice] = []

    var body: some View {
        Form {
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
            Section("Sound") {
                Picker("Classic games play through", selection: $audioDevice) {
                    Text("Automatic").tag("")
                    ForEach(audioOutputs) { device in
                        Text(device.isSupported ? device.name : "\(device.name) (may not work)").tag(device.uid)
                    }
                    if !audioDevice.isEmpty, !audioOutputs.contains(where: { $0.uid == audioDevice }) {
                        Text("Disconnected device").tag(audioDevice)
                    }
                }
                Text(soundNote)
                    .font(.system(size: 11))
                    .foregroundStyle(selectedOutput?.isSupported == false ? Color.orange : Theme.muted)
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
                            if engines.installing.contains(engine) {
                                ProgressView().controlSize(.small)
                            } else if engine.isInstalled {
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
                     + "Console games run on DuckStation, PCSX2, PPSSPP and Dolphin. Only play games you own.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 720)
        .task {
            engineVersion = (try? await Wine.wineVersion()) ?? "Not installed"
        }
        .onAppear { audioOutputs = AudioDevices.outputs() }
    }

    private var selectedOutput: AudioOutputDevice? {
        audioOutputs.first { $0.uid == audioDevice }
    }

    private var soundNote: String {
        if selectedOutput?.isSupported == false {
            return "Virtual and combined devices like this one can make games close as they start. "
                + "If that happens, switch back to Automatic."
        }
        if !audioDevice.isEmpty, selectedOutput == nil {
            return "This device isn't connected, so games use your Mac's speaker."
        }
        return "Automatic uses your Mac's sound output, or the built-in speakers when that's a virtual device. "
            + "Games see this one device only, no microphones."
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

    private func addBIOS(for engine: ConsoleEngine) {
        let panel = NSOpenPanel()
        panel.message = "Choose the BIOS file dumped from your console"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? engines.addBIOS(url, for: engine)
    }
}
