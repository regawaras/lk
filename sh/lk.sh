#!/bin/sh
# LogKlerk (LK) v0.0.5 Experimental - 100% POSIX-Compliant Core
# Feature: Chronological AWK Injector, Native ![TAGS]! Highlighting & %b Formatter

LK_STATUS="experimental"; LK_VERSION="v0.0.5"

# 1. POSIX Absolute Path Resolution
LK_INSTALL_DIR=$(cd "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)
LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"

# 2. User Configuration Directory
LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
LK_TAXONOMY_FILE="$LK_CONFIG_DIR/modules/context.sh"

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
# COLOR PALETTE CONFIGURATION (ZERO-SUBSHELL OVERHEAD)
# =========================================================================
LK_RESET='\033[0m'
LK_AMBER='\033[38;2;255;255;0m'
LK_LIME='\033[38;2;100;255;0m'
LK_GREY='\033[38;2;150;150;150m'
LK_CYAN='\033[38;2;0;255;255m'
LK_ORANGE='\033[38;2;225;102;0m'
LK_DIM='\033[2m'
LK_GREEN='\033[32m'
LK_MAGENTA='\033[38;2;255;100;255m'
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
        "")
            if type lki >/dev/null 2>&1; then
                lki ""
                return $?
            else
                curr_hr=$(date +%H:00)
                if [ -f "$LK_BANNER" ]; then
                    printf "%b" "$LK_ORANGE"
                    cat "$LK_BANNER"
                fi
                printf "%b | LK LogKlerk %s %s | Github: https://github.com/regawaras/lk/ |\n" "$LK_ORANGE" "$LK_STATUS" "$LK_VERSION"
                printf " | ''Just Open Terminal, Type, Enter, Forget Brutal'' -LK LogKlerking Creator |\n"
                printf "%b | -------------- LK Interactive Mode (Hybrid Shell & Context) -------------- |\n" "$LK_GREY"
                printf " | Hour Block: %b%s%b | Source: %s |\n%b" "$LK_CYAN" "$curr_hr" "$LK_GREY" "$LK_CONFIG_DIR" "$LK_RESET"
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
        [ -z "$lk_text" ] && { printf "%b[Error]%b No Input.\n" "$LK_RED" "$LK_RESET" >&2; exit 1; }

        set -- $(date '+%Y %m %d %H:00 %H:%M:%S')
        lk_tdir="${LK_DIR}/$1/$1-$2"
        lk_file="${lk_tdir}/$1-$2-$3${LK_DEFAULT_FORMAT:-.md}"
        lk_lock="${lk_file}.lock.d"

        [ -d "$lk_tdir" ] || mkdir -p "$lk_tdir"

        while ! mkdir "$lk_lock" 2>/dev/null; do sleep 1; done
        trap 'rmdir "$lk_lock" 2>/dev/null; exit 1' HUP INT QUIT TERM ABRT

        if [ ! -f "$lk_file" ]; then
            printf -- "- # [[%s-%s-%s]] - (Daily Summary)\n    created: [[%s-%s-%s]] - %s\n" "$1" "$2" "$3" "$1" "$2" "$3" "$5" > "$lk_file"
        fi

        lk_tmp="${lk_file}.tmp"
        new_hdr="    - ## $4 - (Hourly Summary)"
        new_log="        - $5 - ${lk_cat:+$lk_cat }$lk_text"

        LC_ALL=C awk -v t_hr="$4" -v n_hdr="$new_hdr" -v n_log="$new_log" '
        BEGIN {
            inserted = 0
            in_target = 0
            t_hr_val = substr(t_hr, 1, 2) + 0
        }
        {
            if ($0 ~ /^ {4}- (## )?[0-2][0-9]:00 /) {
                match($0, /[0-2][0-9]:00/)
                curr_hr_val = substr($0, RSTART, 2) + 0
                
                if (curr_hr_val == t_hr_val) {
                    in_target = 1
                    print $0
                    next
                } else if (curr_hr_val > t_hr_val && inserted == 0) {
                    if (in_target == 1) {
                        print n_log
                    } else {
                        print n_hdr
                        print n_log
                    }
                    inserted = 1
                    in_target = 0
                    print $0
                    next
                } else {
                    in_target = 0
                    print $0
                    next
                }
            }
            print $0
        }
        END {
            if (inserted == 0) {
                if (in_target == 1) {
                    print n_log
                } else {
                    print n_hdr
                    print n_log
                }
            }
        }' "$lk_file" > "$lk_tmp" && mv "$lk_tmp" "$lk_file"

        rmdir "$lk_lock" 2>/dev/null
        
        # Output CLI Feedback dengan Highlighter Native
        printf "%s\n" "$lk_text" | LC_ALL=C awk -v cat_str="$lk_cat" -v ts="$5" '
        BEGIN {
            RESET   = "\033[0m"
            GREEN   = "\033[32m"
            LIME    = "\033[38;2;100;255;0m"
            ORANGE  = "\033[38;2;225;102;0m"
            MAGENTA = "\033[38;2;255;100;255m"
            GREY    = "\033[38;2;150;150;150m"
        }
        {
            cat_display = (cat_str != "") ? ORANGE cat_str " " RESET : ""
            
            if (match($0, /^!\[[^\]]+\]!/)) {
                tag = substr($0, RSTART, RLENGTH)
                msg = substr($0, RLENGTH + 1)
                sub(/^[[:space:]]+/, "", msg)
                
                t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
                printf "%s✔%s        - %s%s%s - %s%s%s%s %s%s%s\n", GREEN, RESET, LIME, ts, RESET, cat_display, t_col, tag, RESET, GREY, msg, RESET
            } else {
                printf "%s✔%s        - %s%s%s - %s%s%s%s\n", GREEN, RESET, LIME, ts, RESET, cat_display, GREY, $0, RESET
            }
        }'

        case "${LK_TAIL_LINES:-0}" in
            *[!0-9]*|"") ;; 
            0) ;;           
            *) 
                printf "%b--- Tail: Last %s lines from %s ---%b\n" "$LK_DIM" "$LK_TAIL_LINES" "$1-$2-$3${LK_DEFAULT_FORMAT:-.md}" "$LK_RESET"
                
                tail -n "$LK_TAIL_LINES" "$lk_file" | tr -d '\033\015\010\007' | LC_ALL=C awk '
                BEGIN {
                    RESET   = "\033[0m"
                    AMBER   = "\033[38;2;255;255;0m"
                    LIME    = "\033[38;2;100;255;0m"
                    GREY    = "\033[38;2;150;150;150m"
                    CYAN    = "\033[38;2;0;255;255m"
                    ORANGE  = "\033[38;2;225;102;0m"
                    MAGENTA = "\033[38;2;255;100;255m"
                }
                
                $0 ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
                    match($0, /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\][[:space:]]*-?[[:space:]]*/)
                    prefix = substr($0, 1, RLENGTH)
                    rest = substr($0, RLENGTH + 1)
                    
                    if (match(rest, /^!\[[^\]]+\]!/)) {
                        tag = substr(rest, RSTART, RLENGTH)
                        msg = substr(rest, RLENGTH + 1)
                        t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
                        print AMBER prefix RESET t_col tag RESET GREY msg RESET
                    } else {
                        print AMBER prefix RESET GREY rest RESET
                    }
                    next
                }
                
                $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
                    match($0, /^[ ]{4}- (## )?[0-2][0-9]:00[[:space:]]*-?[[:space:]]*/)
                    prefix = substr($0, 1, RLENGTH)
                    rest = substr($0, RLENGTH + 1)
                    
                    if (match(rest, /^!\[[^\]]+\]!/)) {
                        tag = substr(rest, RSTART, RLENGTH)
                        msg = substr(rest, RLENGTH + 1)
                        t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
                        print CYAN prefix RESET t_col tag RESET GREY msg RESET
                    } else {
                        print CYAN prefix RESET GREY rest RESET
                    }
                    next
                }
                
                $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
                    ts_part = substr($0, 1, 21)
                    rest_part = substr($0, 22)
                    
                    if (match(rest_part, /^\[\[.*\]\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        
                        if (match(msg_part, /^!\[[^\]]+\]!/)) {
                            sub_tag = substr(msg_part, RSTART, RLENGTH)
                            sub_msg = substr(msg_part, RLENGTH + 1)
                            sub_col = (sub_tag == "![PLAN]!") ? MAGENTA : ORANGE
                            print LIME ts_part ORANGE tag_part RESET sub_col sub_tag RESET GREY sub_msg RESET
                        } else {
                            print LIME ts_part ORANGE tag_part GREY msg_part RESET
                        }
                    } else if (match(rest_part, /^\[[a-zA-Z0-9._-]+\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        print LIME ts_part ORANGE tag_part GREY msg_part RESET
                    } else {
                        if (match(rest_part, /^!\[[^\]]+\]!/)) {
                            tag = substr(rest_part, RSTART, RLENGTH)
                            msg = substr(rest_part, RLENGTH + 1)
                            t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
                            print LIME ts_part RESET t_col tag RESET GREY msg RESET
                        } else {
                            print LIME ts_part GREY rest_part RESET
                        }
                    }
                    next
                }
                { 
                    print GREY $0 RESET 
                }
                '
                
                printf "%b------------------------------------------------------------%b\n" "$LK_DIM" "$LK_RESET"
                ;;
        esac
    )
}
