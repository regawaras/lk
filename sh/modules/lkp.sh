_lk_helper() {
    local CATEGORY_STRING="$1"
    shift

    if [ "$1" = "-add" ]; then
        shift
        local alias_name="$1"
        shift
        local tag_text="$*"
        
        if [ -z "$alias_name" ] || [ -z "$tag_text" ]; then
            printf "\033[31mUsage: lk -add <alias> <\"Tag Description\">\033[0m\n"
            printf "Example: lk -add wrv \"Writing on Vim\"\n"
            return 1
        fi
        
        mkdir -p "$LK_CONFIG_DIR"
        printf "%s() { _lk_helper \"[[%s]] >>\" \"\$@\"; }\n" "$alias_name" "$tag_text" >> "$LK_TAGS_FILE"
        printf "\033[32mSuccess: Tag '%s' added as [[%s]]\033[0m\n" "$alias_name" "$tag_text"
        
        . "$LK_TAGS_FILE"
        return 0
    fi

    if [ "$1" = "-set" ]; then
        shift
        case "$1" in
            -today|-t)
                shift
                local today
                today=$(date +%Y-%m-%d)
                _lk_set_daily_summary "$today" "$@"
                ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                local target_date="$1"
                shift
                _lk_set_daily_summary "$target_date" "$@"
                ;;
            -dir)
                shift
                local target_arg="$1"
                local new_dir=""
                
                if [ -z "$target_arg" ]; then
                    printf "\033[31mUsage: lk -set -dir <path | -home | -default>\033[0m\n"
                    return 1
                fi

                case "$target_arg" in
                    -home) new_dir="$HOME/LogKlerk" ;;
                    -default) new_dir="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk" ;;
                    *) new_dir="$target_arg" ;;
                esac
                
                mkdir -p "$LK_CONFIG_DIR"
                echo "LK_DIR=\"$new_dir\"" > "$LK_CONFIG_FILE"
                mkdir -p "$new_dir"
                
                printf "\033[32mSuccess: LogKlerk data directory changed to -> %s\033[0m\n" "$new_dir"
                
                if [ "$LK_DIR" != "$new_dir" ] && [ -d "$LK_DIR" ]; then
                    printf "\033[33mNote: Your old logs remain in: %s\033[0m\n" "$LK_DIR"
                    printf "To migrate them, run: \033[36mmv \"%s\"/* \"%s\"/\033[0m\n" "$LK_DIR" "$new_dir"
                fi
                
                LK_DIR="$new_dir"
                ;;
            *)
                _lk_set_summary "$@"
                ;;
        esac
        return 0
    fi

    if [ "$1" = "-search" ] || [ "$1" = "s" ]; then
        shift
        lks "$@"
        return 0
    fi

    if [ "$1" = "-help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        lkh
        return 0
    fi

    local NOTE_TEXT="$*"
    if [ -z "$NOTE_TEXT" ]; then
        _lk_interactive_mode "$CATEGORY_STRING"
    else
        local LAST_RAW
        LAST_RAW=$(_lk_write_logic "$CATEGORY_STRING" "$NOTE_TEXT")
        
        _lk_get_time
        local FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"

        printf "\033[32mSuccess: Log added to %s\033[0m\n" "$FILENAME"
        printf "\033[2m------------------------------------------------------------\033[0m\n"

        tail -n 3 "$FILENAME" | while IFS= read -r l; do
            if [ "$l" = "$LAST_RAW" ]; then
                printf "\033[38;5;123m%s [NEW]\033[0m\n" "$l"
            else
                printf "%s\n" "$l"
            fi
        done
        printf "\033[2m------------------------------------------------------------\033[0m\n"
    fi
}

