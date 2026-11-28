#!/bin/sh
# Module: Visual Editor (lkv) - Standalone & Smart Module Router

lkv() { 
    # --- 1. Standalone Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_MODULES_DIR="${LK_CONFIG_DIR}/modules"
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    case "${1:-}" in
        # --- 2. Help Menu ---
       	-h|-help|--help|help)
            # Deteksi modul secara dinamis dari folder
            lkv_available_mods=""
            if [ -d "$LK_MODULES_DIR" ]; then
                for f in "$LK_MODULES_DIR"/*.sh; do
                    [ -e "$f" ] || continue
                    # Hapus path folder dan ekstensi .sh
                    mod_name="${f##*/}"
                    mod_name="${mod_name%.sh}"
                    lkv_available_mods="${lkv_available_mods}${mod_name}, "
                done
                # Hapus koma dan spasi ekstra di bagian paling akhir
                lkv_available_mods="${lkv_available_mods%, }"
            fi
            [ -z "$lkv_available_mods" ] && lkv_available_mods="none"

            printf "\n\033[38;2;255;204;0m| LK (LogKlerk) --- Visual Editor (lkv) Help ---\033[0m\n"
            printf "  \033[38;2;170;100;255mlkv\033[0m                      \033[90mOpen today's log\033[0m\n"
            printf "  \033[38;2;170;100;255mlkv\033[0m \033[38;2;0;255;255mYYYYMMDD\033[0m             \033[90mOpen specific date's log (e.g., 20260424)\033[0m\n"
            printf "  \033[38;2;170;100;255mlkv\033[0m \033[38;2;255;102;0m<module>\033[0m             \033[90mEdit module (e.g., %s)\033[0m\n" "$lkv_available_mods"
            printf "  \033[38;2;170;100;255mlkv\033[0m \033[38;2;100;255;0mlk\033[0m                   \033[90mEdit main lk.sh router\033[0m\n"
            printf "  \033[38;2;170;100;255mlkv\033[0m \033[38;2;100;255;0mconf\033[0m                 \033[90mEdit configuration (lk.conf)\033[0m\n"
            printf "  \033[38;2;170;100;255mlkv\033[0m \033[38;2;100;255;0mbanner\033[0m               \033[90mEdit LKI ASCII banner\033[0m\n"
            printf "  \033[38;2;170;100;255mlkvh\033[0m                     \033[90mShow this help menu\033[0m\n"
            printf "\033[38;2;255;117;0m------------------------------------------------\033[0m\n"
            return 0 
            ;;

        # --- 3. System & Config Editor Flags ---
        -config|-dir|config|conf|-conf)
            ${EDITOR:-vi} "$LK_CONFIG_FILE"
            return 0 ;;
        -lk|lk)
            ${EDITOR:-vi} "$LK_CONFIG_DIR/lk.sh"
            return 0 ;;
        -banner|banner)
            ${EDITOR:-vi} "$LK_CONFIG_DIR/assets/banner.txt"
            return 0 ;;
        
        # --- 4. Smart Module Router ---
        # Catch all existing module names (with or without '-' prefix)
        -context|context|-lkc|lkc|-lkconf|lkconf|-lkfiles|lkfiles|-lkh|lkh|-lki|lki|-lkset|lkset|-lksort|lksort|-lks|lks|-lksum|lksum|-lkv|lkv)
            target="${1#-}" # Remove '-' prefix if user typed -module
            ${EDITOR:-vi} "$LK_MODULES_DIR/${target}.sh"
            
            # If editing context, source it immediately to apply changes
            if [ "$target" = "context" ]; then
                . "$LK_MODULES_DIR/context.sh"
            fi
            return 0 ;;
            
        # --- 5. Data Log Editor (YYYY-MM-DD or YYYYMMDD) ---
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            # Parse YYYYMMDD format into YYYY-MM-DD
            if [ "${#1}" -eq 8 ]; then
                y="${1%????}"
                m_d="${1#????}"
                m="${m_d%??}"
                d="${m_d#??}"
                lkv_date="$y-$m-$d"
            else
                lkv_date="$1"
            fi
            
            lkv_year="${lkv_date%%-*}"
            lkv_month="${lkv_date%-*}"
            lkv_dir="$LK_DIR/$lkv_year/$lkv_month"
            
            mkdir -p "$lkv_dir"
            ${EDITOR:-vi} "$lkv_dir/$lkv_date${LK_DEFAULT_FORMAT}"
            return 0
            ;;
            
        # --- 6. Default Fallback (Edit Today's Log) ---
        "") 
            lkv_today=$(date +%Y-%m-%d)
            lkv_year=$(date +%Y)
            lkv_month=$(date +%Y-%m)
            lkv_dir="$LK_DIR/$lkv_year/$lkv_month"
            
            mkdir -p "$lkv_dir"
            ${EDITOR:-vi} "$lkv_dir/$lkv_today${LK_DEFAULT_FORMAT}"
            return 0
            ;;
            
        # --- 7. Error Handling ---
        *)
            printf "\033[31m[Error]\033[0m Invalid date format or module not found. Type \033[38;2;0;255;255mlkvh\033[0m for help.\n"
            return 1
            ;;
    esac
}

# Alias Wrapper for Help
lkvh() {
    lkv -help
}
