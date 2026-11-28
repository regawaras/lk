#!/bin/sh
# Module: lksort (LogKlerk Sorter - Universal Table Analytics)
# Updated to v0.0.5: Dashboard Layout, Dynamic Tag Highlighting, Relative Mini Chart, & Strict Date Filter

lksort() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;200;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[38;2;150;150;150m')
    LK_PATH_GREY=$(printf '\033[38;2;85;85;85m')
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_ORANGE=$(printf '\033[38;2;225;102;0m')
    LK_MAGENTA=$(printf '\033[38;2;255;100;255m')
    LK_RED=$(printf '\033[31m')
    # =========================================================================

    # --- 2. Help Menu ---
    if [ $# -eq 0 ]; then
        printf "%s| LK Analytics --- Universal Dashboard Engine ---%s\n" "$LK_ORANGE" "$LK_RESET"
        printf "Usage: lksort [filter] [metric] [order]\n\n"
        printf "%s[filter]%s (Optional)\n" "$LK_CYAN" "$LK_RESET"
        printf "  YYYY       : Filter by year (e.g., 2026)\n"
        printf "  YYYYMM     : Filter by month (e.g., 202604)\n"
        printf "  YYYY-MM    : Filter by month (e.g., 2026-04)\n\n"
        printf "%s[metric]%s (Optional, Default: date)\n" "$LK_LIME" "$LK_RESET"
        printf "  date       : Sort by chronology\n"
        printf "  size       : Sort by file size\n"
        printf "  words      : Sort by word count\n"
        printf "  lines      : Sort by line count\n\n"
        printf "%s[order]%s  (Optional, Default: asc)\n" "$LK_AMBER" "$LK_RESET"
        printf "  asc        : Smallest/oldest to largest/newest\n"
        printf "  desc       : Largest/newest to smallest/oldest\n\n"
        printf "%sExamples:\n" "$LK_GREY"
        printf "  lksort 202604             -> Chronological dashboard for April 2026\n"
        printf "  lksort 2026 words desc  -> Highest word count files in 2026%s\n" "$LK_RESET"
        return 0
    fi

    # --- 3. Smart Argument Parsing (Time-Scope Filter) ---
    filter_dir="$LK_DIR"
    filter_label="All Notes"

    case "$1" in
        [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
            if [ "${#1}" -eq 6 ]; then
                y="${1%??}"
                m="${1#????}"
            else
                y="${1%-*}"
                m="${1#*-}"
            fi
            filter_dir="$LK_DIR/$y/$y-$m"
            filter_label="$y-$m"
            shift 
            ;;
        [0-9][0-9][0-9][0-9])
            y="$1"
            filter_dir="$LK_DIR/$y"
            filter_label="$y"
            shift
            ;;
    esac

    if [ ! -d "$filter_dir" ]; then
        printf "\033[31m[Error]\033[0m Data or directory for '\033[38;2;255;255;0m%s\033[0m' not found.\n" "$filter_label"
        return 1
    fi

    # --- 4. Parameter Resolution (Metric & Order) ---
    if [ -z "$1" ]; then
        metric="date"
        order="asc"
    else
        metric="$1"
        if [ -n "$2" ]; then
            order="$2"
        else
            order="asc"
        fi
    fi

    # --- 5. Determine Sorting Column Based on Metric ---
    case "$metric" in
        table|date)
            [ "$order" = "asc" ] && sort_flag="-k4,4" || sort_flag="-k4,4r"
            ;;
        lines)
            [ "$order" = "asc" ] && sort_flag="-n -k1,1" || sort_flag="-nr -k1,1"
            ;;
        words|wordcount)
            [ "$order" = "asc" ] && sort_flag="-n -k2,2" || sort_flag="-nr -k2,2"
            ;;
        size)
            [ "$order" = "asc" ] && sort_flag="-n -k3,3" || sort_flag="-nr -k3,3"
            ;;
        *)
            printf "\033[31m[Error]\033[0m Metric '%s' unknown. Type 'lksort' for help.\n" "$metric"
            return 1 ;;
    esac

    # --- TERMINAL WRAP PROTECTION ---
    tput rmam 2>/dev/null
    trap 'tput smam 2>/dev/null; trap - INT' INT

    printf "%s| LK Analytics Dashboard --- [%s] sorted by %s (%s) ---%s\n" "$LK_ORANGE" "$filter_label" "$metric" "$order" "$LK_RESET"

    # --- 6. Universal Analytics Engine + Array Buffering for Relative Chart ---
    # [PERBAIKAN] Strict pattern matching untuk memfilter folder notes (hanya ambil format YYYY-MM-DD.md)
    find "$filter_dir" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -exec wc {} + | grep -v " total$" | sort $sort_flag | \
    LC_ALL=C awk -v base="$LK_DIR/" -v reset="$LK_RESET" -v amber="$LK_AMBER" -v lime="$LK_LIME" -v cyan="$LK_CYAN" \
        -v grey="$LK_GREY" -v path_grey="$LK_PATH_GREY" -v orange="$LK_ORANGE" -v magenta="$LK_MAGENTA" -v red="$LK_RED" '
    BEGIN { max_words = 1 }
    
    function human(x) {
        if (x>=1073741824) {return sprintf("%5.1f GiB", x/1073741824)}
        if (x>=1048576) {return sprintf("%5.1f MiB", x/1048576)}
        if (x>=1024) {return sprintf("%5.1f KiB", x/1024)}
        return sprintf("%5d B  ", x)
    }
    
    # Pass 1: Baca ke Array & Temukan Word Count Tertinggi (Untuk Chart)
    {
        lines_arr[NR] = $1; words_arr[NR] = $2; bytes_arr[NR] = $3; paths_arr[NR] = $4;
        if ($2 > max_words) max_words = $2;
        total_items = NR;
    }
    
    # Pass 2: Rendering UI
    END {
        for (idx = 1; idx <= total_items; idx++) {
            lines = lines_arr[idx]; words = words_arr[idx]; bytes = bytes_arr[idx]; path = paths_arr[idx];
            
            n = split(path, a, "/"); filename = a[n]
            file_date = substr(filename, 1, 10);
            
            # --- EKSTRAKSI SUMMARY DARI FILE ---
            summary = ""
            while ((getline line < path) > 0) {
                if (line ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/) {
                    summary = line
                    sub(/^[[:space:]]*-[[:space:]]*#?[[:space:]]*\[\[[^\]]+\]\][[:space:]]*[-:]?[[:space:]]*/, "", summary)
                    break
                }
            }
            close(path)

            if (summary == "") summary = "[Summary Not Found/Not Yet Summarized]"
            sub(/[[:space:]]+$/, "", summary)

            # --- DYNAMIC PADDING & TAG SEGMENTATION (MAX 38 CHARS) ---
            max_len = 38
            txt_color = grey
            tag_str = ""
            tag_color = orange
            rest_str = summary
            colored_sum = ""

            if (summary ~ /^\[Anomaly/ || summary ~ /^\[Empty/ || summary ~ /^\(Empty/ || summary ~ /^\[Summary Not Found/) {
                txt_color = red
                colored_sum = txt_color summary reset
                raw_len = length(summary)
            } else {
                if (match(summary, /^!\[[^\]]+\]!/)) {
                    tag_str = substr(summary, RSTART, RLENGTH)
                    rest_str = substr(summary, RLENGTH + 1)
                    sub(/^[[:space:]]+/, "", rest_str)
                    if (tag_str == "![PLAN]!") tag_color = magenta
                }

                raw_len = length(tag_str) + (tag_str != "" ? 1 : 0) + length(rest_str)
                if (tag_str == "") raw_len = length(rest_str)

                if (raw_len > max_len) {
                    avail_len = max_len - length(tag_str) - (tag_str != "" ? 1 : 0)
                    if (avail_len < 3) {
                        raw_txt = substr((tag_str != "" ? tag_str " " rest_str : rest_str), 1, max_len - 3) "..."
                        tag_str = ""; rest_str = raw_txt
                        colored_sum = txt_color raw_txt reset
                        raw_len = length(raw_txt)
                    } else {
                        rest_str = substr(rest_str, 1, avail_len - 3) "..."
                        raw_len = max_len
                    }
                }

                if (tag_str != "") {
                    colored_sum = tag_color tag_str reset " " txt_color rest_str reset
                } else if (colored_sum == "") {
                    colored_sum = txt_color rest_str reset
                }
            }

            # Inject Spasi untuk Penyelarasan Kolom Summary
            pad_spaces = ""
            if (raw_len < max_len) {
                for (i = 0; i < (max_len - raw_len); i++) pad_spaces = pad_spaces " "
            }

            # --- MINI CHART GENERATOR (Relatif Terhadap max_words) ---
            chart_len = 8
            # Hitung rasio dan bulatkan. Jika ada kata tapi rasionya sangat kecil, beri minimal 1 bar.
            val = int((words / max_words) * chart_len + 0.5)
            if (val == 0 && words > 0) val = 1
            if (val > chart_len) val = chart_len
            
            chart = ""
            for (c = 1; c <= val; c++) chart = chart "■"
            for (c = val + 1; c <= chart_len; c++) chart = chart "·"

            # Clean path
            sub(base, "", path)
            
            # FORMAT: [Date] Summary | Chart | Words | Lines | Size | Path
            printf "%s%s%s %s%s %s│ %s%s%s │ %s%6d W%s │ %s%5d L%s │ %s%9s%s │ %s%s%s\n", \
                amber, file_date, reset, \
                colored_sum, pad_spaces, \
                grey, cyan, chart, grey, \
                cyan, words, reset, \
                lime, lines, reset, \
                lime, human(bytes), reset, \
                path_grey, path, reset
        }
    }' 2>/dev/null

    tput smam 2>/dev/null
    trap - INT
}
