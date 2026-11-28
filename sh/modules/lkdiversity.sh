#!/bin/sh
# Module: lkdiversity (LogKlerk Lexical Richness & Entropy Ranker)
# Concept: Measures Type-Token Ratio (TTR) to determine Cognitive Expansion vs Cognitive Loops
# Updated to v0.0.6: Chronological Sorting (date) and Multi-Year/Range Filtering

lkdiversity() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.6}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    LK_RESET='\033[0m'
    LK_AMBER='\033[38;2;255;200;0m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_MAGENTA='\033[38;2;255;100;255m'
    LK_RED='\033[31m'
    # =========================================================================

    MIN_WORDS=50

    # --- 2. Smart Argument Parsing (Any Order) & Advanced Scope Filtering ---
    filter_label="Global Lifetime"
    lkm_metric="rttr"
    lkm_order="asc"
    
    # Kumpulkan semua jalur direktori yang akan dipindai
    scope_dirs=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            asc|desc)
                lkm_order="$1"
                ;;
            date|ttr|rttr|uniq)
                lkm_metric="$1"
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]--[0-9][0-9][0-9][0-9][0-9][0-9])
                # RANGING MONTHS (e.g. 202504--202512)
                y1="${1:0:4}"; m1="${1:4:2}"
                y2="${1:8:4}"; m2="${1:12:2}"
                filter_label="${y1}-${m1} to ${y2}-${m2}"
                # Loop sederhana untuk merangkai direktori (Hanya bekerja di sistem POSIX jika bash)
                # Lebih aman kita menggunakan find nanti, di sini kita tangkap labelnya
                scope_dirs="$scope_dirs RANGEMONTH:$1"
                ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]--[0-9][0-9][0-9][0-9])
                # RANGING YEARS (e.g. 2025-2026 or 2025--2026)
                y1="${1:0:4}"
                y2="${1:5:4}"
                filter_label="${y1} to ${y2}"
                scope_dirs="$scope_dirs RANGEYEAR:$1"
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
                # SINGLE MONTH (e.g. 202504 or 2025-04)
                if [ "${#1}" -eq 6 ]; then
                    y="${1%??}"; m="${1#????}"
                else
                    y="${1%-*}"; m="${1#*-}"
                fi
                scope_dirs="$scope_dirs ${LK_DIR}/$y/$y-$m"
                if [ "$filter_label" = "Global Lifetime" ]; then filter_label="$y-$m"
                else filter_label="${filter_label}, $y-$m"; fi
                ;;
            [0-9][0-9][0-9][0-9])
                # SINGLE YEAR (e.g. 2025)
                y="$1"
                scope_dirs="$scope_dirs ${LK_DIR}/$y"
                if [ "$filter_label" = "Global Lifetime" ]; then filter_label="$y"
                else filter_label="${filter_label}, $y"; fi
                ;;
            *)
                printf "%b[Error]%b Argument '%s' unknown.\n" "$LK_RED" "$LK_RESET" "$1"
                return 1
                ;;
        esac
        shift
    done

    # Jika tidak ada filter tanggal, default ke global
    if [ -z "$scope_dirs" ]; then
        scope_dirs="$LK_DIR"
    fi

    # Karena scope_dirs bisa rumit (berisi RANGEYEAR dll), kita bangun regex untuk perintah `find`
    # Ini adalah metode brutal tapi sangat kompatibel dengan sh/dash murni tanpa perlu bash sequence {1..10}
    find_cmd="find \"$LK_DIR\" -type f -name \"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md\""
    
    if echo "$scope_dirs" | grep -q "RANGE"; then
        # Jika ada ranging, kita gunakan AWK pass pertama untuk memfilter nama file absolutnya
        file_list=$(eval "$find_cmd" | LC_ALL=C awk -v rules="$scope_dirs" '
        BEGIN {
            n = split(rules, r_arr, " ")
            for(i=1; i<=n; i++) {
                if(r_arr[i] ~ /^RANGEYEAR:/) {
                    sub("RANGEYEAR:", "", r_arr[i])
                    y1 = substr(r_arr[i], 1, 4) + 0
                    y2 = substr(r_arr[i], length(r_arr[i])-3, 4) + 0
                    for(y=y1; y<=y2; y++) valid_years[y] = 1
                } else if(r_arr[i] ~ /^RANGEMONTH:/) {
                    sub("RANGEMONTH:", "", r_arr[i])
                    y1 = substr(r_arr[i], 1, 4) + 0; m1 = substr(r_arr[i], 5, 2) + 0
                    y2 = substr(r_arr[i], 9, 4) + 0; m2 = substr(r_arr[i], 13, 2) + 0
                    start_val = (y1 * 12) + m1
                    end_val = (y2 * 12) + m2
                    for(v=start_val; v<=end_val; v++) {
                        vy = int((v-1)/12)
                        vm = v - (vy*12)
                        if (vm < 10) vm_str = "0" vm; else vm_str = vm
                        valid_months[vy "-" vm_str] = 1
                    }
                }
            }
        }
        {
            file = $0
            nx = split(file, parts, "/")
            date_str = substr(parts[nx], 1, 10)
            y_str = substr(date_str, 1, 4) + 0
            ym_str = substr(date_str, 1, 7)
            
            if (rules ~ /RANGE/) {
                if ((y_str in valid_years) || (ym_str in valid_months)) { print file }
            } else {
                print file
            }
        }')
    else
        # Jika hanya folder tunggal (e.g., lkdiversity 2025)
        find_cmd="find $scope_dirs -type f -name \"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md\" 2>/dev/null"
        file_list=$(eval "$find_cmd")
    fi

    if [ -z "$file_list" ]; then
        printf "%b[Error]%b No data matching '%s' found.\n" "$LK_RED" "$LK_RESET" "$filter_label"
        return 1
    fi

    printf "%b| LK Analytics --- Lexical Diversity [%s] via %s (%s) ---%b\n" "$LK_ORANGE" "$filter_label" "$lkm_metric" "$lkm_order" "$LK_RESET"

    # Set sort flag based on metric
    if [ "$lkm_metric" = "date" ]; then
        # Sort based on file name (Date is field 2 in our pipe)
        if [ "$lkm_order" = "asc" ]; then sort_flag="-k2,2"; else sort_flag="-k2,2r"; fi
    else
        # Sort based on score
        if [ "$lkm_order" = "asc" ]; then sort_flag="-k1,1n"; else sort_flag="-k1,1nr"; fi
    fi

    # --- 3. Extract, Math & Buffered Render ---
    echo "$file_list" | \
    LC_ALL=C awk -v min="$MIN_WORDS" -v metric="$lkm_metric" '
    {
        file = $0
        total = 0
        uniq_count = 0
        delete uniq_arr
        
        while ((getline line < file) > 0) {
            gsub(/!\[[^\]]+\]!/, "", line)
            gsub(/\[\[[^\]]+\]\]/, "", line)
            gsub(/[^a-zA-Z0-9]/, " ", line)
            line = tolower(line)
            
            n = split(line, w_arr, " ")
            for (i = 1; i <= n; i++) {
                if (w_arr[i] != "") {
                    total++
                    if (!(w_arr[i] in uniq_arr)) {
                        uniq_arr[w_arr[i]] = 1
                        uniq_count++
                    }
                }
            }
        }
        close(file)
        
        if (total >= min) {
            ttr = (uniq_count / total) * 100
            rttr = uniq_count / sqrt(total)
            
            if (metric == "rttr") score = rttr
            else if (metric == "ttr") score = ttr
            else if (metric == "uniq") score = uniq_count
            else score = rttr # Default fallback for date

            # date sorting needs pure YYYY-MM-DD which is in the file name
            nx = split(file, fp, "/")
            date_str = substr(fp[nx], 1, 10)

            printf "%09.4f|%s|%d|%d|%.2f|%.2f\n", score, date_str, uniq_count, total, ttr, rttr
        }
    }' | \
    sort -t'|' $sort_flag | \
    LC_ALL=C awk -F'|' -v min="$MIN_WORDS" -v metric="$lkm_metric" -v order="$lkm_order" \
        -v r="$LK_RESET" -v c="$LK_CYAN" -v l="$LK_LIME" -v a="$LK_AMBER" \
        -v g="$LK_GREY" -v o="$LK_ORANGE" -v m="$LK_MAGENTA" '
    BEGIN {
        print "  " g "Filter : Min " min " words. Metric: " toupper(metric) r
        if (metric == "rttr") print "  " g "Desc   : Root TTR (Guiraud\x27s Index). Best balance of volume and diversity." r
        if (metric == "ttr") print "  " g "Desc   : Raw Type-Token Ratio. Favors extremely short, dense logs." r
        if (metric == "uniq") print "  " g "Desc   : Raw Unique Words. Favors extremely long logs." r
        if (metric == "date") print "  " g "Desc   : Chronological view of Cognitive Expansion." r
        print ""
        print "  " m "[■]" r " Ascended Range | " c "[■]" r " Healthy Range | " l "[■]" r " Focus Range | " o "[■]" r " Loop/Echo Chamber"
        print ""
        rank = 1
        max_score = 0
    }
    {
        score = $1 + 0; date_str = $2; uniq = $3; total = $4; ttr = $5; rttr = $6
        if (rank == 1 && metric != "date") max_score = score
        # For date metric, calculate an absolute max across the dataset to render charts relative to global max
        if (metric == "date") {
            abs_sc = rttr # Kita gunakan rttr sebagai patokan grafik jika mode date
            if (abs_sc > max_score) max_score = abs_sc
        }
    }
    # Pass kedua via memori untuk merender (karena kita butuh max_score untuk date mode)
    {
        lines_count++
        l_score[lines_count] = score
        l_date[lines_count] = date_str
        l_uniq[lines_count] = uniq
        l_total[lines_count] = total
        l_ttr[lines_count] = ttr
        l_rttr[lines_count] = rttr
    }
    END {
        for (i = 1; i <= lines_count; i++) {
            score = l_score[i]; date_str = l_date[i]; uniq = l_uniq[i]; total = l_total[i]; ttr = l_ttr[i]; rttr = l_rttr[i]
            
            if (rttr >= 25) color = m; else if (rttr >= 18) color = c; else if (rttr >= 12) color = l; else color = o
            
            chart_len = 10
            # Gunakan RTTR sebagai baseline grafik untuk semua mode agar adil
            filled = (max_score > 0) ? int((rttr / max_score) * chart_len + 0.5) : 0
            if (filled == 0 && rttr > 0) filled = 1
            if (filled > chart_len) filled = chart_len
            
            bar = ""
            for(b = 0; b < filled; b++) bar = bar "■"
            for(b = filled; b < chart_len; b++) bar = bar "·"
            
            # Format UI Matrix
            if (metric == "rttr" || metric == "date") { disp_score = sprintf("%5.2f", rttr); suffix = "Idx " }
            else if (metric == "ttr") { disp_score = sprintf("%5.2f", ttr); suffix = "%   " }
            else { disp_score = sprintf("%5d", uniq); suffix = "Wrds" }

            printf " %s%03d.%s %s[[%s]]%s │ %s[%s]%s %s%s %s%s │ %s%4d Uniq%s / %s%4d Totl%s │ %s(RTTR: %05.2f)%s\n", \
                g, i, r, a, date_str, r, color, bar, r, color, disp_score, suffix, r, c, uniq, r, g, total, r, g, rttr, r
        }
    }'
}
