#!/usr/bin/env bash
#
# One-click chaudloader installer for Steam Deck / SteamOS (and desktop Linux).
#
# What it does:
#   1. Downloads the latest chaudloader Linux release from GitHub.
#   2. Finds your Mega Man Battle Network Legacy Collection install(s)
#      (Vol.1 = appid 1798010, Vol.2 = appid 1798020) across every Steam
#      library folder, including SD cards and a Flatpak Steam install.
#   3. Copies the loader DLLs (dxgi.dll, chaudloader.dll, lua54.dll) into the
#      game's exe/ folder, removes the old bnlc_mod_loader.dll, and creates the
#      mods/ folder.
#
# chaudloader's dxgi.dll proxy is loaded automatically by Proton (the local DLL
# wins over the system one, exactly like on Windows), so NO Steam launch option
# is required. Just run this, then launch the game.
#
# Usage:
#   bash install.sh              # normal, interactive-friendly output
#   CHAUDLOADER_REPO=owner/repo bash install.sh   # pull binaries from a fork
#
set -euo pipefail

# Repo to pull the chaudloader *binary release* from. The fork has no releases
# of its own, so default to upstream, which always has a working Linux build.
REPO="${CHAUDLOADER_REPO:-RockmanEXEZone/chaudloader}"

# App IDs -> friendly name.
declare -A GAMES=( [1798010]="Vol. 1" [1798020]="Vol. 2" )

FILES_TO_COPY=(dxgi.dll chaudloader.dll lua54.dll)
FILES_TO_DELETE=(bnlc_mod_loader.dll)

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

trap 'st=$?; [ $st -ne 0 ] && printf "\n\033[1;31mInstallation failed (exit %s).\033[0m\n" "$st"; exit $st' EXIT

cat <<'BANNER'
        %%%%%%%%%%%%%%%%%
     %%%%%  *********  %%%%%
   %%%% *************     %%%%
  %%% ***************       %%%
 %%% *************** ******* %%%    chaudloader
 %%% ************ ********** %%%    Steam Deck installer
 %%% ******* *************** %%%
   %%%%     ************* %%%%
     %%%%%  *********  %%%%%
        %%%%%%%%%%%%%%%%%
BANNER
echo

command -v curl >/dev/null 2>&1 || die "curl is required but not found."
command -v tar  >/dev/null 2>&1 || die "tar is required but not found."

# ---------------------------------------------------------------------------
# 1. Download + extract the latest Linux release.
# ---------------------------------------------------------------------------
workdir="$(mktemp -d)"
trap 'st=$?; rm -rf "$workdir"; [ $st -ne 0 ] && printf "\n\033[1;31mInstallation failed (exit %s).\033[0m\n" "$st"; exit $st' EXIT
dist="$workdir/dist"
mkdir -p "$dist"

say "Looking up the latest chaudloader release from $REPO ..."
api="https://api.github.com/repos/$REPO/releases/latest"
# Grab the browser_download_url of the *linux* .tar.bz2 asset (no jq dependency).
asset_url="$(curl -fsSL "$api" \
  | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*linux[^"]*\.tar\.bz2"' \
  | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')"
tag="$(curl -fsSL "$api" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')"
[ -n "$asset_url" ] || die "Could not find a Linux release asset on $REPO. Check your internet connection."

say "Downloading chaudloader $tag ..."
curl -fL# "$asset_url" -o "$workdir/chaudloader.tar.bz2"
tar -xjf "$workdir/chaudloader.tar.bz2" -C "$dist"

for f in "${FILES_TO_COPY[@]}"; do
  [ -f "$dist/$f" ] || die "Release archive is missing $f (unexpected layout)."
done
ok "Downloaded and extracted chaudloader $tag."

# ---------------------------------------------------------------------------
# 2. Locate every Steam library folder.
# ---------------------------------------------------------------------------
collect_libraries() {
  local roots=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"   # Flatpak Steam
  )
  local r vdf p
  for r in "${roots[@]}"; do
    [ -d "$r/steamapps" ] || continue
    printf '%s\n' "$r/steamapps"
    vdf="$r/steamapps/libraryfolders.vdf"
    [ -f "$vdf" ] || continue
    # Additional library folders (extra drives, SD cards) are listed as "path".
    grep -oE '"path"[[:space:]]+"[^"]+"' "$vdf" 2>/dev/null \
      | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/' \
      | while IFS= read -r p; do
          p="${p//\\\\/\/}"   # normalise any escaped backslashes
          [ -d "$p/steamapps" ] && printf '%s\n' "$p/steamapps"
        done
  done | awk '!seen[$0]++'
}

mapfile -t LIBS < <(collect_libraries)
[ "${#LIBS[@]}" -gt 0 ] || die "No Steam library was found. Is Steam installed?"

# ---------------------------------------------------------------------------
# 3. Find each game and install into <game>/exe/.
# ---------------------------------------------------------------------------
installed=0
for appid in "${!GAMES[@]}"; do
  name="${GAMES[$appid]}"
  for steamapps in "${LIBS[@]}"; do
    acf="$steamapps/appmanifest_$appid.acf"
    [ -f "$acf" ] || continue

    installdir="$(grep -oE '"installdir"[[:space:]]+"[^"]+"' "$acf" \
      | head -n1 | sed -E 's/.*"installdir"[[:space:]]+"([^"]+)".*/\1/')"
    [ -n "$installdir" ] || { warn "$name: appmanifest found but no installdir; skipping."; continue; }

    gamedir="$steamapps/common/$installdir"
    exedir="$gamedir/exe"
    if [ ! -d "$exedir" ]; then
      # Some layouts keep the exe at the game root.
      if ls "$gamedir"/MMBN_LC*.exe >/dev/null 2>&1; then
        exedir="$gamedir"
      else
        warn "$name: found manifest but no exe/ folder at $gamedir; skipping."
        continue
      fi
    fi

    say "Installing to $name  ($exedir)"
    for f in "${FILES_TO_DELETE[@]}"; do
      if [ -f "$exedir/$f" ]; then rm -f "$exedir/$f" && ok "removed old $f"; fi
    done
    for f in "${FILES_TO_COPY[@]}"; do
      cp -f "$dist/$f" "$exedir/$f" && ok "copied $f"
    done
    mkdir -p "$exedir/mods" && ok "ensured mods/ folder"
    installed=$((installed + 1))
  done
done

echo
if [ "$installed" -eq 0 ]; then
  warn "No Mega Man Battle Network Legacy Collection install was detected."
  echo  "  If the game is installed, copy these files manually into the folder"
  echo  "  containing MMBN_LC1.exe / MMBN_LC2.exe (usually .../<game>/exe/):"
  for f in "${FILES_TO_COPY[@]}"; do echo "    - $dist/$f"; done
  die "Nothing was installed."
fi

ok "chaudloader installed to $installed game folder(s)."
echo
say "Done! Next steps:"
echo "  1. Launch the game normally from Steam (no launch options needed)."
echo "  2. Put mods in the game's exe/mods/ folder — they load alphabetically."
echo
