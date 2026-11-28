#!/bin/sh
# Module: Visual Editor (lkv) - Standalone & Smart Module Router
# Version: v0.0.5 (Dynamic Module Routing Edition)

lkv() { 
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"
    
    # Load Config to get LK_DIR and LK_DEFAULT_FORMAT
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # Define Colors
    LKV_CYAN='\033[38;2;0;255;255m'
    LKV_PURPLE='\033[38;2;170;100;255m'
    LKV_AMBER='\033[38;2;255;204;0m'
    LKV_ORANGE='\033[38;2;255;102;0m'
    LKV_LIME='\033[38;2;100;255;0m'
    LKV_GREY='\033[90m'
    LKV_RED='\033[31m'
    LKV_RESET='\033[0m'

    case "${1:-}" in
        # --- 2. Help Menu ---
        -h|-help|--help|help)
            lkv_available_mods=""
            if [ -d "$LK_MODULES_DIR" ]; then
                for f in "$LK_MODULES_DIR"/*.sh; do
                    [ -e "$f" ] || continue
                    m_name="${f##*/}"
                    lkv_available_mods="${lkv_available_mods}${m_name%.sh}, "
                done
                lkv_available_mods="${lkv_available_mods%, }"
            fi

            printf "\n%b| LK (LogKlerk) --- Visual Editor (lkv) Help ---%b\n" "$LKV_AMBER" "$LKV_RESET"
            printf "  %b%-15s%b %bOpen today's log%b\n" "$LKV_PURPLE" "lkv" "$LKV_RESET" "$LKV_GREY" "$LKV_RESET"
            printf "  %b%-15s%b %bOpen specific date's log%b\n" "$LKV_PURPLE" "lkv YYYYMMDD" "$LKV_RESET" "$LKV_GREY" "$LKV_RESET"
            printf "  %b%-15s%b %bEdit module file%b\n" "$LKV_PURPLE" "lkv <mod_name>" "$LKV_RESET" "$LKV_GREY" "$LKV_RESET"
            printf "  %b%-15s%b %bEdit core router%b\n" "$LKV_PURPLE" "lkv lk" "$LKV_RESET" "$LKV_GREY" "$LKV_RESET"
            printf "  %b%-15s%b %bEdit lk.conf%b\n" "$LKV_PURPLE" "lkv conf" "$LKV_RESET" "$LKV_GREY" "$LKV_RESET"
            printf "  %bAvailable:%b %b%s%b\n" "$LKV_ORANGE" "$LKV_RESET" "$LKV_CYAN" "$lkv_available_mods" "$LKV_RESET"
            printf "%b------------------------------------------------%b\n" "$LKV_ORANGE" "$LKV_RESET"
            return 0 
            ;;

        # --- 3. Core System Editor ---
        conf|config|-conf|-config)
            ${EDITOR:-vi} "$LK_CONFIG_FILE"
            return 0 ;;
        lk|-lk)
            ${EDITOR:-vi} "$LK_CONFIG_DIR/lk.sh"
            return 0 ;;
        banner|-banner)
            ${EDITOR:-vi} "$LK_CONFIG_DIR/assets/banner.txt"
            return 0 ;;
            
        # --- 4. Dynamic Data Log Editor (YYYY-MM-DD or YYYYMMDD) ---
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            if [ "${#1}" -eq 8 ]; then
                y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
                lkv_date="$y-$m-$d"
            else
                lkv_date="$1"
            fi
            lkv_year="${lkv_date%%-*}"
            lkv_month="${lkv_date%-*}"
            lkv_dir="$LK_DIR/$lkv_year/$lkv_month"
            mkdir -p "$lkv_dir"
            ${EDITOR:-vi} "$lkv_dir/$lkv_date${LK_DEFAULT_FORMAT}"
            return 0 ;;

        # --- 5. Dynamic Module Router (The Upgrade) ---
        "") # Default: Today's Log
            lkv_today=$(date +%Y-%m-%d); lkv_year=$(date +%Y); lkv_month=$(date +%Y-%m)
            lkv_dir="$LK_DIR/$lkv_year/$lkv_month"
            mkdir -p "$lkv_dir"
            ${EDITOR:-vi} "$lkv_dir/$lkv_today${LK_DEFAULT_FORMAT}"
            return 0 ;;

        *) # Check if the argument is a module name
            target="${1#-}" # Remove '-' if exists
            if [ -f "$LK_MODULES_DIR/${target}.sh" ]; then
                ${EDITOR:-vi} "$LK_MODULES_DIR/${target}.sh"
                [ "$target" = "context" ] && . "$LK_MODULES_DIR/context.sh"
                return 0
            else
                printf "%b[Error]%b Module or Date '%s' not found.\n" "$LKV_RED" "$LKV_RESET" "$1"
                return 1
            fi
            ;;
    esac
}

lkvh() { lkv -help; }
