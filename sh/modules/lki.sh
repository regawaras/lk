#!/bin/sh
# Module: lki (Standalone Interactive with Dynamic Taxonomy Parser & Hybrid Shell Logging)
# Updated to v0.0.5: Global Zero-Subshell %b Formatting & Pure AWK Constants

lki() {
    CATEGORY_STRING="$1"

    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"
    
    LK_DIR="/srv/als/lk/"
    LK_DEFAULT_FORMAT=".md"
    
    LK_TAIL_LINES="10"
    LK_COMMAND_TAIL_LINES="1"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION (ZERO-SUBSHELL OVERHEAD)
    # =========================================================================
    LK_RESET='\033[0m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_GREY='\033[38;2;150;150;150m' 
    LK_CYAN='\033[38;2;0;255;255m'
    LK_PURPLE='\033[38;2;180;100;255m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_DIM='\033[2m'
    LK_DARKGREY='\033[38;2;105;105;105m'
    LK_YELLOW='\033[38;2;255;220;0m'
    LK_MAGENTA='\033[38;2;255;100;255m'
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
            printf "%b" "$LK_ORANGE"
            cat "$LK_CONFIG_DIR/assets/banner.txt"
            printf "%b" "$LK_RESET"
        fi
        
        # Penggunaan %b wajib untuk merender literal escape \033
        printf "%b | LK LogKlerk %s %s | Github: https://github.com/regawaras/lk/ |\n%b" "$LK_ORANGE" "$LK_STATUS" "$LK_VERSION" "$LK_RESET"
        printf "%b | ''Just Open Terminal, Type, Enter, Forget Brutal'' -LK LogKlerking Creator |\n%b" "$LK_ORANGE" "$LK_RESET"
        printf "%b | -------------- LK Interactive Mode (Hybrid Shell & Context) -------------- |\n%b" "$LK_GREY" "$LK_RESET"
        printf "%b | Hour Block: %b%s%b | Source: %s |\n%b\n" "$LK_GREY" "$LK_CYAN" "$CURRENT_HOUR" "$LK_GREY" "$LK_CONFIG_DIR" "$LK_RESET"
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
            printf "%bLog As %s to %s\n>> %b" "$LK_ORANGE" "$disp_prompt" "$disp_filename" "$LK_RESET"
        else
            printf "%bLog to %s\n>> %b" "$LK_ORANGE" "$disp_filename" "$LK_RESET"
        fi

        if ! read -r line; then break; fi
        _lki_update_vars
        curr_ts=$(date +%H:%M:%S)
        
        printf "\033[F\033[K\033[F\033[K" 
        
        if [ -n "$line" ]; then
            printf "%b❯ %s%b\n" "$LK_MAGENTA" "$line" "$LK_RESET"

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
                printf -- "- # [[%s]] - (Daily Summary)\n" "$TODAY" > "$FILENAME"
                printf "%screated: [[%s]] - %s\n" "$indent" "$TODAY" "$curr_ts" >> "$FILENAME"
            fi

            if [ -n "$ACTIVE_TAG" ]; then
                log_entry="${indent}${indent}- ${curr_ts} - ${ACTIVE_TAG} ${LOG_TEXT}"
            else
                log_entry="${indent}${indent}- ${curr_ts} - ${LOG_TEXT}"
            fi

            lk_tmp="${FILENAME}.tmp"
            new_hdr="${indent}- ## $CURRENT_HOUR - (Hourly Summary)"

            LC_ALL=C awk -v t_hr="$CURRENT_HOUR" -v n_hdr="$new_hdr" -v n_log="$log_entry" '
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
            }' "$FILENAME" > "$lk_tmp" && mv "$lk_tmp" "$FILENAME"

            printf "%b--- Last %s Lines ---%b\n" "$LK_DIM" "$current_tail_lines" "$LK_RESET"
            
            # --- PEMBARUAN V0.0.5: Injeksi Pewarnaan Dinamis AWK Native ---
            tail -n "$current_tail_lines" "$FILENAME" | tr -d '\033\015\010\007' | LC_ALL=C awk '
            BEGIN {
                RESET   = "\033[0m"
                AMBER   = "\033[38;2;255;204;0m"
                LIME    = "\033[38;2;100;255;0m"
                GREY    = "\033[38;2;150;150;150m"
                CYAN    = "\033[38;2;0;255;255m"
                ORANGE  = "\033[38;2;225;102;0m"
                MAGENTA = "\033[38;2;255;100;255m"
            }
            
            # Catch Daily Summary
            $0 ~ /^-[[:space:]]*(#)?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
                match($0, /^-[[:space:]]*(#)?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\][[:space:]]*-?[[:space:]]*/)
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
            
            # Catch Hourly Summary
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
            
            # Catch Regular Log / Taxonomy
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
        fi
    done
}
