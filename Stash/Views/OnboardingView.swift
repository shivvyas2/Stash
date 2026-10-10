//
//  OnboardingView.swift
//  Stash
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var runtime: RuntimeManager

    private let points: [(title: String, detail: String)] = [
        ("Windows games", "Run .exe games and installers, translated to Apple Silicon and Metal."),
        ("Console games", "PlayStation, PS2, PSP, GameCube and Wii games you own, launched like Mac apps."),
        ("Made sharper", "Retina resolution, widescreen fixes and upscaling, set up for you.")
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Welcome")
                    .padding(.bottom, 14)
                Text("Stash.")
                    .font(.display(96)).tracking(-4)
                    .foregroundStyle(Theme.ink)
                    .padding(.bottom, 8)
                Text("Your games, on your Mac.")
                    .font(.system(size: 22, weight: .medium)).tracking(-0.3)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 48)

                Hairline(color: Theme.ink)
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 12, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                            .frame(width: 24, alignment: .leading)
                        Text(point.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 150, alignment: .leading)
                        Text(point.detail)
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 16)
                    Hairline()
                }

                content
                    .padding(.top, 40)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 72)
            .padding(.top, 96)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }

    @ViewBuilder private var content: some View {
        switch runtime.phase {
        case .idle, .ready:
            HStack(spacing: 16) {
                Button("Get Started") { runtime.start() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.ink))
                    .keyboardShortcut(.defaultAction)
                Text("Downloads the game engine, about 240 MB.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        case .needsRosetta:
            HStack(spacing: 16) {
                Button("Install Rosetta") { runtime.installRosetta() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.ink))
                Text("Apple's Rosetta 2 is needed to run Windows games.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    Text("\(Int(runtime.progress * 100))%")
                        .font(.display(34)).tracking(-1).monospacedDigit().foregroundStyle(Theme.ink)
                    Spacer()
                    Text(runtime.totalBytes > 0
                         ? "\(bytes(runtime.receivedBytes)) of \(bytes(runtime.totalBytes))"
                         : "Starting download…")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.hairline)
                        Rectangle().fill(Theme.ink).frame(width: proxy.size.width * runtime.progress)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: 420)
        case .installing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Installing the game engine…").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.warning)
                Button("Try Again") { runtime.start() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.ink))
            }
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
