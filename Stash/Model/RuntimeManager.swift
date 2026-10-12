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
        case needsRosetta
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
        if !Rosetta2.isRosettaInstalled {
            phase = .needsRosetta
        } else {
            phase = isInstalled ? .ready : .idle
        }
    }

    func checkForUpdate() async {
        let (needsUpdate, _) = await WhiskyWineInstaller.shouldUpdateWhiskyWine()
        if needsUpdate, phase != .needsRosetta { phase = .idle }
    }

    func start() {
        guard Rosetta2.isRosettaInstalled else {
            phase = .needsRosetta
            return
        }
        download()
    }

    func installRosetta() {
        Task {
            do {
                if try await Rosetta2.installRosetta() {
                    if isInstalled { phase = .ready } else { download() }
                } else {
                    phase = .failed("Rosetta 2 could not be installed.")
                }
            } catch {
                phase = .failed(error.localizedDescription)
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
