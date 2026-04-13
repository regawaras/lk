# LogKlerk (LK) - A POSIX-compliant Daily Notes Terminal
# Compatible with dash, sh, bash, zsh

# --- Configuration & Paths ---
LK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/logklerk"
LK_CONFIG_FILE="$LK_CONFIG_DIR/lk.conf"
LK_TAGS_FILE="$LK_CONFIG_DIR/lk_tags"

# Default fallback directory
LK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk"

# Load persistent location config if exists
if [ -f "$LK_CONFIG_FILE" ]; then
    . "$LK_CONFIG_FILE"
fi

_lk_get_time() {
    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    CURRENT_HOUR=$(date +%H:00)
    FULL_TIMESTAMP=$(date +%H:%M:%S)
}

_lk_write_logic() {
    local CATEGORY="$1"
    local TEXT="$2"
    
    _lk_get_time
    
    local TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    local FILENAME="$TARGET_DIR/$TODAY.md"
    local LOCKFILE="$FILENAME.lock"
    local INDENT_4="    "
    local INDENT_8="        "
    
    mkdir -p "$TARGET_DIR"

    # I/O protection with file-locking (menggunakan FD 9 untuk dash compatibility)
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

_lk_interactive_mode() {
    local CATEGORY_STRING="$1"
    _lk_get_time
    local FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    
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
            
            local cmd="${line%% *}"
            local args="${line#* }"
            [ "$cmd" = "$args" ] && args=""

            case "$cmd" in
                -set)
                    local subcmd="${args%% *}"
                    local subargs="${args#* }"
                    [ "$subcmd" = "$subargs" ] && subargs=""

                    case "$subcmd" in
                        -today)
                            local today
                            today=$(date +%Y-%m-%d)
                            _lk_set_daily_summary "$today" "$subargs"
                            ;;
                        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                            _lk_set_daily_summary "$subcmd" "$subargs"
                            ;;
                        -dir)
                            local target_arg="$subargs"
                            local new_dir=""
                            if [ -z "$target_arg" ]; then
                                printf "\033[31mUsage: -set -dir <path | -home | -default>\033[0m\n"
                                continue
                            fi
                            case "$target_arg" in
                                -home) new_dir="$HOME/LogKlerk" ;;
                                -default) new_dir="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk" ;;
                                *) new_dir="$target_arg" ;;
                            esac
                            
                            mkdir -p "$LK_CONFIG_DIR"
                            echo "LK_DIR=\"$new_dir\"" > "$LK_CONFIG_FILE"
                            mkdir -p "$new_dir"
                            
                            printf "\033[32mDirectory changed to -> %s\033[0m\n" "$new_dir"
                            LK_DIR="$new_dir"
                            FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
                            ;;
                        *)
                            _lk_set_summary "$args"
                            ;;
                    esac
                    ;;
                -search|-s|lks) lks "$args" ;;
                -help|--help|-h|lkh) lkh ;;
                -exit|-q|-quit|exit|quit)
                    printf "\033[32mExiting LogKlerk interactive mode.\033[0m\n"
                    break
                    ;;
                
                clk) clk "$args" ;;
                clks) clks "$args" ;;
                clkh) clkh "$args" ;;
                vlk) 
                    vlk "$args" 
                    printf "\033[38;2;255;117;0m--- Returned to Interactive Mode ---\033[0m\n"
                    ;;
                *)
                    local LAST_RAW
                    LAST_RAW=$(_lk_write_logic "$CATEGORY_STRING" "$line")
                    
                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    tail -n 3 "$FILENAME" | while IFS= read -r l; do
                        if [ "$l" = "$LAST_RAW" ]; then
                           printf "\033[38;5;123m%s [NEW]\033[0m\n" "$l"
                        else
                            printf "%s\n" "$l"
                        fi
                    done
                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    ;;
            esac
        fi
    done
}

_lk_set_daily_summary() {
    local TARGET_DATE="$1"
    shift
    local SUMMARY_TEXT="$*"
    
    local YEAR="${TARGET_DATE%%-*}"
    local MONTH="${TARGET_DATE%-*}"
    local FULL_TIMESTAMP
    FULL_TIMESTAMP=$(date +%H:%M:%S)
    
    local TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    local FILENAME="$TARGET_DIR/$TARGET_DATE.md"
    
    mkdir -p "$TARGET_DIR"

    if [ ! -f "$FILENAME" ]; then
        printf -- "- [[%s]] - %s\n" "$TARGET_DATE" "$SUMMARY_TEXT" >> "$FILENAME"
        printf "    created: [[%s]] - %s\n" "$TARGET_DATE" "$FULL_TIMESTAMP" >> "$FILENAME"
    else
        local TMP_FILE
        TMP_FILE=$(mktemp)
        sed "1c\\
- [[$TARGET_DATE]] - $SUMMARY_TEXT
" "$FILENAME" > "$TMP_FILE" && mv "$TMP_FILE" "$FILENAME"
    fi
    printf "\033[32mDaily Summary updated (%s): \033[38;2;0;255;255m%s\033[0m\n" "$TARGET_DATE" "$SUMMARY_TEXT"
}

_lk_set_summary() {
    TIME_INPUT="$1"  # Hilangkan penggunaan 'local' untuk kompatibilitas POSIX murni
    shift
    SUMMARY_TEXT="$*"
    _lk_get_time
    
    TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    FILENAME="$TARGET_DIR/$TODAY.md"
    INDENT_4="    "

    mkdir -p "$TARGET_DIR"

    if [ ! -f "$FILENAME" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$FILENAME"
        printf "%screated: [[%s]] - %s\n" "$INDENT_4" "$TODAY" "$FULL_TIMESTAMP" >> "$FILENAME"
    fi

    # Strip nol di depan menggunakan parameter expansion bawaan shell (100% POSIX, lebih aman dari sed)
    START_H_RAW=$(echo "$TIME_INPUT" | cut -d'-' -f1 | tr -cd '0-9')
    END_H_RAW=$(echo "$TIME_INPUT" | cut -d'-' -f2 | tr -cd '0-9')
    
    # Force base-10 dengan menghapus leading zeros secara aman
    START_H=$(printf '%d' "${START_H_RAW:-0}" 2>/dev/null || echo 0)
    END_H=$(printf '%d' "${END_H_RAW:-$START_H}" 2>/dev/null || echo 0)

    TMP_FILE=$(mktemp)

    current_hour_idx=$START_H
    while [ "$current_hour_idx" -le "$END_H" ]; do
        HOUR_FORMAT=$(printf "%02d:00" "$current_hour_idx")
        NEW_HEADER="${INDENT_4}- $HOUR_FORMAT - $SUMMARY_TEXT"
        
        # Perbaikan SED: Gunakan kombinasi single quote untuk menghindari escape sequence dash
        sed '3,$ { /^'"${INDENT_4}"'- '"$HOUR_FORMAT"' -/d; }' "$FILENAME" > "$TMP_FILE" && mv "$TMP_FILE" "$FILENAME"
        
        printf "%s\n" "$NEW_HEADER" >> "$FILENAME"
        current_hour_idx=$((current_hour_idx + 1))
    done

    head -n 2 "$FILENAME" > "$TMP_FILE"
    sed '1,2d' "$FILENAME" | sort -b -k2,2 -u >> "$TMP_FILE"
    mv "$TMP_FILE" "$FILENAME"

    printf "\033[32mSummary updated & Sorted range %s-%s: \033[38;2;0;255;255m%s\033[0m\n" "$START_H" "$END_H" "$SUMMARY_TEXT"
    clks
}

vlk() { 
    case "$1" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            local TARGET_DATE="$1"
            local TARGET_YEAR="${TARGET_DATE%%-*}"
            local TARGET_MONTH="${TARGET_DATE%-*}"
            local TARGET_DIR="$LK_DIR/$TARGET_YEAR/$TARGET_MONTH"
            
            mkdir -p "$TARGET_DIR"
            ${EDITOR:-vim} "$TARGET_DIR/$TARGET_DATE.md"
            return 0
            ;;
        "")
            ;;
        *)
            printf "\033[31mInvalid date format. Use YYYY-MM-DD.\033[0m\n"
            return 1
            ;;
    esac

    _lk_get_time
    local TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    mkdir -p "$TARGET_DIR"
    ${EDITOR:-vim} "$TARGET_DIR/$TODAY.md"
}

clk() {
    _lk_get_time
    local FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    local INDENT_4="    "

    if [ -z "$1" ]; then
        if [ -f "$FILENAME" ]; then
            awk '
                $0 ~ /^[ ]{4}- [0-2][0-9]:00/ { print "\033[38;2;0;255;255m" $0 "\033[0m"; next }
                { print }
            ' "$FILENAME"
        else
            echo "File does not exist yet."
        fi
        return 0
    fi

    case "$1" in
        -a|-all|--all)
            printf "\033[38;2;255;117;0m--- All Daily Summaries ---\033[0m\n"
            find "$LK_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
            printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            return 0
            ;;
        -y|-year|--year)
            local TARGET_DIR="$LK_DIR/$YEAR"
            if [ -d "$TARGET_DIR" ]; then
                printf "\033[38;2;255;117;0m--- Daily Summaries (%s) ---\033[0m\n" "$YEAR"
                find "$TARGET_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
                printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            else
                printf "\033[31mDirectory %s not found.\033[0m\n" "$TARGET_DIR"
            fi
            return 0
            ;;
        -m|-month|--month)
            local TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
            if [ -d "$TARGET_DIR" ]; then
                printf "\033[38;2;255;117;0m--- Daily Summaries (%s) ---\033[0m\n" "$MONTH"
                find "$TARGET_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
                printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            else
                printf "\033[31mDirectory %s not found.\033[0m\n" "$TARGET_DIR"
            fi
            return 0
            ;;
        [0-9][0-9][0-9][0-9])
            local TARGET_DIR="$LK_DIR/$1"
            if [ -d "$TARGET_DIR" ]; then
                printf "\033[38;2;255;117;0m--- Daily Summaries (%s) ---\033[0m\n" "$1"
                find "$TARGET_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
                printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            else
                printf "\033[31mDirectory %s not found.\033[0m\n" "$TARGET_DIR"
            fi
            return 0
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9])
            local TARGET_YEAR="${1%%-*}"
            local TARGET_DIR="$LK_DIR/$TARGET_YEAR/$1"
            if [ -d "$TARGET_DIR" ]; then
                printf "\033[38;2;255;117;0m--- Daily Summaries (%s) ---\033[0m\n" "$1"
                find "$TARGET_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
                printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            else
                printf "\033[31mDirectory %s not found.\033[0m\n" "$TARGET_DIR"
            fi
            return 0
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            local TARGET_YEAR="${1%%-*}"
            local TARGET_MONTH="${1%-*}"
            local TARGET_FILE="$LK_DIR/$TARGET_YEAR/$TARGET_MONTH/$1.md"
            
            if [ -f "$TARGET_FILE" ]; then
                printf "\033[38;2;255;117;0m--- Daily Log (%s) ---\033[0m\n" "$1"
                awk '
                    $0 ~ /^[ ]{4}- [0-2][0-9]:00/ { print "\033[38;2;0;255;255m" $0 "\033[0m"; next }
                    { print }
                ' "$TARGET_FILE"
                printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
            else
                printf "\033[31mFile %s not found.\033[0m\n" "$TARGET_FILE"
            fi
            return 0
            ;;
    esac

    # HOURLY READ MODE
    if [ ! -f "$FILENAME" ]; then
        printf "File %s not found.\n" "$FILENAME"
        return 1
    fi

    case "$1" in
        *-*)
            local START_HOUR
            local END_HOUR
            START_HOUR=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9' | sed 's/^0*//')
            END_HOUR=$(echo "$1" | cut -d'-' -f2 | tr -cd '0-9' | sed 's/^0*//')
            [ -z "$START_HOUR" ] && START_HOUR=0
            [ -z "$END_HOUR" ] && END_HOUR=0
            
            local START_FMT
            local END_FMT
            START_FMT=$(printf "%02d:00" "$START_HOUR")
            END_FMT=$(printf "%02d:00" "$END_HOUR")

            printf "\033[38;2;255;117;0m--- Displaying Hour Range %s to %s (%s) ---\033[0m\n" "$START_FMT" "$END_FMT" "$TODAY"

            awk -v start="${INDENT_4}- $START_FMT" -v end_limit="${INDENT_4}- $END_FMT" '
                $0 ~ start {found=1}
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {
                    split($0, a, "- "); split(a[2], b, " ");
                    if (b[1] > substr(end_limit, 7)) { found=0 }
                }
                found {
                    if ($0 ~ /^[ ]{4}- [0-2][0-9]:00/) {
                        print "\033[38;2;0;255;255m" $0 "\033[0m"
                    } else {
                        print
                    }
                }
            ' "$FILENAME"
            ;;
        *)
            local HOUR_CLEAN
            HOUR_CLEAN=$(echo "$1" | tr -cd '0-9' | sed 's/^0*//')
            [ -z "$HOUR_CLEAN" ] && HOUR_CLEAN=0
            local HOUR_FORMAT
            HOUR_FORMAT=$(printf "%02d:00" "$HOUR_CLEAN")

            printf "\033[38;2;255;117;0m--- Displaying Hour Log %s (%s) ---\033[0m\n" "$HOUR_FORMAT" "$TODAY"

            awk -v target="${INDENT_4}- $HOUR_FORMAT" '
                $0 ~ target {
                    found=1;
                    print "\033[38;2;0;255;255m" $0 "\033[0m";
                    next
                }
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {found=0}
                found {print}
            ' "$FILENAME"
            ;;
    esac
    printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
}

clks() {
    _lk_get_time
    local FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    local INDENT_4="    "

    if [ ! -f "$FILENAME" ]; then
        printf "\033[31mFile %s not found.\033[0m\n" "$FILENAME"
        return 1
    fi

    printf "\033[38;2;255;117;0m--- Daily Hourly Summary (%s) ---\033[0m\n" "$TODAY"
    
    local DAILY_SUMMARY
    DAILY_SUMMARY=$(head -n 1 "$FILENAME")
    printf "\033[38;2;255;255;0m%s\033[0m\n" "$DAILY_SUMMARY"

    grep "\- [0-2][0-9]:00 " "$FILENAME" | sed 's/^[[:space:]]*//' | \
    awk '!seen[$2]++' | sort -k2,2 | while IFS= read -r line; do
        printf "\033[38;2;0;255;255m%s%s\033[0m\n" "$INDENT_4" "$line"
    done

    printf "\033[38;2;255;117;0m----------------------------------\033[0m\n"
}

clkh() {
    local CURRENT_HOUR
    CURRENT_HOUR=$(date +%H)
    clk "$CURRENT_HOUR"
}

lks() {
    local TARGET_PATTERN="*.md"
    local TARGET_HOUR=""
    local KEYWORD=""
    local SEARCH_MSG_TIME="all notes"

    while [ $# -gt 0 ]; do
        case "$1" in
            -t|-today)
                local today
                today=$(date +%Y-%m-%d)
                TARGET_PATTERN="${today}.md"
                SEARCH_MSG_TIME="today ($today)"
                shift
                ;;
            -[0-2][0-9])
                TARGET_HOUR=$(echo "$1" | tr -d '-')
                shift
                ;;
            [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9])
                TARGET_PATTERN="$1.md"
                SEARCH_MSG_TIME="date $1"
                shift
                ;;
            [0-9][0-9][0-9][0-9]-[0-1][0-9])
                TARGET_PATTERN="$1-*.md"
                SEARCH_MSG_TIME="month $1"
                shift
                ;;
            [0-9][0-9][0-9][0-9])
                TARGET_PATTERN="$1-*.md"
                SEARCH_MSG_TIME="year $1"
                shift
                ;;
            *)
                if [ -z "$KEYWORD" ]; then
                    KEYWORD="$1"
                else
                    KEYWORD="$KEYWORD $1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$KEYWORD" ]; then
        printf "\033[31mUsage: lks [-t|-today] [-HH] [YYYY-MM-DD | YYYY-MM | YYYY] <keyword>\033[0m\n"
        printf "Example: lks 2026-04 Linux\n"
        return 1
    fi

    local SEARCH_MSG="Searching for '$KEYWORD' in $SEARCH_MSG_TIME"
    [ -n "$TARGET_HOUR" ] && SEARCH_MSG="$SEARCH_MSG hour ${TARGET_HOUR}:xx"

    printf "\033[38;2;255;117;0m--- %s ---\033[0m\n" "$SEARCH_MSG"

    local GREP_CMD="grep -risH --include=\"$TARGET_PATTERN\" \"$KEYWORD\" \"$LK_DIR\""

    if ! eval "$GREP_CMD" > /dev/null 2>&1; then
        printf "No matching notes found.\n"
    else
        eval "$GREP_CMD" | while IFS=: read -r file content; do
            if [ -n "$TARGET_HOUR" ]; then
                if ! echo "$content" | grep -q -- "-[[:space:]]${TARGET_HOUR}:[0-9]\{2\}:[0-9]\{2\}[[:space:]]-"; then
                    continue
                fi
            fi

            date_str=$(basename "$file" .md)
            clean_content=$(echo "$content" | sed 's/^[[:space:]]*//')

            printf "\033[38;2;0;255;255m[%s]\033[0m %s\n" "$date_str" "$clean_content"
        done
    fi
    printf "\033[38;2;255;117;0m------------------------------------------------------------\033[0m\n"
}

# --- Core Global Taxonomy ---
lk() { _lk_helper "" "$@"; }
sog() { _lk_helper "[[Searching on Google]] >>" "$@"; }
todo() { _lk_helper "[[TODO]] >>" "$@"; }
ideas() { _lk_helper "[[IDEAS]] >>" "$@"; }
problems() { _lk_helper "[[Problems/Troubleshooting]] >>" "$@"; }

# Load external custom tags
if [ -f "$LK_TAGS_FILE" ]; then
    . "$LK_TAGS_FILE"
fi

lkh() {
    printf "\033[38;2;255;117;0m=== LogKlerk (LK) System Manual ===\033[0m\n"
    printf "\033[38;2;0;255;255mCore Commands:\033[0m\n"
    printf "  \033[1mlk [text]\033[0m               : Append a new log. If empty, enters Interactive Mode.\n"
    printf "  \033[1mlk -add alias \"Tag\"\033[0m     : Create a custom tag (e.g., lk -add wrv \"Writing on Vim\").\n"
    printf "  \033[1mlk -set -dir <path>\033[0m       : Change data directory (Options: -home, -default, or /custom/path).\n"
    printf "  \033[1mlk -set -today [text]\033[0m   : Set/update the Daily Summary at the top of today's file.\n"
    printf "  \033[1mlk -set YYYY-MM-DD [txt]\033[0m: Set/update the Daily Summary for a specific historical date.\n"
    printf "  \033[1mlk -set [HH] [text]\033[0m     : Set an Hourly Summary (e.g., 'lk -set 08-10 \"Deep Work\"').\n"
    printf "  \033[1mlk -search | -s\033[0m         : Unified search engine. Same as using 'lks' command.\n"
    printf "  \033[1mlk -help | -h\033[0m           : Show this manual.\n"
    printf "\n\033[38;2;0;255;255mReading, Editing & Display (clk & vlk):\033[0m\n"
    printf "  \033[1mclk\033[0m                   : Read all logs for today.\n"
    printf "  \033[1mclk -a | -all\033[0m         : Display ALL daily summaries across all time.\n"
    printf "  \033[1mclk -y | -year\033[0m        : Display daily summaries for the CURRENT year.\n"
    printf "  \033[1mclk -m | -month\033[0m       : Display daily summaries for the CURRENT month.\n"
    printf "  \033[1mclk YYYY-MM-DD\033[0m        : Display full logs for a specific date.\n"
    printf "  \033[1mclk [HH] | [HH-HH]\033[0m    : Display logs for a specific hour/range today.\n"
    printf "  \033[1mclks\033[0m                  : Display today's main Daily Summary & all Hourly Summaries.\n"
    printf "  \033[1mclkh\033[0m                  : Display all logs for the CURRENT hour.\n"
    printf "  \033[1mvlk\033[0m                   : Open TODAY's markdown file using \$EDITOR.\n"
    printf "\n\033[38;2;0;255;255mAdvanced Search Engine (lks / lk -s):\033[0m\n"
    printf "  \033[1mlks [keyword]\033[0m         : Recursive search across ALL files and time.\n"
    printf "  \033[1mlks -t [keyword]\033[0m      : Search only in TODAY's file.\n"
    printf "  \033[1mlks -[HH] [keyword]\033[0m   : Search across all days, but ONLY at a specific hour.\n"
    printf "  \033[1mlks YYYY-MM-DD [key]\033[0m  : Search only on a specific historical date.\n"
    printf "\n\033[38;2;0;255;255mGlobal Tags & Custom Tags:\033[0m\n"
    printf "  sog (Searching on Google), todo, ideas, problems.\n"
    printf "  Create your own using \033[1mlk -add\033[0m.\n"
    printf "\033[38;2;255;117;0m=========================================\033[0m\n"
}

alias clkm='clk -m'
