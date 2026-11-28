#!/bin/sh
# Module: lks (LogKlerk Search - Chronological & Real-time Stream)
# Optimized: Extreme Performance Native AWK Streamer, Space-Proof, Absolute Silent, UX Buffered

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
    lks_mode="fast" # Default behavior is pure speed (no sorting)

    while [ $# -gt 0 ]; do
        case "$1" in
            # --- EXECUTION MODES ---
            fast|oldest|newest|latest) 
                [ "$1" = "latest" ] && lks_mode="newest" || lks_mode="$1"
                shift ;;
            
            # --- TIME SCOPE FILTERS ---
            -t|-today) lks_today=$(date +%Y-%m-%d); lks_pattern="${lks_today}.md"; lks_msg_time="today ($lks_today)"; shift ;;
            -[0-2][0-9]) lks_hour=$(echo "$1" | tr -d '-'); shift ;;
            
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) 
                y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
                lks_pattern="$y-$m-$d.md"
                lks_msg_time="date $y-$m-$d"
                shift ;;
                
            [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) lks_pattern="$1.md"; lks_msg_time="date $1"; shift ;;
            
            [0-9][0-9][0-9][0-9][0-9][0-9])
                y="${1%??}"; m="${1#????}"
                lks_pattern="$y-$m-*.md"
                lks_msg_time="month $y-$m"
                shift ;;
                
            [0-9][0-9][0-9][0-9]-[0-1][0-9]) lks_pattern="$1-*.md"; lks_msg_time="month $1"; shift ;;
            
            [0-9][0-9][0-9][0-9]) lks_pattern="$1-*.md"; lks_msg_time="year $1"; shift ;;
            
            *) [ -z "$lks_kw" ] && lks_kw="$1" || lks_kw="$lks_kw $1"; shift ;;
        esac
    done

    if [ -z "$lks_kw" ]; then
        printf "\033[31m[Error]\033[0m Usage: lks [fast|oldest|newest|latest] [-t] [-HH] [YYYY-MM-DD | YYYYMMDD | YYYYMM] <keyword>\n"
        return 1
    fi

    lks_msg="Searching for '$lks_kw' in $lks_msg_time [Mode: $lks_mode]"
    [ -n "$lks_hour" ] && lks_msg="$lks_msg hour ${lks_hour}:xx"
    
    printf "%s--- %s ---%s\n" "$LK_ORANGE" "$lks_msg" "$LK_RESET"

    # --- ROUTER: DIRECT STREAM PIPELINE ---
    # Untuk memastikan buffer array bekerja dengan waktu kronologis yang benar,
    # baik mode oldest maupun newest harus disuplai dengan file yang sudah diurutkan (ASC).
    if [ "$lks_mode" = "fast" ]; then
        stream_cmd="find \"$LK_DIR\" -type f -name \"$lks_pattern\" 2>/dev/null"
    else
        stream_cmd="find \"$LK_DIR\" -type f -name \"$lks_pattern\" 2>/dev/null | sort"
    fi

    # --- THE NATIVE AWK STREAMER (Sub-shell Quarantined & UX Buffered) ---
    (
        export LC_ALL=C
        export LANG=C

        eval "$stream_cmd" | awk -v mode="$lks_mode" -v kw="$lks_kw" -v target_hr="$lks_hour" \
            -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" \
            -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
        BEGIN {
            IGNORECASE = 1;
            lower_kw = tolower(kw)
            file_count = 0
            match_count = 0
            res_idx = 0
        }
        
        {
            file = $0
            file_count++

            n = split(file, parts, "/")
            base = parts[n]
            date_str = substr(base, 1, 10) 
            
            while ((getline < file) > 0) {
                
                # --- 1. FILTERING TAHAP AWAL ---
                if (index(tolower($0), lower_kw) == 0) continue; 
                
                if (target_hr != "") {
                    if (index($0, "- " target_hr ":") == 0) continue; 
                }

                match_count++

                # --- 2. PERSIAPAN DATA ---
                raw_text = $0
                sub(/^[[:space:]]+/, "", raw_text)
                line = "[[" date_str "]] " raw_text
                colored_line = ""

                # --- 3. PEWARNAAN TEKS ---
                if (line ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - (## )?\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\]/) {
                    colored_line = amber line reset;
                }
                else if (line ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - (## )?[0-2][0-9]:00/) {
                    date_part = substr(line, 1, 14)
                    rest_part = substr(line, 16)
                    colored_line = amber date_part reset " " cyan rest_part reset;
                }
                else if (line ~ /^\[\[[0-9]{4}-[0-9]{2}-[0-9]{2}\]\] - [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - /) {
                    date_part = substr(line, 1, 14)  
                    ts_part = substr(line, 16, 13)   
                    rest_part = substr(line, 29)     

                    if (match(rest_part, /^\[\[.*\]\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        colored_line = amber date_part reset " " lime ts_part orange tag_part grey msg_part reset
                    } else if (match(rest_part, /^\[[a-zA-Z0-9._-]+\] >>/)) {
                        tag_part = substr(rest_part, 1, RLENGTH)
                        msg_part = substr(rest_part, RLENGTH + 1)
                        colored_line = amber date_part reset " " lime ts_part orange tag_part grey msg_part reset
                    } else {
                        colored_line = amber date_part reset " " lime ts_part grey rest_part reset
                    }
                }
                else {
                    date_part = substr(line, 1, 14)
                    rest_part = substr(line, 16)
                    colored_line = amber date_part reset " " grey rest_part reset
                }

                # --- 4. BUFFERING UX (Prompt-Anchoring) ---
                # Jika mode fast, cetak langsung secara sporadis untuk kecepatan maksimal.
                # Jika mode latest/oldest, simpan di RAM array untuk memanipulasi urutan akhir.
                if (mode == "fast") {
                    print colored_line
                } else {
                    res[++res_idx] = colored_line
                }
            }
            
            close(file)
        }
        
        END {
            if (file_count == 0) {
                print "No matching notes found."
            } else if (match_count == 0) {
                print "Keyword not found in the selected scope."
            } else if (mode != "fast") {
                # --- MEMUNTAHKAN BUFFER KE TERMINAL ---
                if (mode == "oldest") {
                    # REVERSE: Yang tertua ada di paling bawah
                    for (i = res_idx; i >= 1; i--) print res[i]
                } else {
                    # CHRONOLOGICAL: Yang terbaru ada di paling bawah
                    for (i = 1; i <= res_idx; i++) print res[i]
                }
            }
        }
        '
    ) 2>/dev/null
}
