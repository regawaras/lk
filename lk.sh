#!/bin/sh
# LogKlerk (LK) v0.0.1 Stable - 100% POSIX-Compliant Core
# Minimalist, zero-dependency, atomic-locking daily logger.

LK_STATUS="experimental"; LK_VERSION="v0.0.2"

# 1. POSIX Absolute Path Resolution: Melacak lokasi asli lk.sh berada
LK_INSTALL_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"

# 2. Direktori Konfigurasi Pengguna (State & Preferences)
LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
LK_TAXONOMY_FILE="$LK_CONFIG_DIR/taxonomy.sh"

# Auto-Bootstrapping: Hanya mengurus pembuatan preferensi pengguna, BUKAN file sistem
if [ ! -d "$LK_CONFIG_DIR" ]; then
    mkdir -p "${LK_CONFIG_DIR}" "${HOME}/lk"
    printf 'LK_DIR="%s/lk"\nLK_TAIL_LINES="0"\nLK_DEFAULT_FORMAT=".md"\n' "$HOME" > "$LK_CONFIG_FILE"
fi

# Variabel Default (Akan ditimpa oleh lk.conf jika ada)
LK_DIR="${HOME}/lk"
LK_TAIL_LINES="0"
LK_DEFAULT_FORMAT=".md"
LK_BANNER="${LK_CONFIG_DIR}/assets/banner.txt"          

[ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"


if [ -d "$LK_MODULES_DIR" ]; then
    for mod_file in "$LK_MODULES_DIR"/*.sh; do
        [ -f "$mod_file" ] && . "$mod_file"
    done
fi

if [ -f "$LK_TAXONOMY_FILE" ]; then
    . "$LK_TAXONOMY_FILE"
fi

lk() {
    case "${1:-}" in
        "")
	if [ -f "$LK_BANNER" ]; then
            printf "\033[38;5;202m" # Memberikan warna aksen kuning pada banner
            cat "$LK_BANNER"
	fi
            printf " | LK Log Klerk %s %s | Github: https://github.com/regawaras/lk/\n" "$LK_STATUS" "$LK_VERSION"
            printf " | ''Just Type Enter Brutal'' - Log Klerking Creator \n" "$LK_STATUS" "$LK_VERSION"
            printf "\033[0m\n"
            return 0 ;;
        h|-h|help|-help|--help)
            if [ -f "${LK_MODULES_DIR}/lkh.sh" ]; then
                . "${LK_MODULES_DIR}/lkh.sh"
                _lk_show_help
            else
                printf "Error: Help module not found at %s\n" "${LK_MODULES_DIR}/lkh.sh" >&2
            fi
            return 0 ;;
        i|-i|interactive|lki)
            if [ -f "${LK_MODULES_DIR}/lki.sh" ]; then
                . "${LK_MODULES_DIR}/lki.sh"
                _lk_interactive
            else
                printf "Error: Interactive module not found at %s\n" "${LK_MODULES_DIR}/lki.sh" >&2
            fi
            return 0 ;;
        c|-c|conf|-conf|--config)
            printf "=== LK Configuration State ===\nCONFIG_FILE: %s\nLOGS_DIR: %s\nTAIL_LINES: %s\nFORMAT: %s\n" "$LK_CONFIG_FILE" "$LK_DIR" "$LK_TAIL_LINES" "$LK_DEFAULT_FORMAT"
            return 0 ;;
        e|-e|edit|-edit|--edit)
            set -- $(date '+%Y %m %d')
            lk_today="${LK_DIR}/$1/$1-$2/$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
            [ -f "$lk_today" ] && ${EDITOR:-${VISUAL:-vi}} "$lk_today" || printf "No log entries for today yet. Just type 'lk <text>' to brutal log.\n"
            return 0 ;;
        pwd|-pwd|--pwd)
            printf "%s\n" "$LK_DIR"; return 0 ;;
        v|-v|ver|-ver|version|-version|--version)
            [ "$#" -eq 1 ] && { printf "LK Log Klerk %s %s\n" "$LK_STATUS" "$LK_VERSION"; return 0; }
            shift; _lk_write "[${LK_STATUS}-${LK_VERSION}] >>" "$@" ;;
        -log-with-version|-lwv|lwv|-logver|--logver|-wv|-with-version|wv|log-with-version|log-w-version)
            shift; _lk_write "[${LK_STATUS}-${LK_VERSION}] >>" "$@" ;;
        *) _lk_write "" "$@" ;;
    esac
}

_lk_write() {
    ( 
        lk_cat="$1"; shift; lk_text="$*"
        [ -z "$lk_text" ] && { printf "Error: No Input.\n" >&2; exit 1; }

        set -- $(date '+%Y %m %d %H:00 %H:%M:%S')
        lk_tdir="${LK_DIR}/$1/$1-$2"
        lk_file="${lk_tdir}/$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
        lk_lock="${lk_file}.lock.d"

        [ -d "$lk_tdir" ] || mkdir -p "$lk_tdir"

        while ! mkdir "$lk_lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lk_lock" 2>/dev/null; exit 1' HUP INT QUIT TERM ABRT

        {
            [ -f "$lk_file" ] || printf -- "- [[%s-%s-%s]] - (Daily Summary)\n    created: [[%s-%s-%s]] - %s\n" "$1" "$2" "$3" "$1" "$2" "$3" "$5"
            grep -q "^    - $4" "$lk_file" 2>/dev/null || printf "    - %s - (Hourly Summary)\n" "$4"
            printf "        - %s - %s%s\n" "$5" "${lk_cat:+$lk_cat }" "$lk_text"
        } >> "$lk_file"

        rmdir "$lk_lock" 2>/dev/null
        
        printf "\033[32m✔\033[0m         - %s - %s%s\n" "$5" "${lk_cat:+$lk_cat }" "$lk_text"

        case "${LK_TAIL_LINES:-0}" in
            *[!0-9]*|"") ;; 
            0) ;;           
            *) 
                printf "\033[90m--- Tail: Last %s lines from %s ---\033[0m\n" "$LK_TAIL_LINES" "$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
                tail -n "$LK_TAIL_LINES" "$lk_file" 
                ;;
        esac
    )
}


if [ -f "$LK_CONFIG_FILE" ]; then
    . "$LK_CONFIG_FILE"
fi

if [ -d "$LK_MODULES_DIR" ]; then
    for mod_file in "$LK_MODULES_DIR"/*.sh; do
        [ -f "$mod_file" ] && . "$mod_file"
    done
fi

if [ -f "$LK_TAXONOMY_FILE" ]; then
    . "$LK_TAXONOMY_FILE"
fi

_lk_get_time() {
    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    CURRENT_HOUR=$(date +%H:00)
    FULL_TIMESTAMP=$(date +%H:%M:%S)
}

_lk_set_daily_summary() {
    ds_target_date="$1"
    shift
    ds_summary_text="$*"
    ds_year="${ds_target_date%%-*}"
    ds_month="${ds_target_date%-*}"
    ds_full_ts=$(date +%H:%M:%S)
    ds_target_dir="$LK_DIR/$ds_year/$ds_month"
    ds_filename="$ds_target_dir/$ds_target_date.md"
    
    mkdir -p "$ds_target_dir"
    if [ ! -f "$ds_filename" ]; then
        printf -- "- [[%s]] - %s\n" "$ds_target_date" "$ds_summary_text" >> "$ds_filename"
        printf "    created: [[%s]] - %s\n" "$ds_target_date" "$ds_full_ts" >> "$ds_filename"
    else
        ds_tmp_file=$(mktemp)
        sed "1c\\
- [[$ds_target_date]] - $ds_summary_text
" "$ds_filename" > "$ds_tmp_file" && mv "$ds_tmp_file" "$ds_filename"
    fi
    printf "\033[32mDaily Summary updated (%s): \033[38;2;0;255;255m%s\033[0m\n" "$ds_target_date" "$ds_summary_text"
}

_lk_set_summary() {
    # Menggunakan prefix 'lksv_' (LogKlerk Summary Variable) untuk simulasi scope
    lksv_time_input="$1"
    shift
    lksv_summary_text="$*"
    
    _lk_get_time
    lksv_target_dir="$LK_DIR/$YEAR/$MONTH"
    lksv_filename="$lksv_target_dir/$TODAY.md"
    lksv_indent="    "

    mkdir -p "$lksv_target_dir"
    if [ ! -f "$lksv_filename" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$lksv_filename"
        printf "%screated: [[%s]] - %s\n" "$lksv_indent" "$TODAY" "$FULL_TIMESTAMP" >> "$lksv_filename"
    fi

    # POSIX-compliant parsing: Memastikan hanya jam yang diproses
    case "$lksv_time_input" in
        *-*)
            lksv_start_raw=$(echo "$lksv_time_input" | cut -d'-' -f1 | tr -cd '0-9')
            lksv_end_raw=$(echo "$lksv_time_input" | cut -d'-' -f2 | tr -cd '0-9')
            ;;
        *)
            lksv_start_raw=$(echo "$lksv_time_input" | tr -cd '0-9')
            lksv_end_raw="$lksv_start_raw"
            ;;
    esac

    # Menghapus leading zero tanpa sed (lebih cepat di POSIX)
    lksv_start=$(echo "$lksv_start_raw" | sed 's/^0*//'); [ -z "$lksv_start" ] && lksv_start=0
    lksv_end=$(echo "$lksv_end_raw" | sed 's/^0*//'); [ -z "$lksv_end" ] && lksv_end=0

    lksv_tmp_file=$(mktemp)
    lksv_current="$lksv_start"
    while [ "$lksv_current" -le "$lksv_end" ]; do
        lksv_fmt=$(printf "%02d:00" "$lksv_current")
        lksv_header="${lksv_indent}- $lksv_fmt - $lksv_summary_text"
        
        # POSIX sed untuk menghapus baris lama sebelum update
        sed "3,\$ { /^${lksv_indent}- ${lksv_fmt} -/d; }" "$lksv_filename" > "$lksv_tmp_file" && mv "$lksv_tmp_file" "$lksv_filename"
        printf "%s\n" "$lksv_header" >> "$lksv_filename"
        lksv_current=$((lksv_current + 1))
    done

    # Sorting kronologis tanpa merusak struktur
    head -n 2 "$lksv_filename" > "$lksv_tmp_file"
    sed '1,2d' "$lksv_filename" | sort -b -k2,2 -u >> "$lksv_tmp_file"
    mv "$lksv_tmp_file" "$lksv_filename"
    
    printf "\033[32mSummary updated (%02d-%02d): \033[38;2;0;255;255m%s\033[0m\n" "$lksv_start" "$lksv_end" "$lksv_summary_text"
    lkcd
}
