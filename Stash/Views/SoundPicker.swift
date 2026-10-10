//
//  SoundPicker.swift
//  Stash
//
//  Asked the first time a classic game is played: which speaker it should use.
//  Games see only that one device (StashAudio/AudioFilter.c).
//

import SwiftUI

struct SoundPicker: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    let game: Game
    /// Play once the choice is saved. Changing it from the menu doesn't start the game.
    var playAfter = true

    @State private var outputs: [AudioOutputDevice] = []
    @State private var selection = ""

    private var selected: AudioOutputDevice? { outputs.first { $0.uid == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Sound").padding(.bottom, 8)
            Text("Where should \(game.name) play sound?")
                .font(.display(24)).tracking(-0.5).foregroundStyle(Theme.ink)
                .padding(.bottom, 6)
            Text("Games from this era can crash when they see every sound device on your Mac, so this game only sees the one you pick.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            VStack(spacing: 2) {
                row(uid: "", name: "Automatic", detail: "Your Mac's sound output, or its speakers when that's a virtual device",
                    supported: true)
                ForEach(outputs) { device in
                    row(uid: device.uid, name: device.name,
                        detail: device.isSupported ? nil : "May not work", supported: device.isSupported)
                }
            }
            .padding(4)
            .card(radius: 10)

            Group {
                if selected?.isSupported == false {
                    Label("Virtual and combined devices like \(selected?.name ?? "this one") can make the game close as it starts. If that happens, choose Automatic.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                } else {
                    Text("You can change this later from the ••• menu.")
                        .foregroundStyle(Theme.muted)
                }
            }
            .font(.system(size: 11.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    library.setAudioDevice(selection, for: game.id)
                    dismiss()
                    if playAfter { library.play(game.id) }
                } label: {
                    if playAfter { Label("Play", systemImage: "play.fill") } else { Text("Save") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.paper)
        .onAppear {
            outputs = AudioDevices.outputs()
            selection = game.audioDevice ?? ""
            // A saved device that's been unplugged falls back to automatic
            if !selection.isEmpty, !outputs.contains(where: { $0.uid == selection }) { selection = "" }
        }
    }

    private func row(uid: String, name: String, detail: String?, supported: Bool) -> some View {
        Button { selection = uid } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == uid ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selection == uid ? Theme.accent : Theme.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                    if let detail {
                        Text(detail).font(.system(size: 11))
                            .foregroundStyle(supported ? Theme.muted : Theme.warning)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selection == uid ? Theme.ink.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
