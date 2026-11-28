#!/bin/sh
# Module: lkconf (LogKlerk Configuration Manager - Dynamic Upsert & Contextual View)

lkconf() {
    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')        # Success Checkmark
    LK_PURPLE=$(printf '\033[38;2;170;100;255m')    # Key Color
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')      # Value Color
    LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Info Color / Target Indicator
    LK_GREY=$(printf '\033[90m')                    # Dim Text / Comments
    LK_AMBER=$(printf '\033[38;2;255;204;0m')       # Tail Header
    LK_HEADER_ORG=$(printf '\033[38;2;255;117;0m')  # Header Separator
    LK_RED=$(printf '\033[31m')                     # Strict Syntax Error Red
    # =========================================================================

    # --- Contextual Syntax Highlighter Engine ---
    _lkconf_tail_colorizer() {
        local target_key="$1"
        awk -v reset="$LK_RESET" -v purp="$LK_PURPLE" -v org="$LK_ORANGE" -v grey="$LK_GREY" -v cyan="$LK_CYAN" -v target="$target_key" '
        {
            is_target = 0
            
            # Deteksi apakah baris ini adalah baris target yang baru diubah
            if (match($0, /^[[:space:]]*[a-zA-Z0-9_]+=/)) {
                key = substr($0, 1, RLENGTH - 1)
                sub(/^[[:space:]]*/, "", key) # Hapus spasi di depan untuk pencocokan akurat
                if (key == target) {
                    is_target = 1
                }
            }

            # Tambahkan panah indikator jika ini baris target
            prefix = is_target ? "  " cyan "> " reset : "    "

            # Highlight format KEY="VALUE"
            if (match($0, /^[[:space:]]*[a-zA-Z0-9_]+=/)) {
                raw_key = substr($0, 1, RLENGTH - 1)
                val = substr($0, RLENGTH + 1)
                print prefix purp raw_key grey "=" org val reset
            } 
            # Grey out untuk baris komentar atau kosong
            else {
                print prefix grey $0 reset
            }
        }'
    }

    # --- 1. Environment & Smart Fallback Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_GLOBAL_CONFIG="${HOME}/.config/lk/lk.conf"
    
    # Priority 1: Versioned Config. Priority 2: Global Config. Priority 3: Create new.
    if [ -f "${LK_CONFIG_DIR}/lk.conf" ]; then
        LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    elif [ -f "$LK_GLOBAL_CONFIG" ]; then
        LK_CONFIG_FILE="$LK_GLOBAL_CONFIG"
    else
        mkdir -p "$LK_CONFIG_DIR" 2>/dev/null
        LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
        touch "$LK_CONFIG_FILE" 2>/dev/null
    fi

    # Read user preference for tail lines, default to 5
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LKSET_TAIL_LINES="${LKSET_TAIL_LINES:-5}"

    # --- 2. Strict Input Validation ---
    lkcf_raw="$*"
    if [ -z "$lkcf_raw" ] || [ "${lkcf_raw#*=}" = "$lkcf_raw" ]; then
        printf "%s[Syntax Error]%s Format must be KEY=\"VALUE\"\n" "$LK_RED" "$LK_RESET"
        printf "Example: lkconf LK_TAIL_LINES=\"5\"\n"
        printf "Example: lkconf LK_USER=\"Rega Waras\"\n"
        return 1
    fi

    # --- 3. Key & Value Extraction ---
    lkcf_key="${lkcf_raw%%=*}"
    lkcf_val_raw="${lkcf_raw#*=}"
    
    if echo "$lkcf_key" | grep -q '[^a-zA-Z0-9_]'; then
        printf "%s[Error]%s Invalid key name: '%s'. Use alphanumeric and underscores only.\n" "$LK_RED" "$LK_RESET" "$lkcf_key"
        return 1
    fi

    # Clean quotes safely and re-wrap explicitly
    lkcf_val=$(echo "$lkcf_val_raw" | sed "s/^['\"]//; s/['\"]$//")
    lkcf_entry="${lkcf_key}=\"${lkcf_val}\""

    # --- 4. Atomic Upsert Logic (Update or Insert) ---
    if [ ! -w "$LK_CONFIG_FILE" ]; then
        printf "%s[Error]%s Permission denied on %s.\n" "$LK_RED" "$LK_RESET" "$LK_CONFIG_FILE"
        return 1
    fi

    lkcf_tmp=$(mktemp)
    if grep -q "^[[:space:]]*${lkcf_key}=" "$LK_CONFIG_FILE" 2>/dev/null; then
        sed "s|^[[:space:]]*${lkcf_key}=.*|${lkcf_entry}|" "$LK_CONFIG_FILE" > "$lkcf_tmp" && mv "$lkcf_tmp" "$LK_CONFIG_FILE"
        lkcf_action="Updated"
        lkcf_color="$LK_CYAN"
    else
        printf "%s\n" "$lkcf_entry" >> "$LK_CONFIG_FILE"
        lkcf_action="Added"
        lkcf_color="$LK_LIME"
    fi

    # --- 5. Visual Feedback ---
    printf "%s✔%s Configuration %s%s%s\n" "$LK_LIME" "$LK_RESET" "$lkcf_color" "$lkcf_action" "$LK_RESET"
    printf "    Key      : %s%s%s\n" "$LK_PURPLE" "$lkcf_key" "$LK_RESET"
    printf "    Value    : %s\"%s\"%s\n" "$LK_ORANGE" "$lkcf_val" "$LK_RESET"
    printf "    Location : %s%s%s\n" "$LK_GREY" "$LK_CONFIG_FILE" "$LK_RESET"
    
    # --- 6. Contextual Preview (Sliding Window Math) ---
    # Temukan baris di mana key tersebut berada sekarang
    target_ln=$(grep -n "^[[:space:]]*${lkcf_key}=" "$LK_CONFIG_FILE" | cut -d: -f1 | head -n1)
    [ -z "$target_ln" ] && target_ln=1 # Fallback aman

    total_ln=$(wc -l < "$LK_CONFIG_FILE" | tr -d ' ')
    half_context=$(( LKSET_TAIL_LINES / 2 ))
    
    start_ln=$(( target_ln - half_context ))
    [ "$start_ln" -lt 1 ] && start_ln=1

    end_ln=$(( start_ln + LKSET_TAIL_LINES - 1 ))
    [ "$end_ln" -gt "$total_ln" ] && end_ln="$total_ln"

    # Koreksi jendela jika menabrak dasar file (geser ke atas agar jumlah baris tetap utuh)
    actual_lines=$(( end_ln - start_ln + 1 ))
    if [ "$actual_lines" -lt "$LKSET_TAIL_LINES" ]; then
        start_ln=$(( end_ln - LKSET_TAIL_LINES + 1 ))
        [ "$start_ln" -lt 1 ] && start_ln=1
    fi

    printf "\n%s--- Context: Lines %s-%s from %s ---%s\n" "$LK_AMBER" "$start_ln" "$end_ln" "$(basename "$LK_CONFIG_FILE")" "$LK_RESET"
    
    # Ekstrak baris spesifik dan beri highlight
    sed -n "${start_ln},${end_ln}p" "$LK_CONFIG_FILE" | _lkconf_tail_colorizer "$lkcf_key"
    
    printf "%s------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
}
