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
SQL_MM_TAR="/opt/bb-cs2-plugins/sql_mm-linux.tar.gz"

# When SteamCMD finishes a first-time install in the same container lifetime, this hook may have
# run once before gameinfo.gi existed (so plugins were skipped). Every later invocation should
# install anything still missing.
if [[ ! -f "${CSGO}/gameinfo.gi" ]]; then
	echo "bb_cs2_server: ${CSGO}/gameinfo.gi missing — CS2 not installed yet, skip KZ layer this start"
else

if [[ ! -f "${CSGO}/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ]]; then
	echo "bb_cs2_server: extracting Metamod 2.0 (CS2)"
	tar -xzf "${MM_TAR}" -C "${CSGO}"
fi

if [[ ! -f "${CSGO}/addons/sql_mm/bin/linuxsteamrt64/sql_mm.so" ]] && [[ -f "${SQL_MM_TAR}" ]]; then
	echo "bb_cs2_server: extracting SQL_MM (CS2KZ local SQLite / MySQL)"
	# Release asset is a POSIX tar (not gzip) despite .tar.gz name.
	tar -xf "${SQL_MM_TAR}" -C "${CSGO}"
fi

if [[ ! -f "${CSGO}/addons/cs2kz/bin/linuxsteamrt64/cs2kz.so" ]]; then
	echo "bb_cs2_server: extracting CS2KZ (KZGlobalTeam release)"
	tar -xzf "${KZ_TAR}" -C "${CSGO}"
fi

bb_cs2_patch_gameinfo

# Always overlay CS2KZ server config so default mode stays Vanilla (VNL); must run after tarball extract.
# https://docs.cs2kz.org/systems/modes
BIOBASE_KZCFG="/opt/bb-cs2-plugins/cs2kz-server-config.biobase.txt"
KZCFG_DEST="${CSGO}/cfg/cs2kz-server-config.txt"
if [[ -f "${BIOBASE_KZCFG}" ]]; then
	mkdir -p "${CSGO}/cfg"
	cp -f "${BIOBASE_KZCFG}" "${KZCFG_DEST}"
	echo "bb_cs2_server: applied Biobase CS2KZ config -> ${KZCFG_DEST} (defaultMode Vanilla)"
else
	echo "bb_cs2_server: WARN: missing ${BIOBASE_KZCFG}; CS2KZ uses stock config from tarball"
fi

# CS2KZ creates this dir mode 750; bb_data_collection (non-steam user) needs +rx to read SQLite for ingest.
mkdir -p "${CSGO}/addons/cs2kz/data"
chmod a+rX "${CSGO}/addons/cs2kz/data" 2>/dev/null || true
find "${CSGO}/addons/cs2kz/data" -maxdepth 1 -type f -exec chmod a+r {} \; 2>/dev/null || true

echo "bb_cs2_server: pre-hook done (Metamod + CS2KZ)"
fi
