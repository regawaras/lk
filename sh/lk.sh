#!/bin/sh
# LogKlerk (LK) v0.0.3 Experimental - 100% POSIX-Compliant Core
# Minimalist, zero-dependency, atomic-locking daily logger.

LK_STATUS="experimental"; LK_VERSION="v0.0.3"

# 1. POSIX Absolute Path Resolution
LK_INSTALL_DIR=$(cd "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"

# 2. User Configuration Directory
LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
LK_TAXONOMY_FILE="$LK_CONFIG_DIR/modules/context.sh" # Updated path to match previous modularity

# Auto-Bootstrapping
if [ ! -d "$LK_CONFIG_DIR" ]; then
    mkdir -p "${LK_CONFIG_DIR}" "${HOME}/lk"
    printf 'LK_DIR="%s/lk"\nLK_TAIL_LINES="10"\nLK_DEFAULT_FORMAT=".md"\n' "$HOME" > "$LK_CONFIG_FILE"
fi

# Default Variables
LK_DIR="${HOME}/lk"
LK_TAIL_LINES="10"
LK_DEFAULT_FORMAT=".md"
LK_BANNER="${LK_CONFIG_DIR}/assets/banner.txt"          

[ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

# =========================================================================
# COLOR PALETTE CONFIGURATION (Universal Core)
# =========================================================================
LK_RESET=$(printf '\033[0m')
LK_AMBER=$(printf '\033[38;2;255;255;0m')       # Daily Summary Date
LK_LIME=$(printf '\033[38;2;100;255;0m')        # Timestamps
LK_GREY=$(printf '\033[38;2;150;150;150m')      # True Color Bright Grey (Fixed for Wayland)
LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Hourly Summary Time
LK_ORANGE=$(printf '\033[38;2;225;102;0m')      # Custom Orange (Taxonomy & Banner)
LK_DIM=$(printf '\033[2m')                      # Dim/Faded (Tails Line)
LK_GREEN=$(printf '\033[32m')                   # Success Checkmarks
# =========================================================================

# Load all available modules
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
        # --- Default Behavior: Launch LKI or Show Fallback Banner ---
        "")
            if type lki >/dev/null 2>&1; then
                lki ""
                return $?
            else
                curr_hr=$(date +%H:00)
                if [ -f "$LK_BANNER" ]; then
                    printf "%s" "$LK_ORANGE"
                    cat "$LK_BANNER"
                fi
                printf "%s | LK LogKlerk %s %s | Github: https://github.com/regawaras/lk/ |\n" "$LK_ORANGE" "$LK_STATUS" "$LK_VERSION"
                printf " | ''Just Open Terminal, Type, Enter, Forget Brutal'' -LK LogKlerking Creator |\n"
                printf "${LK_GREY} | -------------- LK Interactive Mode (Hybrid Shell & Context) -------------- |\n"
                printf " | Hour Block: ${LK_CYAN}%s${LK_GREY} | Source: %s |\n${LK_RESET}" "$curr_hr" "$LK_CONFIG_DIR"
                return 0
            fi
            ;;
        
        h|-h|help|-help|--help)
            if type lkvh >/dev/null 2>&1; then
                lkvh
            elif [ -f "${LK_MODULES_DIR}/lkh.sh" ]; then
                . "${LK_MODULES_DIR}/lkh.sh"
                _lk_show_help
            else
                printf "\033[31m[Error]\033[0m Help module not found.\n" >&2
            fi
            return 0 ;;
            
        i|-i|interactive|lki)
            if type lki >/dev/null 2>&1; then
                lki ""
            else
                printf "\033[31m[Error]\033[0m Interactive module (lki) not found.\n" >&2
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
            [ "$#" -eq 1 ] && { printf "LK LogKlerk %s %s\n" "$LK_STATUS" "$LK_VERSION"; return 0; }
            shift; _lk_write "[[${LK_STATUS}-${LK_VERSION}]] >>" "$@" ;;
            
        -log-with-version|-lwv|lwv|-logver|--logver|-wv|-with-version|wv|log-with-version|log-w-version)
            shift; _lk_write "[[${LK_STATUS}-${LK_VERSION}]] >>" "$@" ;;
            
        *) _lk_write "" "$@" ;;
    esac
}

_lk_write() {
    ( 
        lk_cat="$1"; shift; lk_text="$*"
        [ -z "$lk_text" ] && { printf "\033[31m[Error]\033[0m No Input.\n" >&2; exit 1; }

        set -- $(date '+%Y %m %d %H:00 %H:%M:%S')
        lk_tdir="${LK_DIR}/$1/$1-$2"
        lk_file="${lk_tdir}/$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
        lk_lock="${lk_file}.lock.d"

        [ -d "$lk_tdir" ] || mkdir -p "$lk_tdir"

        # Atomic Locking Mechanism
        while ! mkdir "$lk_lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lk_lock" 2>/dev/null; exit 1' HUP INT QUIT TERM ABRT

        {
            [ -f "$lk_file" ] || printf -- "- [[%s-%s-%s]] - (Daily Summary)\n    created: [[%s-%s-%s]] - %s\n" "$1" "$2" "$3" "$1" "$2" "$3" "$5"
            grep -q "^    - $4" "$lk_file" 2>/dev/null || printf "    - %s - (Hourly Summary)\n" "$4"
            printf "        - %s - %s%s\n" "$5" "${lk_cat:+$lk_cat }" "$lk_text"
        } >> "$lk_file"

        rmdir "$lk_lock" 2>/dev/null
        
        # CLI Feedback
        printf "${LK_GREEN}✔${LK_RESET}         - ${LK_LIME}%s${LK_RESET} - ${LK_ORANGE}%s${LK_GREY}%s${LK_RESET}\n" "$5" "${lk_cat:+$lk_cat }" "$lk_text"

        case "${LK_TAIL_LINES:-0}" in
            *[!0-9]*|"") ;; 
            0) ;;           
            *) 
                # Colorized Tail Output
                printf "${LK_DIM}--- Tail: Last %s lines from %s ---${LK_RESET}\n" "$LK_TAIL_LINES" "$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
                
                tail -n "$LK_TAIL_LINES" "$lk_file" | awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
                $0 ~ /^- \[\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]\]/ {
                    print amber $0 reset; next
                }
                $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {
                    print cyan $0 reset; next
                }
                $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
                    ts_part = substr($0, 1, 21)
                    rest_part = substr($0, 22)
                    
                    if (match(rest_part, /^\[\[.*\]\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        print lime ts_part orange tag_part grey msg_part reset
                    } else if (match(rest_part, /^\[[a-zA-Z0-9._-]+\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        print lime ts_part orange tag_part grey msg_part reset
                    } else {
                        print lime ts_part grey rest_part reset
                    }
                    next
                }
                { print grey $0 reset }
                '
                printf "${LK_DIM}------------------------------------------------------------${LK_RESET}\n"
                ;;
        esac
    )
}
