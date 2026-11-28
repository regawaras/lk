#!/bin/sh
# Module: lksnap (LogKlerk Snapshot Backup)
# Updated to v0.0.7: Incremental Hard-Link Archival (Zero-Waste Duplication)

lksnap() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.7}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    # Defaults
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_SNAP_DIR="${HOME}/snapshots/lk"
    
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"
    LK_SNAP_DIR="${LK_SNAP_DIR%/}"

    # =========================================================================
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_PURPLE='\033[38;2;170;100;255m'
    LK_RED='\033[31m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_AMBER='\033[38;2;255;200;0m'
    LK_MAGENTA='\033[38;2;255;100;255m'
    # =========================================================================

    # --- 2. Dynamic Naming Parsing ---
    SNAP_SUFFIX=""
    if [ $# -gt 0 ]; then
        old_ifs="$IFS"; IFS="_"; joined_args="$*"; IFS="$old_ifs"
        clean_args=$(printf "%s" "$joined_args" | tr ' ' '_')
        SNAP_SUFFIX="-$clean_args"
    fi

    # --- 3. Pre-Flight Checks ---
    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Fatal]%b Source Vault (%s) not found.\n" "$LK_RED" "$LK_RESET" "$LK_DIR"
        return 1
    fi

    mkdir -p "$LK_SNAP_DIR" 2>/dev/null
    if [ ! -d "$LK_SNAP_DIR" ]; then
        printf "%b[Fatal]%b Cannot create snapshot directory at %s.\n" "$LK_RED" "$LK_RESET" "$LK_SNAP_DIR"
        return 1
    fi

    # --- 4. Chronological Snapshot Generation ---
    TS=$(date +%Y%m%d-%H%M%S)
    SNAP_TARGET="${LK_SNAP_DIR}/lk-snapshot-${TS}${SNAP_SUFFIX}"

    printf "%b--- Initializing LogKlerk Archival ---%b\n" "$LK_CYAN" "$LK_RESET"
    printf " Source : %b%s%b\n" "$LK_PURPLE" "$LK_DIR" "$LK_RESET"
    printf " Target : %b%s%b\n" "$LK_PURPLE" "$SNAP_TARGET" "$LK_RESET"

    # --- 5. The Surgical Copy (Incremental Hard-Link via rsync) ---
    # Mencari snapshot terakhir berdasarkan urutan nama direktori
    LATEST_SNAP=$(ls -d "$LK_SNAP_DIR"/lk-snapshot-* 2>/dev/null | sort | tail -n 1)
    
    if command -v rsync >/dev/null 2>&1 && [ -n "$LATEST_SNAP" ]; then
        printf " Method : %bIncremental Hard-Link%b (Referencing %s)\n" "$LK_MAGENTA" "$LK_RESET" "$(basename "$LATEST_SNAP")"
        # Melakukan sinkronisasi. File yang tidak berubah akan menjadi Hard-Link ke LATEST_SNAP
        rsync -a --link-dest="$LATEST_SNAP" "$LK_DIR/" "$SNAP_TARGET/"
        COPY_STATUS=$?
    else
        printf " Method : %bFull Clone%b (rsync fallback or first snapshot)\n" "$LK_AMBER" "$LK_RESET"
        cp -a "$LK_DIR" "$SNAP_TARGET"
        COPY_STATUS=$?
    fi

    if [ $COPY_STATUS -eq 0 ]; then
        # Kalkulasi True Size (Byte Size)
        true_bytes=$(find "$SNAP_TARGET" -type f -exec ls -l {} + 2>/dev/null | LC_ALL=C awk '{s+=$5} END {print s+0}')
        SNAP_SIZE=$(LC_ALL=C awk -v b="$true_bytes" 'BEGIN {
            if (b >= 1048576) printf "%.2f MiB", b / 1048576
            else if (b >= 1024) printf "%.2f KiB", b / 1024
            else printf "%d B", b
        }')

        printf "%b✔%b Snapshot successful! [ Logical Size: %b%s%b ]\n" "$LK_LIME" "$LK_RESET" "$LK_AMBER" "$SNAP_SIZE" "$LK_RESET"
        printf " %bHint: To rollback, run: rm -rf %s/* && cp -a %s/* %s/%b\n" "$LK_GREY" "$LK_DIR" "$SNAP_TARGET" "$LK_DIR" "$LK_RESET"
    else
        printf "%b[Error]%b Snapshot failed during filesystem copy operation.\n" "$LK_RED" "$LK_RESET"
        return 1
    fi
}
