# chaudloader — one-click Steam Deck installer

Installs [chaudloader](https://github.com/RockmanEXEZone/chaudloader) (mod loader
for **Mega Man Battle Network Legacy Collection**) on a Steam Deck / SteamOS with
no manual file copying.

## Easiest: the one-click desktop launcher

1. Switch the Deck to **Desktop Mode**.
2. Download **[`Install-chaudloader.desktop`](Install-chaudloader.desktop)**
   (in Konsole: `curl -fLO https://raw.githubusercontent.com/ZeldoKavira/chaudloader/main/steamdeck/Install-chaudloader.desktop`).
3. Double-click it. A terminal opens, downloads chaudloader, and installs it into
   every detected game volume.

## Or run the script directly

Open **Konsole** and run:

```bash
curl -fsSL https://raw.githubusercontent.com/ZeldoKavira/chaudloader/main/steamdeck/install.sh | bash
```

## What it does

- Downloads the latest chaudloader **Linux** release from GitHub.
- Finds every Steam library (internal, SD card, and Flatpak Steam) and locates
  **Vol. 1** (appid `1798010`) and **Vol. 2** (appid `1798020`) via their
  `appmanifest_*.acf`.
- Into each game's `exe/` folder it removes the old `bnlc_mod_loader.dll`, copies
  `dxgi.dll`, `chaudloader.dll`, and `lua54.dll`, and creates the `mods/` folder.

**No Steam launch options are needed.** Proton loads the game-local `dxgi.dll`
ahead of the system one, so the loader activates automatically. Just launch the
game normally and drop mods into `exe/mods/` (loaded alphabetically).

## Notes

- The script pulls chaudloader binaries from upstream `RockmanEXEZone/chaudloader`
  by default (this fork ships no binary releases). To use a different source:
  ```bash
  CHAUDLOADER_REPO=YourName/chaudloader bash install.sh
  ```
- To uninstall, delete `dxgi.dll`, `chaudloader.dll`, and `lua54.dll` from each
  game's `exe/` folder.
