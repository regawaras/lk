# LK Search Modules (lks)
lks() {
    lks_pattern="*.md"
    lks_hour=""
    lks_kw=""
    lks_msg_time="all notes"

    while [ $# -gt 0 ]; do
        case "$1" in
            -t|-today) lks_today=$(date +%Y-%m-%d); lks_pattern="${lks_today}.md"; lks_msg_time="today ($lks_today)"; shift ;;
            -[0-2][0-9]) lks_hour=$(echo "$1" | tr -d '-'); shift ;;
            [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) lks_pattern="$1.md"; lks_msg_time="date $1"; shift ;;
            [0-9][0-9][0-9][0-9]-[0-1][0-9]) lks_pattern="$1-*.md"; lks_msg_time="month $1"; shift ;;
            [0-9][0-9][0-9][0-9]) lks_pattern="$1-*.md"; lks_msg_time="year $1"; shift ;;
            *) [ -z "$lks_kw" ] && lks_kw="$1" || lks_kw="$lks_kw $1"; shift ;;
        esac
    done

    if [ -z "$lks_kw" ]; then
        printf "\033[31mUsage: lks [-t|-today] [-HH] [YYYY-MM-DD | YYYY-MM | YYYY] <keyword>\033[0m\n"
        return 1
    fi

    lks_msg="Searching for '$lks_kw' in $lks_msg_time"
    [ -n "$lks_hour" ] && lks_msg="$lks_msg hour ${lks_hour}:xx"
    printf "\033[38;2;255;117;0m--- %s ---\033[0m\n" "$lks_msg"

    lks_cmd="grep -risH --include=\"$lks_pattern\" \"$lks_kw\" \"$LK_DIR\""
    if ! eval "$lks_cmd" > /dev/null 2>&1; then
        printf "No matching notes found.\n"
    else
        eval "$lks_cmd" | while IFS=: read -r file content; do
            if [ -n "$lks_hour" ]; then
                if ! echo "$content" | grep -q -- "-[[:space:]]${lks_hour}:[0-9]\{2\}:[0-9]\{2\}[[:space:]]-"; then continue; fi
            fi
            lks_date=$(basename "$file" .md)
            lks_clean=$(echo "$content" | sed 's/^[[:space:]]*//')
            printf "\033[38;2;0;255;255m[%s]\033[0m %s\n" "$lks_date" "$lks_clean"
        done
    fi
}
