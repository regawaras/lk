#!/bin/sh
# LogKlerk (LK) v0.0.1 Stable - 100% POSIX-Compliant Core
# Minimalist, zero-dependency, atomic-locking daily logger.

LK_STATUS="stable"; LK_VERSION="v0.0.1"

# 1. POSIX Absolute Path Resolution: Melacak lokasi asli lk.sh berada
LK_INSTALL_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"

# 2. Direktori Konfigurasi Pengguna (State & Preferences)
LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"

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

lk() {
    case "${1:-}" in
        "")
	if [ -f "$LK_BANNER" ]; then
            printf "\033[38;5;220m" # Memberikan warna aksen kuning pada banner
            cat "$LK_BANNER"
	fi
            printf " | LK Log Klerk %s %s | Github: https://github.com/regawaras/lk/\n" "$LK_STATUS" "$LK_VERSION"
            printf " | ''Just Type Enter Brutal'' - Log Klerking Creator \n" "$LK_STATUS" "$LK_VERSION"
            printf "\033[0m\n"
            return 0 ;;
        h|-h|help|-help|--help)
            # Dynamic Sourcing langsung dari repository clone
            if [ -f "${LK_MODULES_DIR}/lkh.sh" ]; then
                . "${LK_MODULES_DIR}/lkh.sh"
                _lk_show_help
            else
                printf "Error: Help module not found at %s\n" "${LK_MODULES_DIR}/lkh.sh" >&2
            fi
            return 0 ;;
        i|-i|interactive|lki)
            # Dynamic Sourcing untuk Interactive Mode
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
