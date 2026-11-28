#!/bin/sh
# Module: lkword (LogKlerk Keyword Frequency Mapper)
# Concept: Cognitive Hyper-Fixation Tracker (Lexical Cartography)
# Version: v0.0.8 (Uncapped Context Engine & Exact Day/Today Filtering)
# POSIX Strict Version (Dash & TTY 16-Color Compatible)

lkword() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.8}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;200;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[38;2;150;150;150m')
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_ORANGE=$(printf '\033[38;2;225;102;0m')
    LK_MAGENTA=$(printf '\033[38;2;255;100;255m')
    LK_RED=$(printf '\033[31m')
    # =========================================================================

    if [ $# -eq 0 ]; then
        printf "%s| LK Analytics --- Lexical Keyword Frequency ---%s\n" "$LK_ORANGE" "$LK_RESET"
        printf "Usage: lkword [time_scope] [metric] <keyword>\n\n"
        printf "%sTime Scope Examples:%s\n" "$LK_CYAN" "$LK_RESET"
        printf "  lkword nixos                 %s(Global Lifetime)%s\n" "$LK_GREY" "$LK_RESET"
        printf "  lkword date nixos            %s(Chronological Timeline)%s\n" "$LK_GREY" "$LK_RESET"
        printf "  lkword today context vi      %s(Context of 'vi' strictly for today)%s\n" "$LK_GREY" "$LK_RESET"
        printf "  lkword 2026-05-14 vi         %s(Stats for a specific day)%s\n" "$LK_GREY" "$LK_RESET"
        return 0
    fi

    # --- 2. Smart Argument & Range Parser ---
    lkw_scope_type="all"
    lkw_scope_val=""
    lkw_keyword=""
    lkw_label="Global Lifetime"
    lkw_metric="rank"

    for arg in "$@"; do
        case "$arg" in
            date|context)
                lkw_metric="$arg"
                ;;
            today)
                lkw_scope_type="day"
                lkw_scope_val=$(date +%Y-%m-%d)
                lkw_label="Today ($lkw_scope_val)"
                ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) # YYYY-MM-DD
                lkw_scope_type="day"
                lkw_scope_val="$arg"
                lkw_label="$arg"
                ;;
            [0-9][0-9][0-9][0-9]) # YYYY
                lkw_scope_type="year"
                lkw_scope_val="$arg"
                lkw_label="$arg"
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]) # YYYYMM
                lkw_scope_type="month"
                lkw_scope_val="${arg%??}-${arg#????}"
                lkw_label="${arg%??}-${arg#????}"
                ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9]) # YYYY-MM
                lkw_scope_type="month"
                lkw_scope_val="$arg"
                lkw_label="$arg"
                ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]) # YYYY-YYYY
                lkw_scope_type="year_range"
                lkw_scope_val="$arg"
                lkw_label="$arg"
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) # YYYYMM-YYYYMM
                lkw_scope_type="month_range"
                s_m="${arg%-*}"; e_m="${arg#*-}"
                s_m_fmt="${s_m%??}-${s_m#????}"; e_m_fmt="${e_m%??}-${e_m#????}"
                lkw_scope_val="${s_m_fmt}_${e_m_fmt}"
                lkw_label="${s_m_fmt} to ${e_m_fmt}"
                ;;
            *) # Keyword Catcher
                if [ -z "$lkw_keyword" ]; then
                    lkw_keyword="$arg"
                else
                    lkw_keyword="$lkw_keyword $arg"
                fi
                ;;
        esac
    done

    if [ -z "$lkw_keyword" ]; then
        printf "%b[Error]%b Keyword is required. See 'lkword' for help.\n" "$LK_RED" "$LK_RESET"
        return 1
    fi

    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Error]%b LK Vault not found.\n" "$LK_RED" "$LK_RESET"
        return 1
    fi

    # --- THE CONTEXT ENGINE (TRUTH TELLER) ---
    if [ "$lkw_metric" = "context" ]; then
        printf "%b--- Retrieving Exact Standalone Context for '%s' [%s]... ---%b\n" "$LK_CYAN" "$lkw_keyword" "$lkw_label" "$LK_RESET"
        
        # BUGFIX: Menghapus "tail -n 30" agar seluruh sejarah yang sesuai filter tercetak absolut
        find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" 2>/dev/null | sort | \
        LC_ALL=C awk -v kw="$lkw_keyword" -v stype="$lkw_scope_type" -v sval="$lkw_scope_val" '
        BEGIN {
            RESET="\033[0m"; AMBER="\033[38;2;255;200;0m"; GREY="\033[38;5;245m"; CYAN="\033[36m"; MAGENTA="\033[35m"
            target = tolower(kw)
        }
        {
            file = $0
            n = split(file, parts, "/")
            date_str = substr(parts[n], 1, 10)
            
            if (stype == "day" && date_str != sval) next
            if (stype == "year" && substr(date_str, 1, 4) != sval) next
            if (stype == "month" && substr(date_str, 1, 7) != sval) next
            if (stype == "year_range") { split(sval, r, "-"); y = substr(date_str, 1, 4) + 0; if (y < r[1]+0 || y > r[2]+0) next }
            if (stype == "month_range") { split(sval, r, "_"); m = substr(date_str, 1, 7); if (m < r[1] || m > r[2]) next }
            
            while ((getline l < file) > 0) {
                l_clean = tolower(l)
                gsub(/[^a-z0-9]/, " ", l_clean)
                nf = split(l_clean, w_arr, " ")
                
                is_match = 0
                for(i=1; i<=nf; i++) {
                    if (w_arr[i] == target) { is_match = 1; break; }
                }
                
                if (is_match) {
                    if (match(l, /^[[:space:]]*- [0-9]{2}:[0-9]{2}:[0-9]{2} - /)) {
                        ts = substr(l, RSTART+4, 8)
                        msg = substr(l, RSTART+RLENGTH)
                        printf "%s%s%s │ %s%s%s │ %s%s%s\n", AMBER, date_str, RESET, CYAN, ts, RESET, GREY, msg, RESET
                    }
                }
            }
            close(file)
        }'
        printf "%b------------------------------------------------------------------%b\n" "$LK_CYAN" "$LK_RESET"
        return 0
    fi

    # --- STANDARD MATRIX ENGINE (date / rank) ---
    printf "%s| LK Analytics --- Lexical Keyword Matrix [%s] ---%s\n" "$LK_ORANGE" "$lkw_label" "$LK_RESET"

    if [ "$lkw_metric" = "date" ]; then sort_flag="-k2,2"
    else sort_flag="-k1,1nr"; fi

    find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" 2>/dev/null | \
    LC_ALL=C awk -v kw="$lkw_keyword" -v stype="$lkw_scope_type" -v sval="$lkw_scope_val" '
    {
        file = $0
        n = split(file, a, "/")
        fname = a[n]
        date_str = substr(fname, 1, 10)
        
        if (stype == "day" && date_str != sval) next
        if (stype == "year" && substr(date_str, 1, 4) != sval) next
        if (stype == "month" && substr(date_str, 1, 7) != sval) next
        if (stype == "year_range") { split(sval, r, "-"); y = substr(date_str, 1, 4) + 0; if (y < r[1]+0 || y > r[2]+0) next }
        if (stype == "month_range") { split(sval, r, "_"); m = substr(date_str, 1, 7); if (m < r[1] || m > r[2]) next }
        
        target = tolower(kw)
        match_count = 0; total_words = 0; summary = ""
        
        while ((getline line < file) > 0) {
            if (summary == "" && line ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/) {
                summary = line
                sub(/^[[:space:]]*-[[:space:]]*#?[[:space:]]*\[\[[^\]]+\]\][[:space:]]*[-:]?[[:space:]]*/, "", summary)
            }
            line = tolower(line)
            gsub(/[^a-z0-9]/, " ", line)
            nf = split(line, w_arr, " ")
            total_words += nf
            
            for (i=1; i<=nf; i++) {
                if (w_arr[i] == target) match_count++
            }
        }
        close(file)
        if (summary == "") summary = "[No Summary]"
        sub(/[[:space:]]+$/, "", summary)
        
        if (match_count > 0) print match_count "|" date_str "|" total_words "|" summary
    }' | \
    sort -t'|' $sort_flag | \
    LC_ALL=C awk -F'|' -v kw="$lkw_keyword" -v metric="$lkw_metric" -v r="$LK_RESET" -v c="$LK_CYAN" -v l="$LK_LIME" -v a="$LK_AMBER" \
        -v g="$LK_GREY" -v o="$LK_ORANGE" -v m="$LK_MAGENTA" -v red="$LK_RED" '
    BEGIN {
        print "  " g "Keyword : \x27" kw "\x27" r
        if (metric == "date") print "  " g "Order   : Chronological Timeline" r
        else print "  " g "Order   : Frequency Ranking (Highest Frequency at the Bottom)" r
        print ""
        rank = 1; max_count = 0; total_hits = 0
    }
    {
        count = $1 + 0; date_str = $2; total_w = $3 + 0; summary = $4
        if (rank == 1 && metric != "date") max_count = count
        if (metric == "date" && count > max_count) max_count = count
        total_hits += count
        
        l_count[rank] = count; l_date[rank] = date_str; l_totalw[rank] = total_w; l_sum[rank] = summary
        rank++
    }
    END {
        total_ranks = rank - 1
        if (total_ranks == 0) { print "  \033[31m[No Matches]\033[0m Keyword \x27" kw "\x27 not found in this scope."; exit }

        for (idx = 1; idx <= total_ranks; idx++) {
            if (metric == "rank") i = total_ranks - idx + 1
            else i = idx

            count = l_count[i]; dt = l_date[i]; tw = l_totalw[i]; sm = l_sum[i]

            max_len = 38; txt_color = g; tag_str = ""; tag_color = o; rest_str = sm; colored_sum = ""

            if (sm ~ /^\[Anomaly/ || sm ~ /^\[No Sum/) {
                txt_color = red; colored_sum = txt_color sm r; raw_len = length(sm)
            } else {
                if (match(sm, /^!\[[^\]]+\]!/)) {
                    tag_str = substr(sm, RSTART, RLENGTH); rest_str = substr(sm, RLENGTH + 1)
                    sub(/^[[:space:]]+/, "", rest_str)
                    if (tag_str == "![PLAN]!") tag_color = m
                }
                raw_len = length(tag_str) + (tag_str != "" ? 1 : 0) + length(rest_str)
                if (tag_str == "") raw_len = length(rest_str)

                if (raw_len > max_len) {
                    avail_len = max_len - length(tag_str) - (tag_str != "" ? 1 : 0)
                    if (avail_len < 3) {
                        raw_txt = substr((tag_str != "" ? tag_str " " rest_str : rest_str), 1, max_len - 3) "..."
                        tag_str = ""; rest_str = raw_txt; colored_sum = txt_color raw_txt r; raw_len = length(raw_txt)
                    } else { rest_str = substr(rest_str, 1, avail_len - 3) "..."; raw_len = max_len }
                }
                if (tag_str != "") colored_sum = tag_color tag_str r " " txt_color rest_str r
                else if (colored_sum == "") colored_sum = txt_color rest_str r
            }

            pad_spaces = ""
            if (raw_len < max_len) { for (p = 0; p < (max_len - raw_len); p++) pad_spaces = pad_spaces " " }

            chart_len = 8
            filled = (max_count > 0) ? int((count / max_count) * chart_len + 0.5) : 0
            if (filled == 0 && count > 0) filled = 1
            if (filled > chart_len) filled = chart_len
            
            bar = ""
            for(b = 0; b < filled; b++) bar = bar "■"
            for(b = filled; b < chart_len; b++) bar = bar "·"

            printf " %s%s%s %s%s │ %s%s%s │ %s%4d%s uses │ %s%5d%s words\n", a, dt, r, colored_sum, pad_spaces, c, bar, r, o, count, r, l, tw, r
        }
        print "\n" o "  Total Accumulation: " c total_hits " mentions" r " across " c total_ranks " days." r
    }'
}
