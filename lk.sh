# LogKlerk (LK) - A POSIX-compliant Daily Notes Terminal
# Compatible with dash, sh, bash, zsh

# --- Configuration & Paths ---
# LogKlerk (LK) - Core Dispatcher
LK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/logklerk"
LK_CONFIG_FILE="$LK_CONFIG_DIR/lk.conf"
LK_MODULES_DIR="$LK_CONFIG_DIR/modules"
LK_TAXONOMY_FILE="$LK_CONFIG_DIR/taxonomy.sh"

LK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk"

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

_lk_write_logic() {
    CATEGORY="$1"
    TEXT="$2"
    _lk_get_time
    
    TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    FILENAME="$TARGET_DIR/$TODAY.md"
    LOCKFILE="$LK_CONFIG_DIR/.lk_write.lock"
    INDENT_4="    "
    INDENT_8="        "
    
    mkdir -p "$TARGET_DIR"

(
        flock -x 9
        if [ ! -f "$FILENAME" ]; then
            printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$FILENAME"
            printf "%screated: [[%s]] - %s\n" "$INDENT_4" "$TODAY" "$FULL_TIMESTAMP" >> "$FILENAME"
        fi
        if ! grep -q "^${INDENT_4}- $CURRENT_HOUR" "$FILENAME"; then
            printf "%s- %s - (Hourly Summary)\n" "$INDENT_4" "$CURRENT_HOUR" >> "$FILENAME"
        fi

        NEW_ENTRY="${INDENT_8}- $FULL_TIMESTAMP - $CATEGORY $TEXT"
        printf "%s\n" "$NEW_ENTRY" >> "$FILENAME"
        
        printf "%s\n" "$NEW_ENTRY"
    ) 9> "$LOCKFILE"
}

_lk_helper() {
    CATEGORY_STRING="$1"
    shift

    if [ "$1" = "-set" ]; then
        shift
        case "$1" in
            -alias)
                shift
		if [ -z "$1" ]; then
                    printf "\033[38;2;255;117;0m--- Registered Taxonomy Aliases ---\033[0m\n"
                    printf "\033[38;2;255;117;0m--- How to add Example: 'lk -set -alias sog=<Searching on Google>' ---\033[0m\n"
                    if [ -f "$LK_TAXONOMY_FILE" ]; then
                        # AWK POSIX-compliant untuk memformat fungsi shell menjadi tabel rapi
                        awk '
                        /\(\) \{ _lk_helper/ {
                            # Ekstrak nama alias
                            split($0, a, "()"); 
                            alias_name = a[1];
                            
                            # Ekstrak nilai tag di dalam tanda kutip
                            split($0, b, "\"");
                            tag_val = b[2];
                            
                            # Buang sufiks " >>" dari nilai tag
                            sub(/ >>$/, "", tag_val);
                            
                            printf "  \033[38;2;0;255;255m%-12s\033[0m : %s\n", alias_name, tag_val;
                        }' "$LK_TAXONOMY_FILE"
                    else
                        printf "  \033[31mNo taxonomy file found at %s.\033[0m\n" "$LK_TAXONOMY_FILE"
                    fi
                    printf "\033[38;2;255;117;0m-----------------------------------\033[0m\n"
                    return 0
                fi
                raw_input="$1"
                alias_name="${raw_input%%=*}"
                tag_text="${raw_input#*=}"
                tag_text=$(echo "$tag_text" | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
                mkdir -p "$LK_CONFIG_DIR"
                if printf "%s() { _lk_helper \"%s >>\" \"\$@\"; }\n" "$alias_name" "$tag_text" >> "$LK_TAXONOMY_FILE" 2>/dev/null; then
                    printf "\033[32mSuccess: Taxonomy '%s' mapped to '%s'\033[0m\n" "$alias_name" "$tag_text"
                    . "$LK_TAXONOMY_FILE"
                else
                    printf "\033[31mError: Permission denied. Cannot write to %s\033[0m\n" "$LK_TAXONOMY_FILE"
                    printf "\033[33mRun: sudo chown -R \$USER:\$USER %s\033[0m\n" "$LK_CONFIG_DIR"
                    return 1
                fi
                ;;
            -today|-t)
                shift
                today_date=$(date +%Y-%m-%d)
                _lk_set_daily_summary "$today_date" "$@"
                ;;
                
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                target_date="$1"
                shift
                _lk_set_daily_summary "$target_date" "$@"
                ;;
            -dir)
                shift
                target_arg="$1"
                new_dir=""
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
		printf "\033[32mSuccess: Directory changed to -> %s\033[0m\n" "$new_dir"
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

    if [ "$1" = "-search" ] || [ "$1" = "--search" ] || [ "$1" = "-s" ]; then
        shift
        lks "$@"
        return 0
    fi

    if [ "$1" = "-help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        lkh
        return 0
    fi

    NOTE_TEXT="$*"
    if [ -z "$NOTE_TEXT" ]; then
        _lk_interactive_mode "$CATEGORY_STRING"
    else
        LAST_RAW=$(_lk_write_logic "$CATEGORY_STRING" "$NOTE_TEXT")
        _lk_get_time
        FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"

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

_lk_interactive_mode() {
    CATEGORY_STRING="$1"
    _lk_get_time
    FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    
    clear
    printf "\033[38;2;255;117;0m--- LogKlerk Structured Mode: Chronological ---\033[0m\n"
    printf "Notes entering hour block: %s\n" "$CURRENT_HOUR"
    printf "Current Log Directory: %s\n" "$LK_DIR"
    printf "\033[2mType -help for menu, or -exit to quit.\033[0m\n\n"

    while true; do
        printf ">> "
        if ! read -r line; then break; fi
        
        if [ -n "$line" ]; then
            printf "\033[F\033[K"
            cmd="${line%% *}"
            args="${line#* }"
            [ "$cmd" = "$args" ] && args=""

            case "$cmd" in
                -set)
                    subcmd="${args%% *}"
                    subargs="${args#* }"
                    [ "$subcmd" = "$subargs" ] && subargs=""
                    case "$subcmd" in
                        -today) today_d=$(date +%Y-%m-%d); _lk_set_daily_summary "$today_d" "$subargs" ;;
                        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) _lk_set_daily_summary "$subcmd" "$subargs" ;;
                        -dir)
                            if [ -z "$subargs" ]; then continue; fi
                            case "$subargs" in
                                -home) ndir="$HOME/LogKlerk" ;;
                                -default) ndir="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk" ;;
                                *) ndir="$subargs" ;;
                            esac
                            mkdir -p "$LK_CONFIG_DIR" "$ndir"
                            echo "LK_DIR=\"$ndir\"" > "$LK_CONFIG_FILE"
                            LK_DIR="$ndir"
                            FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
                            ;;
                        *) _lk_set_summary "$args" ;;
                    esac
                    ;;
                -search|--search|-s|lks) lks "$args" ;;
                -help|--help|-h|lkh) lkh ;;
                -exit|-q|-quit|exit|quit) break ;;
                lkc) lkc "$args" ;;
                lkcs) lkcs "$args" ;;
                lkch) lkch "$args" ;;
                lkv) lkv "$args"; printf "\033[38;2;255;117;0m--- Returned to Interactive Mode ---\033[0m\n" ;;
                *)
                    LAST_RAW=$(_lk_write_logic "$CATEGORY_STRING" "$line")
                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    tail -n 3 "$FILENAME" | while IFS= read -r l; do
                        if [ "$l" = "$LAST_RAW" ]; then printf "\033[38;5;123m%s [NEW]\033[0m\n" "$l"; else printf "%s\n" "$l"; fi
                    done
                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    ;;
            esac
        fi
    done
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
    hs_time_input="$1"
    shift
    hs_summary_text="$*"
    _lk_get_time
    hs_target_dir="$LK_DIR/$YEAR/$MONTH"
    hs_filename="$hs_target_dir/$TODAY.md"
    hs_indent="    "

    mkdir -p "$hs_target_dir"
    if [ ! -f "$hs_filename" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$hs_filename"
        printf "%screated: [[%s]] - %s\n" "$hs_indent" "$TODAY" "$FULL_TIMESTAMP" >> "$hs_filename"
    fi

    case "$hs_time_input" in
        *-*)
            hs_start_raw=$(echo "$hs_time_input" | cut -d'-' -f1 | tr -cd '0-9')
            hs_end_raw=$(echo "$hs_time_input" | cut -d'-' -f2 | tr -cd '0-9')
            ;;
        *)
            hs_start_raw=$(echo "$hs_time_input" | tr -cd '0-9')
            hs_end_raw="$hs_start_raw"
            ;;
    esac

    hs_start=$(echo "$hs_start_raw" | sed 's/^0*//')
    hs_end=$(echo "$hs_end_raw" | sed 's/^0*//')
    [ -z "$hs_start" ] && hs_start=0
    [ -z "$hs_end" ] && hs_end=0

    hs_tmp_file=$(mktemp)
    hs_current=$hs_start
    while [ "$hs_current" -le "$hs_end" ]; do
        hs_fmt=$(printf "%02d:00" "$hs_current")
        hs_header="${hs_indent}- $hs_fmt - $hs_summary_text"
        sed '3,$ { /^'"${hs_indent}"'- '"$hs_fmt"' -/d; }' "$hs_filename" > "$hs_tmp_file" && mv "$hs_tmp_file" "$hs_filename"
        printf "%s\n" "$hs_header" >> "$hs_filename"
        hs_current=$((hs_current + 1))
    done

    head -n 2 "$hs_filename" > "$hs_tmp_file"
    sed '1,2d' "$hs_filename" | sort -b -k2,2 -u >> "$hs_tmp_file"
    mv "$hs_tmp_file" "$hs_filename"
    printf "\033[32mSummary updated & Sorted range %s-%s: \033[38;2;0;255;255m%s\033[0m\n" "$hs_start" "$hs_end" "$hs_summary_text"
    lkcs
}
