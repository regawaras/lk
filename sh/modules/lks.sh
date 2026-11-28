#!/bin/sh
# Module: lks (LogKlerk Search - Chronological & Real-time Stream)

lks() {
    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;200;0m')       # Date [[YYYY-MM-DD]]
    LK_LIME=$(printf '\033[38;2;100;255;0m')        # Timestamps
    LK_GREY=$(printf '\033[38;2;150;150;150m')      # True Color Bright Grey (Fixed)
    LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Hourly Summary Time
    LK_ORANGE=$(printf '\033[38;2;225;102;0m')      # Tags Taxonomy & Header
    # =========================================================================

    lks_pattern="*.md"
    lks_hour=""
    lks_kw=""
    lks_msg_time="all notes"

    while [ $# -gt 0 ]; do
        case "$1" in
            -t|-today) lks_today=$(date +%Y-%m-%d); lks_pattern="${lks_today}.md"; lks_msg_time="today ($lks_today)"; shift ;;
            -[0-2][0-9]) lks_hour=$(echo "$1" | tr -d '-'); shift ;;
            
            # Catch 8-digit YYYYMMDD
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) 
                y="${1%????}"
                m_d="${1#????}"
                m="${m_d%??}"
                d="${m_d#??}"
                lks_pattern="$y-$m-$d.md"
                lks_msg_time="date $y-$m-$d"
                shift ;;
                
            # Catch standard YYYY-MM-DD
            [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) lks_pattern="$1.md"; lks_msg_time="date $1"; shift ;;
            
            # Catch 6-digit YYYYMM
            [0-9][0-9][0-9][0-9][0-9][0-9])
                y="${1%??}"
                m="${1#????}"
                lks_pattern="$y-$m-*.md"
                lks_msg_time="month $y-$m"
                shift ;;
                
            # Catch standard YYYY-MM
            [0-9][0-9][0-9][0-9]-[0-1][0-9]) lks_pattern="$1-*.md"; lks_msg_time="month $1"; shift ;;
            
            # Catch 4-digit YYYY
            [0-9][0-9][0-9][0-9]) lks_pattern="$1-*.md"; lks_msg_time="year $1"; shift ;;
            
            *) [ -z "$lks_kw" ] && lks_kw="$1" || lks_kw="$lks_kw $1"; shift ;;
        esac
    done

    if [ -z "$lks_kw" ]; then
        printf "\033[31m[Error]\033[0m Usage: lks [-t] [-HH] [YYYY-MM-DD | YYYYMMDD | YYYYMM] <keyword>\n"
        return 1
    fi

    lks_msg="Searching for '$lks_kw' in $lks_msg_time"
    [ -n "$lks_hour" ] && lks_msg="$lks_msg hour ${lks_hour}:xx"
    
    printf "%s--- %s ---%s\n" "$LK_ORANGE" "$lks_msg" "$LK_RESET"

    # --- STREAMING CHRONOLOGICAL ALGORITHM ---
    # 1. Cari dan urutkan DARI NAMA FILE terlebih dahulu, agar `sort` tidak memblokir output teks.
    lks_files=$(find "$LK_DIR" -type f -name "$lks_pattern" 2>/dev/null | sort)

    if [ -z "$lks_files" ]; then
        printf "No matching notes found.\n"
    else
        # 2. Grep dijalankan berurutan per file, memberikan animasi "membaca" dari atas ke bawah.
        for f in $lks_files; do
            grep -isH "$lks_kw" "$f"
        done | while IFS=: read -r file content; do
            if [ -n "$lks_hour" ]; then
                if ! echo "$content" | grep -q -- "-[[:space:]]${lks_hour}:[0-9]\{2\}:[0-9]\{2\}[[:space:]]-"; then continue; fi
            fi
            lks_date=$(basename "$file" .md)
            lks_clean=$(echo "$content" | sed 's/^[[:space:]]*//')
            
            # Print langsung ke AWK (Stream)
            printf "[[%s]] %s\n" "$lks_date" "$lks_clean"
            
        done | awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
        
        $0 ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - \[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\]/ {
            # Text: Daily Summary
            print amber $0 reset; next
        }
        $0 ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - [0-2][0-9]:00/ {
            # Text: Hourly Summary
            date_part = substr($0, 1, 14)
            rest_part = substr($0, 16)
            print amber date_part reset " " cyan rest_part reset; next
        }
        $0 ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
            # Text: Regular Log / Taxonomy Log
            date_part = substr($0, 1, 14)  # Get [[YYYY-MM-DD]]
            ts_part = substr($0, 16, 13)   # Get - HH:MM:SS - 
            rest_part = substr($0, 29)     # Get the rest of the text

            if (match(rest_part, /^\[\[.*\]\] >>/)) {
                tag_part = substr(rest_part, 1, RLENGTH)
                msg_part = substr(rest_part, RLENGTH + 1)
                print amber date_part reset " " lime ts_part orange tag_part grey msg_part reset
            } else if (match(rest_part, /^\[[a-zA-Z0-9._-]+\] >>/)) {
                tag_part = substr(rest_part, 1, RLENGTH)
                msg_part = substr(rest_part, RLENGTH + 1)
                print amber date_part reset " " lime ts_part orange tag_part grey msg_part reset
            } else {
                print amber date_part reset " " lime ts_part grey rest_part reset
            }
            next
        }
        {
            # Fallback for non-standard lines
            date_part = substr($0, 1, 14)
            rest_part = substr($0, 16)
            print amber date_part reset " " grey rest_part reset
        }
        '
    fi
}
