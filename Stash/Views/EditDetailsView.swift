//
//  EditDetailsView.swift
//  Stash
//
//  Rename a game and change what Stash shows about it.
//

import SwiftUI

struct EditDetailsView: View {
    @EnvironmentObject private var library: GameLibrary
    @Environment(\.dismiss) private var dismiss
    let game: Game

    @State private var name = ""
    @State private var year = ""
    @State private var platform: Platform = .windows
    @State private var notes = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Details").padding(.bottom, 8)
            Text("Edit \(game.name)")
                .font(.display(24)).tracking(-0.5).foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                field("Name") {
                    TextField("Game name", text: $name).textFieldStyle(.roundedBorder)
                }
                field("Year") {
                    TextField(game.knownGame?.year ?? "Release year", text: $year)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                if game.platform.isConsole {
                    field("Console") {
                        Picker("", selection: $platform) {
                            ForEach(Platform.allCases.filter(\.isConsole)) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
                field("Notes") {
                    TextEditor(text: $notes)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 96)
                        .card(radius: 6)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 24)
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.paper)
        .onAppear {
            name = game.name
            year = game.year ?? ""
            platform = game.platform
            notes = game.notes
        }
    }

    private func save() {
        let year = year.trimmingCharacters(in: .whitespaces)
        library.update(game.id) {
            $0.name = trimmedName
            // Matching the catalog keeps following it; clearing the field hides the year
            $0.customYear = year == $0.knownGame?.year ? nil : year
            $0.platform = platform
            $0.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        dismiss()
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            content()
        }
    }
}
