# DT Manager

DT Manager is a Windows-focused mod manager for Undertale, Deltarune, and similar fangames. It keeps a clean copy of the original game, builds patched mod outputs from ZIP files, and prepares a runnable game folder every time you launch.

It is designed for patch-heavy workflows such as `xdelta`, `GodotDelta`, override-based mods, chained patches, and Steam version-specific mod setups.

## Overview

- Stores a preserved copy of each original game
- Imports mod ZIP files and auto-detects patch type
- Builds a fresh runnable game folder for each launch
- Supports Steam launch, backup, restore, and runtime recovery

## Features

| Feature | Description |
| --- | --- |
| Game import | Copies the full folder based on a selected `.exe` |
| Mod import | Auto-detects `xdelta`, `GodotDelta`, and override-only mods |
| Chained patches | Can build a new mod on top of an already selected mod |
| Steam launch | Replaces the Steam install folder, launches with `steam://run/...`, then restores it |
| Version pinning | Uses `manifest_id` from `DTManager.mod.json` to build against a cached Steam version |
| Thumbnails | Stores and previews `thumbnail.dm.png` for games and mods |
| Recovery safety | Supports backup, restore, forced cleanup, and restart recovery for Steam runs |

## Directory Layout

```text
DTManager/
├─ Game/
│  └─ <game_name>/
│     ├─ config.dm
│     └─ thumbnail.dm.png
├─ Mod/
│  └─ <game_name>/
│     └─ <mod_name>/
│        ├─ config.dm
│        ├─ mod.dm.json
│        └─ thumbnail.dm.png
├─ Run/
├─ Patcher/
│  ├─ xdelta.exe
│  ├─ GodotDelta/
│  └─ DepotDownloader/
├─ GameVersions/
│  └─ <app_id>/
│     └─ <manifest_id>/
├─ app_config.dm
└─ runtime_state.dm
```

| Path | Description |
| --- | --- |
| `Game/` | Stored copies of original game folders |
| `Mod/` | Built mod outputs after patching |
| `Run/` | Temporary runtime folder rebuilt before each launch |
| `Patcher/` | Storage for external patcher tools |
| `GameVersions/` | Cached Steam game versions by manifest |
| `app_config.dm` | App settings and Steam login information |
| `runtime_state.dm` | Runtime recovery state for Steam launches |

## Workflow

### Add Game

Game import uses a selected `.exe` path, not a directory path.

Process:

1. The user selects an executable file.
2. DT Manager copies the entire folder containing that executable into `Game/<game_name>/`.
3. The relative path of the selected `.exe` is saved as `run_path` in `config.dm`.
4. If the folder is inside a Steam library, DT Manager reads `appmanifest_*.acf` and stores `steam_uri` and `steam_game_path` automatically.

This means the internal contents do not need to be known in advance. The whole folder is copied as-is, including `.pck`, `.win`, `.mp4`, and nested directories.

### Add Mod

Mod import uses a single ZIP file as input.

Supported mod types:

- `xdelta` patches
- `.pck` patches for `GodotDelta`
- Plain file overrides
- Chained patches built on top of an already applied mod

### Base Patch Handling

When a mod is added, the ZIP is extracted to a temporary folder and its contents are detected automatically.

- If `.xdelta` files are found, the mod is treated as an xdelta patch.
- If `.pck` files are found, the mod is treated as a GodotDelta patch.
- If neither is found, the mod is treated as an override-only mod.

The built result is stored in `Mod/<game_name>/<mod_name>/`.

#### File Matching

`xdelta` and `.pck` patch files are matched against base files by name.

Examples:

- `data.xdelta` → `data.win`
- `game.xdelta` → looks for a base file named `game`
- `chapter1/data.xdelta` → looks for a matching base file in that path or with the same basename

In other words, if the base name matches, DT Manager will try to apply the patch even when the extension differs.

#### Override Files

Regular non-patch files inside the ZIP are also copied into the mod output.  
For example, `lang.json` and `options.ini` can be included as direct override files without patching.

#### Chained Patches

If a mod is already selected and the user presses `Add Mod` again, the new mod is built on top of the currently selected mod instead of the original game.

This supports flows such as:

- Second-stage patch: built from the original game
- Third-stage patch: built from an already patched mod

This makes it possible to stack patches in sequence.

### Launching

If no mod is selected, DT Manager launches the base game.

Standard launch flow:

1. Clear the `Run/` folder.
2. Copy the selected base game folder into `Run/`.
3. If a mod is selected, merge the mod contents into `Run/`.
4. Launch the executable using the `run_path` stored in `config.dm`.

## `DTManager.mod.json`

If a mod ZIP contains `DTManager.mod.json`, it is used as additional metadata.

Its main use right now is Steam version pinning.

Example:

```json
{
  "app_id": "1671210",
  "manifest_id": "2856471167011435804"
}
```

| Key | Description |
| --- | --- |
| `app_id` | Steam app ID |
| `manifest_id` | The Steam manifest version this mod expects |

If `app_id` and `manifest_id` are present, DT Manager first checks `GameVersions/<app_id>/<manifest_id>/`.  
If the cache does not exist, it downloads that exact version with `DepotDownloader` and uses it as the base for patching.

Notes:

- Steam login information is required for this flow.
- The user must log into Steam from Settings first.

## Steam Login and Version Cache

In the App Settings tab, the user can save a Steam username and password and perform a Steam login.

Login behavior:

- Uses `DepotDownloader`
- Shows a loading message when Steam Guard approval is required in the mobile app
- Allows manifest-specific downloads after a successful login

Version cache behavior:

- Reads manifest lists from `database/<app_id>/game.json`
- Reads depot information from `database/<app_id>/manifests/<manifest_id>.json`
- Downloads the required files with `DepotDownloader`
- Stores the result in `GameVersions/<app_id>/<manifest_id>/`

This cache prevents repeated downloads when the same manifest is needed again.

## Steam Launch Flow

For Steam games, DT Manager temporarily replaces the real Steam install folder instead of doing a normal direct launch.

Process:

1. Back up the original Steam game folder.
2. Prepare the built game files in `Run/`.
3. Clear the actual Steam game folder.
4. Copy the contents of `Run/` into the Steam game folder.
5. Launch `steam://run/<app_id>`.
6. Wait for the game to exit.
7. Restore the original Steam game folder.

## Safety and Recovery

DT Manager includes recovery protection to avoid leaving a Steam install in a broken state.

- Blocks closing the DT Manager window while files are being copied or restored
- Blocks exit if a recovery state still exists while the game is running
- Attempts recovery on the next launch if the app was closed mid-process using `runtime_state.dm`
- Force-kills the running game before restore when necessary

## Thumbnails

Both games and mods can have thumbnails.

Thumbnails are set from the Settings dialog using the image selection button.

Stored at:

- Game: `Game/<game_name>/thumbnail.dm.png`
- Mod: `Mod/<game_name>/<mod_name>/thumbnail.dm.png`

Preview priority:

1. The selected mod thumbnail
2. The base game thumbnail

If the mod selection is cleared, the preview falls back to the base game thumbnail.

## Settings Dialog

The Settings dialog is split into two tabs.

### App Settings

- Steam username
- Steam password
- Steam login
- Database check
- Patcher download

### Game / Mod Settings

- Rename
- Change Steam game folder
- Change thumbnail

## External Tools

The project currently uses:

- `xdelta.exe`
- `gddelta.exe` from [GodotDelta](https://github.com/wheedo07/GodotDelta)
- `DepotDownloader.exe` from [DepotDownloader](https://github.com/SteamRE/DepotDownloader)

## UI Behavior

- `Add Game`, `Add Mod`, and `Settings` dialogs close automatically when they lose focus.
- They do not auto-close while an internal file picker or folder picker is open.
