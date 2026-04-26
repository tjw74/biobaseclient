#!/bin/bash
# PRE HOOK (sourced by joedwards32/cs2 entrypoint after SteamCMD install).
# Installs Metamod:Source 2.x (CS2) and CS2KZ into game/csgo when missing.

bb_cs2_patch_gameinfo() {
	local gi="${STEAMAPPDIR}/game/csgo/gameinfo.gi"
	if [[ ! -f "$gi" ]]; then
		echo "bb_cs2_server: gameinfo.gi not found yet; skip Metamod search path"
		return 0
	fi
	if grep -qF 'csgo/addons/metamod' "$gi"; then
		return 0
	fi
	echo "bb_cs2_server: patching gameinfo.gi for Metamod (SearchPaths)"
	# Typical CS2 layout: first Game + csgo entry in SearchPaths (tabs between fields).
	if sed -i '0,/\t\t\tGame\tcsgo/s//\t\t\tGame\tcsgo\/addons\/metamod\n&/' "$gi" 2>/dev/null; then
		return 0
	fi
	if sed -i '0,/\t\tGame\tcsgo/s//\t\tGame\tcsgo\/addons\/metamod\n&/' "$gi" 2>/dev/null; then
		return 0
	fi
	echo "bb_cs2_server: WARN: automatic gameinfo.gi patch failed; add 'Game    csgo/addons/metamod' to SearchPaths (see CS2 Metamod docs)"
}

CSGO="${STEAMAPPDIR}/game/csgo"
MM_TAR="/opt/bb-cs2-plugins/mmsource-2.0.0-git1396-linux.tar.gz"
KZ_TAR="/opt/bb-cs2-plugins/cs2kz-linux-master.tar.gz"

# Vanilla install has no addons/ until we create it; require csgo root instead.
if [[ ! -f "${CSGO}/gameinfo.gi" ]]; then
	echo "bb_cs2_server: ${CSGO}/gameinfo.gi missing — CS2 not installed yet, skip KZ layer this start"
	return 0
fi

if [[ ! -f "${CSGO}/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ]]; then
	echo "bb_cs2_server: extracting Metamod 2.0 (CS2)"
	tar -xzf "${MM_TAR}" -C "${CSGO}"
fi

if [[ ! -f "${CSGO}/addons/cs2kz/bin/linuxsteamrt64/cs2kz.so" ]]; then
	echo "bb_cs2_server: extracting CS2KZ (KZGlobalTeam release)"
	tar -xzf "${KZ_TAR}" -C "${CSGO}"
fi

bb_cs2_patch_gameinfo
echo "bb_cs2_server: pre-hook done (Metamod + CS2KZ)"
