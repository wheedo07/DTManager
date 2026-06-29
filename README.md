# DT Manager

DT Manager is a Windows-only mod manager for UNDERTALE, DELTARUNE, and similar GameMaker or Godot-based fangames.

It is built for ZIP-based mod distribution, version-sensitive patching, Steam launch support, and save slot management.

## What It Does

- Imports a game from a selected `.exe`
- Copies the full game folder into DT Manager
- Imports mod ZIP files and auto-detects how they should be applied
- Builds mod outputs into `Mod/<game>/<mod>/`
- Rebuilds `Run/` every time a game is launched
- Can launch directly or through Steam
- Can cache specific Steam manifest versions for version-locked mods
- Can back up, restore, import, export, rename, and delete save slots

## Supported Mod Inputs

DT Manager detects mod type automatically from the ZIP contents.

- `xdelta` patches
- `GodotDelta` `.pck` patches
- override-only mods
- chained patches built on top of an existing mod

## Project Layout

When exported, DT Manager uses this structure next to the executable:

```text
DTManager/
├─ DTManager.exe
├─ Files/
│  ├─ GameSave/
│  │  └─ <game_name>/
│  │     └─ <slot_name>/
│  └─ GameVersions/
│     └─ <app_id>/
│        └─ <manifest_id>/
├─ Game/
│  └─ <game_name>/
│     ├─ config.dm
│     └─ thumbnail.dm.png
├─ Mod/
│  └─ <game_name>/
│     └─ <mod_name>/
│        ├─ config.dm
│        └─ thumbnail.dm.png
├─ Patcher/
│  ├─ GodotDelta/
│  └─ DepotDownloader/
├─ Run/
├─ app_config.dm
└─ runtime_state.dm
```

## Add Game

`Add Game` takes an `.exe` path, not a folder path.

Flow:

1. Select the game executable.
2. DT Manager copies the entire folder that contains that executable into `Game/<game_name>/`.
3. The selected executable is stored as a relative `run_path` in `config.dm`.
4. If the folder is inside a Steam library, DT Manager also stores Steam metadata automatically.

The game folder is copied as-is. DT Manager does not need to know ahead of time whether the game uses `.win`, `.pck`, videos, or nested folders.

## Add Mod

`Add Mod` takes a ZIP file.

The ZIP is extracted to a temporary location and then processed automatically:

- If `.xdelta` files are found, DT Manager applies xdelta patches.
- If `.pck` files are found, DT Manager uses GodotDelta.
- If neither is found, DT Manager treats the ZIP as direct file overrides.

The built result is stored in `Mod/<game_name>/<mod_name>/`.

### File Matching

Patch files are matched to base files by name.

Examples:

- `data.xdelta` matches `data.win`
- `chapter1/data.xdelta` matches the corresponding file inside `chapter1/`
- `game.pck` patches a base file with the same base name

Non-patch files such as `lang.json` are copied as regular overrides.

### Chained Patches

If a mod is already selected, pressing `Add Mod` again builds the new mod on top of that selected mod.

This supports:

- second-stage patches
- third-stage patches
- stacked patch workflows

DT Manager stores only the changed result files inside the new mod folder.

## Launch Flow

If no mod is selected, DT Manager launches the base game.

Before each launch:

1. `Run/` is cleared.
2. The selected game base is copied into `Run/`.
3. If a mod is selected, that mod is merged into `Run/`.
4. The executable from `run_path` is launched.

## Steam Launch

For Steam games, `use_steam_launch` can be enabled per game.

Steam launch flow:

1. Back up the real Steam install folder.
2. Save runtime recovery state.
3. Clear the Steam install folder.
4. Copy the prepared `Run/` files into the Steam install folder.
5. Open `steam://run/<app_id>`.
6. Wait for the game process to exit.
7. Restore the original Steam install folder.
8. Clear the runtime recovery state.

If DT Manager detects unfinished runtime recovery data on the next startup, it can restore the original Steam game files.

## Version-Locked Mods

If a mod ZIP contains `DTManager.mod.json`, DT Manager can build the mod against a specific Steam version.

Example:

```json
{
  "app_id": "1671210",
  "manifest_id": "2856471167011435804",
  "name": "Korean Patch"
}
```

Used keys:

- `app_id`
- `manifest_id`
- `branch` if needed later by your workflow

Behavior:

- If the current imported game already matches that manifest, DT Manager uses the copied `Game/<game_name>/` folder directly.
- Otherwise it uses `Files/GameVersions/<app_id>/<manifest_id>/`.
- If that cache is missing, DT Manager downloads the required version with DepotDownloader first.

## Patchers

DT Manager downloads patcher tools into `Patcher/`.

Current external tools:

- `GodotDelta`
- `DepotDownloader`

`xdelta` patch support is still handled by DT Manager, but xdelta is not downloaded from `Patcher.json`.

## Steam Login

App settings can store:

- Steam username
- Steam password

Steam login is used for:

- manifest version downloads through DepotDownloader
- Steam-protected version matching workflows

The login uses DepotDownloader and supports Steam Guard approval through the normal Steam mobile confirmation flow.

## Save Management

Each game can store its save path in settings.

Save slots are stored in:

`Files/GameSave/<game_name>/<slot_name>/`

Supported save actions:

- back up the current live save into a new slot
- restore a slot into the live save folder
- rename a slot
- delete a slot
- import a slot from a folder or ZIP
- export a slot to a folder or ZIP

New save slots use the default name format:

`slot_<index>`

## Thumbnails

Games and mods can both have thumbnails.

Stored paths:

- game: `Game/<game_name>/thumbnail.dm.png`
- mod: `Mod/<game_name>/<mod_name>/thumbnail.dm.png`

Preview behavior:

1. show the selected mod thumbnail if present
2. otherwise show the base game thumbnail

## Settings

DT Manager has separate settings tabs for:

- app settings
- game settings
- mod settings

Game settings include:

- rename
- Steam game path
- save path
- thumbnail
- Steam launch toggle

Mod settings include:

- rename
- thumbnail

## Notes

- Target platform is Windows only.
- The Godot project lives under `godot/`.
- The built runtime data is stored under `output/` when running from the editor.
