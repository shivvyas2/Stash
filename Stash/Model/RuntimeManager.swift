//
//  RuntimeManager.swift
//  Stash
//
//  Downloads and installs the Windows runtime (Wine + Apple's D3DMetal + DXVK).
//

import Foundation
import WhiskyKit

@MainActor
final class RuntimeManager: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case unsupportedMac
        case needsRosetta
        case installingRosetta
        case downloading
        case installing
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var receivedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0

    private var observation: NSKeyValueObservation?

    var isInstalled: Bool { WhiskyWineInstaller.isWhiskyWineInstalled() }

    override init() {
        super.init()
        // A macOS update can remove Rosetta after the runtime is installed. Games then exit without a word.
        if !Mac.isAppleSilicon {
            phase = .unsupportedMac
        } else if !Mac.hasRosetta {
            phase = .needsRosetta
        } else {
            phase = isInstalled ? .ready : .idle
        }
    }

    /// Sends the library back to the Rosetta step when Rosetta has gone missing since launch
    func recheckRosetta() {
        if phase == .ready, Mac.isAppleSilicon, !Mac.hasRosetta { phase = .needsRosetta }
    }

    func checkForUpdate() async {
        let (needsUpdate, _) = await WhiskyWineInstaller.shouldUpdateWhiskyWine()
        if needsUpdate, phase == .ready { phase = .idle }
    }

    func start() {
        guard Mac.hasRosetta else {
            phase = .needsRosetta
            return
        }
        if isInstalled, phase != .idle { phase = .ready } else { download() }
    }

    func installRosetta() {
        phase = .installingRosetta
        Task {
            let succeeded = (try? await Rosetta2.installRosetta()) ?? false
            if succeeded, Mac.hasRosetta {
                if isInstalled { phase = .ready } else { download() }
            } else {
                phase = .failed("Rosetta 2 couldn't be installed. Check your internet connection and try again, "
                                + "or run softwareupdate --install-rosetta --agree-to-license in Terminal.")
            }
        }
    }

    private func download() {
        phase = .downloading
        progress = 0
        let task = URLSession(configuration: .ephemeral).downloadTask(
            with: WhiskyWineInstaller.runtimeURL
        ) { [weak self] url, response, error in
            // The temp file is deleted once this handler returns, so move it first
            var saved: URL?
            if let url, (response as? HTTPURLResponse)?.statusCode == 200 {
                let target = FileManager.default.temporaryDirectory.appending(path: "StashRuntime.tar.xz")
                try? FileManager.default.removeItem(at: target)
                if (try? FileManager.default.moveItem(at: url, to: target)) != nil { saved = target }
            }
            Task { @MainActor in
                guard let self else { return }
                if let saved {
                    self.install(from: saved)
                } else {
                    self.phase = .failed(error?.localizedDescription ?? "The download could not be completed.")
                }
            }
        }
        // task.progress counts in percent units, so read the byte counts from the task itself
        observation = task.progress.observe(\.fractionCompleted) { [weak self, weak task] progress, _ in
            let received = task?.countOfBytesReceived ?? 0
            let expected = task?.countOfBytesExpectedToReceive ?? 0
            Task { @MainActor in
                self?.progress = progress.fractionCompleted
                self?.receivedBytes = received
                self?.totalBytes = expected
            }
        }
        task.resume()
    }

    private func install(from archive: URL) {
        phase = .installing
        Task.detached {
            WhiskyWineInstaller.install(from: archive)
            let installed = WhiskyWineInstaller.isWhiskyWineInstalled()
            await MainActor.run {
                self.phase = installed ? .ready : .failed("The runtime could not be installed.")
            }
        }
    }
}
