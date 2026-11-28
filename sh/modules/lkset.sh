#!/bin/sh
# Module: lkset (LogKlerk Taxonomy Generator - Standalone & Safe I/O)

lkset() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    
    # [FIXED]: Menghargai LK_CONFIG_DIR dari environment (seperti /opt/lk/...) jika ada,
    # jika kosong, baru fallback ke struktur default di .config
    LK_CONFIG_DIR="${LK_CONFIG_DIR:-${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"

    # Load Config to get LK_DIR and LK_DEFAULT_FORMAT
    LK_DIR="${LK_DIR:-${HOME}/.local/share/logklerk}"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    
    # User-defined tail lines, defaulting to 5
    LKSET_TAIL_LINES="${LKSET_TAIL_LINES:-5}"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')        # Success Checkmark
    LK_PURPLE=$(printf '\033[38;2;170;100;255m')    # Alias Color
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')      # Tag Color
    LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Fallback Text Color
    LK_GREY=$(printf '\033[90m')                    # Boilerplate / Dim Text
    LK_AMBER=$(printf '\033[38;2;255;204;0m')       # Tail Header
    LK_HEADER_ORG=$(printf '\033[38;2;255;117;0m')  # Header Separator
    LK_RED=$(printf '\033[31m')                     # Strict Syntax Error Red
    # =========================================================================

    # --- Tail Syntax Highlighter Engine ---
    _lkset_tail_colorizer() {
        awk -v reset="$LK_RESET" -v purp="$LK_PURPLE" -v org="$LK_ORANGE" -v grey="$LK_GREY" -v cyan="$LK_CYAN" '
        {
            # Pattern matcher untuk format: alias_name() { lk_context "[[Tag]] >>" "$@"; }
            if (match($0, /^[a-zA-Z0-9_]+/)) {
                alias_name = substr($0, RSTART, RLENGTH)
                rest_of_line = substr($0, RLENGTH + 1)
                
                # Cari posisi string Tag di dalam quote
                if (match(rest_of_line, /"\[\[.*\]\] >>"/)) {
                    pre_tag = substr(rest_of_line, 1, RSTART - 1)
                    tag_part = substr(rest_of_line, RSTART, RLENGTH)
                    post_tag = substr(rest_of_line, RSTART + RLENGTH)
                    
                    # Print dengan kombinasi warna (Ungu -> Abu -> Oranye -> Abu)
                    print "    " purp alias_name grey pre_tag org tag_part grey post_tag reset
                    next
                }
            }
            # Fallback jika ada baris kode yang tidak sesuai pola
            print "    " cyan $0 reset
        }'
    }

    # --- 2. Strict Input Validation ---
    if [ -z "$1" ] || [ "${1#*=}" = "$1" ]; then
        printf "%s[Syntax Error]%s Format must be alias=\"[[Tag]]\"\n" "$LK_RED" "$LK_RESET"
        printf "Example: lkset wbl=\"[[Website Links]]\"\n"
        return 1
    fi

    lks_alias="${1%%=*}"
    lks_tag_raw="${1#*=}"
    
    # Validasi karakter Shell Function (hanya boleh Alphanumeric & Underscore)
    if echo "$lks_alias" | grep -q '[^a-zA-Z0-9_]'; then
        printf "%s[Error]%s Invalid alias name: '%s'. Use alphanumeric and underscores only.\n" "$LK_RED" "$LK_RESET" "$lks_alias"
        return 1
    fi

    # Menghapus kutip (single/double) dengan aman
    lks_tag=$(echo "$lks_tag_raw" | sed "s/^['\"]//; s/['\"]$//")

    if [ -z "$lks_tag" ]; then
        printf "%s[Error]%s Tag cannot be empty.\n" "$LK_RED" "$LK_RESET"
        return 1
    fi

    # --- 3. Directory Management & I/O Protection ---
    lks_dir="${LK_TAXONOMY_FILE%/*}"
    mkdir -p "$lks_dir" 2>/dev/null
    [ ! -f "$LK_TAXONOMY_FILE" ] && touch "$LK_TAXONOMY_FILE" 2>/dev/null

    if [ ! -w "$LK_TAXONOMY_FILE" ]; then
        printf "%s[Error]%s Permission denied on context.sh.\n" "$LK_RED" "$LK_RESET"
        printf "Run outside LKI: %ssudo chown \$USER:\$USER %s%s\n" "$LK_AMBER" "$LK_TAXONOMY_FILE" "$LK_RESET"
        return 1
    fi

    # --- 4. Duplication Protection ---
    if grep -q "^${lks_alias}[[:space:]]*()[[:space:]]*{" "$LK_TAXONOMY_FILE" 2>/dev/null; then
        printf "\033[33m[Warning]\033[0m %sAlias '%s' is already registered in context.sh. Aborting.%s\n" "$LK_RED" "$lks_alias" "$LK_RESET"
        return 0
    fi
    
    # --- 5. Atomic Write to context.sh ---
    lks_new_func="${lks_alias}() { lk_context \"${lks_tag} >>\" \"\$@\"; }"
    
    printf "%s\n" "$lks_new_func" >> "$LK_TAXONOMY_FILE"

    # --- 6. Visual Feedback ---
    printf "%s✔%s Taxonomy Context Added\n" "$LK_LIME" "$LK_RESET"
    printf "    Alias    : %s%s%s\n" "$LK_PURPLE" "$lks_alias" "$LK_RESET"
    printf "    Tag      : %s%s >>%s\n" "$LK_ORANGE" "$lks_tag" "$LK_RESET"
    printf "    Location : %s%s%s\n" "$LK_GREY" "$LK_TAXONOMY_FILE" "$LK_RESET"
    
    # --- 7. Beautified Code Tail Preview ---
    printf "\n%s--- Tail: Last %s lines from %s ---%s\n" "$LK_AMBER" "$LKSET_TAIL_LINES" "$(basename "$LK_TAXONOMY_FILE")" "$LK_RESET"
    
    tail -n "$LKSET_TAIL_LINES" "$LK_TAXONOMY_FILE" | _lkset_tail_colorizer
    
    printf "%s------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
}
