#!/bin/sh
# Module: lki (Standalone Interactive with Dynamic Taxonomy Parser & Hybrid Shell Logging)

lki() {
    CATEGORY_STRING="$1"

    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"
    
    LK_DIR="/run/media/nixos/c9a0990e-ba7f-4860-ba3b-1a7cd1182b50/home/regawaras/als/lk/"
    LK_DEFAULT_FORMAT=".md"
    
    LK_TAIL_LINES="10"
    LK_COMMAND_TAIL_LINES="1"

    # Muat konfigurasi lebih dulu sebelum mendefinisikan warna
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION (Namespace Protected)
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;204;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[38;2;150;150;150m') 
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_PURPLE=$(printf '\033[38;2;180;100;255m')
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')
    LK_DIM=$(printf '\033[2m')
    LK_DARKGREY=$(printf '\033[38;2;105;105;105m')
    LK_YELLOW=$(printf '\033[38;2;255;220;0m')
    LK_MAGENTA=$(printf '\033[1;35m')
    # =========================================================================

    _lki_update_vars() {
        TODAY=$(date +%Y-%m-%d)
        YEAR=$(date +%Y)
        MONTH=$(date +%Y-%m)
        CURRENT_HOUR=$(date +%H:00)
        LK_TDIR="$LK_DIR/$YEAR/$MONTH"
        FILENAME="$LK_TDIR/$TODAY${LK_DEFAULT_FORMAT}"
    }

    _lki_draw_header() {
        clear 
        
        if [ -f "$LK_CONFIG_DIR/assets/banner.txt" ]; then
            printf "%s" "$LK_ORANGE"
            cat "$LK_CONFIG_DIR/assets/banner.txt"
            printf "%s" "$LK_RESET"
        fi
        
        printf "${LK_ORANGE} | LK LogKlerk %s %s | Github: https://github.com/regawaras/lk/ |\n${LK_RESET}" "$LK_STATUS" "$LK_VERSION"
        printf "${LK_ORANGE} | ''Just Open Terminal, Type, Enter, Forget Brutal'' -LK LogKlerking Creator |\n${LK_RESET}" 
        printf "${LK_GREY} | -------------- LK Interactive Mode (Hybrid Shell & Context) -------------- |\n${LK_RESET}"
        printf "${LK_GREY} | Hour Block: ${LK_CYAN}%s${LK_GREY} | Source: %s |\n${LK_RESET}" "$CURRENT_HOUR" "$LK_CONFIG_DIR"
        printf "\n"
    }

    _lki_update_vars
    _lki_draw_header

    executing_shell=$(ps -p $$ -o comm= 2>/dev/null || basename "$SHELL" 2>/dev/null || echo "sh")
    executing_shell=$(basename "$executing_shell" | sed 's/^-//')
    SHELL_TAG="[[$executing_shell]] >>"

    while true; do
        _lki_update_vars
        current_tail_lines="$LK_TAIL_LINES"
        
        disp_prompt=$(echo "$CATEGORY_STRING" | sed 's/ >>$//')
        disp_filename="${FILENAME#$HOME/}"
        [ "$disp_filename" != "$FILENAME" ] && disp_filename="~/$disp_filename"

        if [ -n "$disp_prompt" ]; then
            printf "${LK_ORANGE}Log As %s to %s\n>> ${LK_RESET}" "$disp_prompt" "$disp_filename"
        else
            printf "${LK_ORANGE}Log to %s\n>> ${LK_RESET}" "$disp_filename"
        fi

        if ! read -r line; then break; fi
        curr_ts=$(date +%H:%M:%S)
        
        # Menghapus dua baris prompt ke atas setelah user menekan enter
        printf "\033[F\033[K\033[F\033[K" 
        
        if [ -n "$line" ]; then
            printf "${LK_MAGENTA}❯ %s${LK_RESET}\n" "$line"

            cmd="${line%% *}"
            args="${line#* }"
            [ "$cmd" = "$args" ] && args=""

            if [ "$cmd" = "-exit" ] || [ "$cmd" = "-q" ] || [ "$cmd" = "exit" ] || [ "$cmd" = "quit" ]; then
                break
            fi
            
            if [ "$cmd" = "clear" ]; then
                _lki_draw_header
                continue
            fi

            override_tag=""
            if [ -f "$LK_TAXONOMY_FILE" ] && [ -n "$cmd" ]; then
                override_tag=$(grep "^${cmd}[[:space:]]*()[[:space:]]*{" "$LK_TAXONOMY_FILE" 2>/dev/null | sed -n 's/.*lk_context "\(.*\)" "\$@".*/\1/p')
            fi

            is_fullscreen=0
            case "$cmd" in
                vim|vi|nano|htop|top|less|man|tmux|screen) is_fullscreen=1 ;;
            esac

            if [ -n "$override_tag" ]; then
                if [ -z "$args" ]; then
                    CATEGORY_STRING="$override_tag"
                    continue 
                else
                    ACTIVE_TAG="$override_tag"
                    LOG_TEXT="$args"
                fi
            elif [ "$is_fullscreen" -eq 1 ]; then
                eval "$line"
                _lki_draw_header 
                ACTIVE_TAG="$SHELL_TAG"
                LOG_TEXT="$line"
                current_tail_lines="$LK_COMMAND_TAIL_LINES"
            elif command -v "$cmd" >/dev/null 2>&1; then
                eval "$line"
                ACTIVE_TAG="$SHELL_TAG"
                LOG_TEXT="$line"
                current_tail_lines="$LK_COMMAND_TAIL_LINES"
            else
                ACTIVE_TAG="$CATEGORY_STRING"
                LOG_TEXT="$line"
            fi

            mkdir -p "$LK_TDIR"
            indent="    "

            if [ ! -f "$FILENAME" ]; then
                printf -- "- # [[%s]] - (Daily Summary)\n" "$TODAY" >> "$FILENAME"
                printf "%screated: [[%s]] - %s\n" "$indent" "$TODAY" "$curr_ts" >> "$FILENAME"
            fi

            # FIX 1: Deteksi dan penulisan blok Jam Baru (Hard Fork '##')
            if ! grep -q "^${indent}- ## ${CURRENT_HOUR} -" "$FILENAME" 2>/dev/null; then
                printf "%s- ## %s - (Hourly Summary)\n" "$indent" "$CURRENT_HOUR" >> "$FILENAME"
            fi

            if [ -n "$ACTIVE_TAG" ]; then
                log_entry="${indent}${indent}- ${curr_ts} - ${ACTIVE_TAG} ${LOG_TEXT}"
            else
                log_entry="${indent}${indent}- ${curr_ts} - ${LOG_TEXT}"
            fi

            printf "%s\n" "$log_entry" >> "$FILENAME"
            
            printf "${LK_DIM}--- Last %s Lines ---${LK_RESET}\n" "$current_tail_lines"
            
            # FIX 2: Pembaruan regex AWK untuk mewarnai '## HH:00' dengan benar
            tail -n "$current_tail_lines" "$FILENAME" | awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
            $0 ~ /^-[[:space:]]*(#)?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
                print amber $0 reset; next
            }
            $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
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
            { 
                print grey $0 reset 
            }
            '
            
            printf "${LK_DIM}------------------------------------------------------------${LK_RESET}\n"
        fi
    done
}
