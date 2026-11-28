#!/bin/sh
# Module: lkvoid (LogKlerk Temporal Silence & Void Cartography)
# Updated to v0.0.2: Filter Single-Log Anomalies, Fix Math, Ascending Order

lkvoid() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2-void}"
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
    LK_DARK=$(printf '\033[38;2;70;70;70m')
    # =========================================================================

    filter_dir="$LK_DIR"
    filter_label="Global Lifetime"

    if [ -n "$1" ]; then
        case "$1" in
            [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
                y="${1%-*}"; m="${1#*-}"; [ "${#1}" -eq 6 ] && { y="${1%??}"; m="${1#????}"; }
                filter_dir="$LK_DIR/$y/$y-$m"
                filter_label="$y-$m"
                ;;
            [0-9][0-9][0-9][0-9])
                y="$1"; filter_dir="$LK_DIR/$y"; filter_label="$y"
                ;;
        esac
    fi

    if [ ! -d "$filter_dir" ]; then
        printf "%b[Error]%b Data for '%s' not found.\n" "$LK_RED" "$LK_RESET" "$filter_label"
        return 1
    fi

    printf "%s| LK Analytics --- The Void Cartography [%s] ---%s\n" "$LK_MAGENTA" "$filter_label" "$LK_RESET"

    # --- 2. Temporal Math Engine ---
    find "$filter_dir" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" | \
    LC_ALL=C awk '
    {
        file = $0
        prev_time = -1
        max_gap = 0
        total_gap = 0
        gap_count = 0
        
        while ((getline line < file) > 0) {
            # Harus mencari exact timestamp (bukan judul jam "## 08:00")
            if (match(line, /^[[:space:]]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] -/)) {
                t_str = substr(line, RSTART, RLENGTH)
                match(t_str, /[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/)
                clean_time = substr(t_str, RSTART, RLENGTH)
                
                split(clean_time, t, ":")
                
                curr_time = (t[1] * 3600) + (t[2] * 60) + (t[3] + 0)
                
                if (prev_time != -1) {
                    # Cek jika waktu mundur (kemungkinan log diedit manual out-of-order), abaikan hitungan gap-nya
                    if (curr_time >= prev_time) {
                        gap = curr_time - prev_time
                        if (gap > max_gap) max_gap = gap
                        total_gap += gap
                        gap_count++
                    }
                }
                prev_time = curr_time
            }
        }
        close(file)
        
        # HANYA proses jika ada lebih dari 1 timestamp di hari tersebut (gap_count > 0)
        # Ini akan otomatis mengabaikan tahun 2022/2023 yang isinya hanya Daily Summary
        if (gap_count > 0) {
            printf "%d|%s|%d|%d\n", max_gap, file, total_gap, gap_count
        }
    }' | \
    # Sort Ascending: Terkecil (Paling Padat) ada di atas, Terbesar (Void Terdalam) di bawah
    sort -t'|' -k1,1n | \
    LC_ALL=C awk -F'|' -v r="$LK_RESET" -v c="$LK_CYAN" -v l="$LK_LIME" -v a="$LK_AMBER" \
        -v g="$LK_GREY" -v o="$LK_ORANGE" -v m="$LK_MAGENTA" -v d="$LK_DARK" '
    BEGIN {
        print "  " g "Desc   : Measures the longest temporal silence (The Void) in each log." r
        print "  " g "Note   : Excludes legacy logs with only 1 timestamp (Daily Summaries)." r
        print "  " m "Top Ranks" r "    : Days with massive uninterrupted silence (Sleep/Dissociation)."
        print "  " l "Bottom Ranks" r " : Days with hyper-continuous cognitive flow."
        print ""
        rank = 1
        max_void = 0
    }
    
    function fmt_time(sec,   h, min, s) {
        h = int(sec / 3600); sec = sec % 3600
        min = int(sec / 60); s = sec % 60
        if (h > 0) return sprintf("%02dh %02dm", h, min)
        if (min > 0) return sprintf("%02dm %02ds", min, s)
        return sprintf("    %02ds", s)
    }

    {
        gap_sec = $1 + 0; path = $2; total_sec = $3 + 0; count = $4 + 0
        
        # Karena di-sort ASC, nilai max_void ada di baris paling akhir. Kita simpan di array dulu.
        lines_gap[rank] = gap_sec
        lines_path[rank] = path
        lines_tot[rank] = total_sec
        lines_cnt[rank] = count
        
        rank++
    }
    END {
        total_ranks = rank - 1
        if (total_ranks == 0) exit
        
        # Nilai gap terbesar sekarang ada di index terakhir
        max_void = lines_gap[total_ranks]
        
        # Kita cetak dengan loop mundur agar Rank 01 (Void Terkecil) dicetak di paling bawah!
        # Dan Rank terbawah (Void Terdalam) dicetak di atas.
        for (i = total_ranks; i >= 1; i--) {
            gap_sec = lines_gap[i]
            total_sec = lines_tot[i]
            count = lines_cnt[i]
            path = lines_path[i]
            
            avg_sec = int(total_sec / count)
            
            n = split(path, arr, "/")
            date_str = substr(arr[n], 1, 10)
            
            if (gap_sec >= 28800) color = m
            else if (gap_sec >= 14400) color = o
            else if (gap_sec >= 7200) color = a
            else color = l
            
            chart_len = 10
            filled = (max_void > 0) ? int((gap_sec / max_void) * chart_len + 0.5) : 0
            if (filled == 0 && gap_sec > 0) filled = 1
            if (filled > chart_len) filled = chart_len
            
            bar = ""
            for(b = 0; b < filled; b++) bar = bar "■"
            for(b = filled; b < chart_len; b++) bar = bar "·"
            
            printf " %s%03d.%s %s%s%s │ %s[%s]%s %s Deepest Void: %-7s%s │ %s(Avg Velocity: %-7s / log)%s\n", \
                g, i, r, a, date_str, r, color, bar, r, color, fmt_time(gap_sec), r, g, fmt_time(avg_sec), r
        }
    }'
}
