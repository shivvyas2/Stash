# Stash

A macOS launcher for Windows and console games on Apple Silicon.

Add a game from an installer, a disc image, a folder or a console game file, and Stash sets up everything it needs to run: a private Windows environment, the right graphics path to Metal, and optional upgrades like widescreen fixes. Games show up in one library with cover art, playtime and a Play button.

![Library](docs/library.jpg)

![Game page](docs/game.jpg)

## Features

- **Windows games.** Runs `.exe` and `.msi` games through Wine and Apple's Game Porting Toolkit. Each game gets its own Windows environment, so games can't break each other.
- **Console games.** PlayStation, PlayStation 2, PSP, GameCube and Wii games boot straight into fullscreen. The platform is detected from the disc header.
- **Graphics.** DirectX 8–12 is translated to Metal. Per-game Retina rendering, a performance HUD, and 1×–6× internal resolution for console games.
- **One-click upgrades** for GTA III, Vice City and San Andreas: widescreen and HUD fixes with SMAA, SilentPatch, and SkyGfx. Every file a mod overwrites is backed up, so removing it restores the original game.
- **Cover art** from SteamGridDB, fetched automatically when a game is added.
- **Mac apps.** Any game can be exported as a `.app` for Launchpad, the Dock or Spotlight.
- **Playtime tracking** with a weekly chart and session history.

## Requirements

- A Mac with Apple Silicon (M1 or later)
- macOS 14 Sonoma or later
- Rosetta 2 (Stash offers to install it)
- About 250 MB for the Windows runtime, downloaded on first launch

## Install

Download `Stash.zip` from the [latest release](../../releases/latest), unzip it and move `Stash.app` to Applications.

Stash is not notarized yet, so macOS blocks the first launch. Right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Stash.app
```

## Build from source

Requires Xcode 16 or later.

```sh
git clone https://github.com/shivvyas2/Stash.git
cd Stash
open Stash.xcodeproj
```

Press ⌘R. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); run `xcodegen generate` after adding or removing source files.

## How it works

### Architecture

```mermaid
flowchart TB
    subgraph UI["Stash app (SwiftUI)"]
        Views["Library · Game page · Add Game · Settings"]
    end

    subgraph Core["Model layer"]
        Library["GameLibrary<br/>library state, launch, playtime"]
        Runtime["RuntimeManager<br/>downloads the Windows runtime"]
        Engines["EngineManager<br/>console engines"]
        Mods["ModInstaller<br/>backups, INI settings"]
        Art["ArtworkService<br/>SteamGridDB"]
    end

    subgraph Windows["Windows path"]
        Kit["WhiskyKit<br/>prefixes, process control"]
        Wine["Wine (Game Porting Toolkit build)"]
        Rosetta["Rosetta 2<br/>x86 → ARM"]
        D3DM["D3DMetal<br/>DirectX 11/12"]
        WineD3D["WineD3D<br/>DirectX 8/9"]
        DXVK["DXVK + MoltenVK<br/>DirectX 10/11, optional"]
    end

    subgraph Consoles["Console path"]
        Duck["DuckStation · PS1"]
        PCSX2["PCSX2 · PS2"]
        PPSSPP["PPSSPP · PSP"]
        Dolphin["Dolphin · GameCube, Wii"]
    end

    Metal["Metal → GPU"]

    Views --> Library
    Views --> Runtime
    Library --> Kit
    Library --> Engines
    Library --> Mods
    Library --> Art
    Runtime --> Kit
    Kit --> Wine
    Wine --> Rosetta
    Wine --> D3DM --> Metal
    Wine --> WineD3D --> Metal
    Wine --> DXVK --> Metal
    Engines --> Duck & PCSX2 & PPSSPP & Dolphin
    Duck & PCSX2 & PPSSPP & Dolphin --> Metal
```

### Launching a Windows game

```mermaid
sequenceDiagram
    participant U as Player
    participant L as GameLibrary
    participant K as WhiskyKit
    participant W as Wine
    participant G as Game

    U->>L: Play
    L->>K: apply per-game settings (renderer, Retina, HUD, DLL overrides)
    K->>W: wine start /wait /d <game folder> /unix <game.exe>
    W->>G: run under Rosetta 2, DirectX → Metal
    G-->>W: player quits
    W-->>L: process exits
    L->>L: record session and playtime
```

`start /wait` keeps the process attached until the game exits, which is how playtime is measured. Mods that replace a system DLL, like the `d3d8.dll` ASI loader in the Vice City widescreen fix, are loaded through `WINEDLLOVERRIDES`.

### Launching a console game

Console engines are open-source emulators that Stash downloads on first use into `~/Library/Application Support/Stash/Engines` and drives from the command line. The engine's own interface stays hidden: the game starts fullscreen in batch mode, and quitting the game returns to Stash.

| Platform | Engine | How Stash starts it |
|---|---|---|
| PlayStation | DuckStation | `-batch -nogui -fullscreen`, resolution and widescreen written to `settings.ini` |
| PlayStation 2 | PCSX2 | `-batch -nogui -fullscreen -gamecfg <per-game ini>` |
| PSP | PPSSPP | `--fullscreen --appendconfig=<per-game ini>` |
| GameCube, Wii | Dolphin | `-b -v Metal -C GFX.Settings.InternalResolution=<n>` |

PlayStation and PlayStation 2 games need a BIOS dumped from your own console. Stash can't include it.

### Installing an upgrade

```mermaid
flowchart LR
    A[Download mod archive] --> B[List files in archive]
    B --> C{File already in game folder?}
    C -- yes --> D[Copy original to backup folder]
    C -- no --> E[Record as new file]
    D --> F[Copy mod file into game folder]
    E --> F
    F --> G[Write manifest.json]
```

Removing an upgrade reads the manifest, deletes the files the mod added and restores the backups. Some mods also need an original file kept under a new name first (San Andreas' `vorbisFile.dll` becomes `vorbisHooked.dll`); that is declared per mod in `Catalog.swift`.

## Project layout

```
Stash/
  StashApp.swift            app entry, URL handling (stash://play/<id>, stash://open/<id>)
  Model/
    Game.swift              game record, platforms, graphics modes
    GameLibrary.swift       library state, environments, launching, Mac app export
    RuntimeManager.swift    Windows runtime download and install
    ConsoleEngines.swift    console engine download, configuration and launch
    ModInstaller.swift      mod install/uninstall with backups, INI editing
    Catalog.swift           recognised games and their upgrades
    ArtworkService.swift    SteamGridDB client, API key in the Keychain
    Support.swift           paths and small helpers
  Views/                    SwiftUI views and the design system (Theme.swift)
WhiskyKit/                  Wine prefix and process management (from Whisky)
project.yml                 XcodeGen project definition
```

## Where Stash keeps data

| What | Location |
|---|---|
| Library, covers, mod backups, console engines | `~/Library/Application Support/Stash` |
| Windows runtime (Wine, D3DMetal, DXVK) | `~/Library/Application Support/app.stash.Stash/Libraries` |
| Game environments | `~/Games` by default, chosen per game |
| Wine logs | `~/Library/Logs/app.stash.Stash` |
| SteamGridDB API key | macOS Keychain |

## Built on

Stash started as a fork of [Whisky](https://github.com/Whisky-App/Whisky), which is no longer maintained. The Whisky app was replaced entirely; its `WhiskyKit` package still handles Wine prefixes and processes, with changes to install the runtime from new sources.

- [Wine](https://www.winehq.org) and CodeWeavers' CrossOver sources
- Apple's [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) (D3DMetal), using the builds published by [Gcenx](https://github.com/Gcenx/game-porting-toolkit)
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) and [MoltenVK](https://github.com/KhronosGroup/MoltenVK)
- [DuckStation](https://github.com/stenzek/duckstation), [PCSX2](https://github.com/PCSX2/pcsx2), [PPSSPP](https://github.com/hrydgard/ppsspp) and [Dolphin](https://dolphin-emu.org)
- [Widescreen Fixes Pack](https://github.com/ThirteenAG/WidescreenFixesPack) by ThirteenAG, [SilentPatch](https://github.com/CookiePLMonster/SilentPatch) by CookiePLMonster, [SkyGfx](https://github.com/aap/skygfx) by aap
- Cover art from [SteamGridDB](https://www.steamgriddb.com)

## Legal

Stash doesn't include or download any games or console BIOS files. Use it with games you own. Stash is not affiliated with Apple, Microsoft, Sony, Nintendo, Rockstar Games or any of the projects above.

## License

[GPL-3.0](LICENSE), the same license as Whisky.
