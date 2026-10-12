//
//  StashApp.swift
//  Stash
//
//  Play Windows games on your Mac. Built on Whisky, Wine and Apple's
//  Game Porting Toolkit.
//

import SwiftUI

@main
struct StashApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var library = GameLibrary()
    @StateObject private var runtime = RuntimeManager()

    var body: some Scene {
        Window("Stash", id: "main") {
            RootView()
                .environmentObject(library)
                .environmentObject(library.engines)
                .environmentObject(runtime)
                .preferredColorScheme(.light)
                .frame(minWidth: 1080, minHeight: 700)
                .task {
                    appDelegate.urlHandler = library.handle(url:)
                    appDelegate.terminationHandler = library.stopAll
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") {
                    NotificationCenter.default.post(name: .stashAddGame, object: nil)
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(library.engines)
                .environmentObject(runtime)
                .preferredColorScheme(.light)
        }
    }
}

/// stash:// links arrive through the app delegate; SwiftUI's onOpenURL doesn't receive them for a Window scene
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []

    var urlHandler: ((URL) -> Void)? {
        didSet {
            guard let urlHandler else { return }
            pending.forEach(urlHandler)
            pending.removeAll()
        }
    }

    /// Games started from Stash close with it
    var terminationHandler: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        terminationHandler?()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let urlHandler else {
            pending += urls
            return
        }
        urls.forEach(urlHandler)
    }
}

extension Notification.Name {
    static let stashAddGame = Notification.Name("stashAddGame")
    /// Posted when a Windows game is played without Rosetta, so the window can offer to install it
    static let stashNeedsRosetta = Notification.Name("stashNeedsRosetta")
}
