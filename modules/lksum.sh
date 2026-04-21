#!/bin/sh
# Module: lksum (LogKlerk Summarizer - Daily & Hourly Context)

lksum() {
    # Validasi input minimum
    if [ $# -lt 2 ]; then
        printf "\033[31mUsage: lksum <time_target> <summary_text>\033[0m\n"
        printf "Examples:\n"
        printf "  lksum 15 aktivitas jam 15\n"
        printf "  lksum 15-18 aktivitas dari jam 15-17 sama semua\n"
        printf "  lksum -t summary aktivitas tanggal ini\n"
        printf "  lksum 20260430 summary aktivitas tanggal tersebut\n"
        printf "  lksum 20260430-14 summary jam 14 di tanggal tersebut\n"
        return 1
    fi

    lks_arg1="$1"
    shift
    lks_text="$*"

    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # --- 2. Initial Variables & Time Defaults ---
    curr_date=$(date +%Y-%m-%d)
    curr_time=$(date +%H:%M:%S)
    
    target_date="$curr_date"
    mode="hourly"
    target_hours=""

    # --- 3. Argument Parser (Regex-like Matching) ---
    case "$lks_arg1" in
        -t|today|-today)
            mode="daily"
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
            # Format: 20260430 (Mode: Daily)
            y=$(echo "$lks_arg1" | cut -c1-4)
            m=$(echo "$lks_arg1" | cut -c5-6)
            d=$(echo "$lks_arg1" | cut -c7-8)
            target_date="$y-$m-$d"
            mode="daily"
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9]*)
            # Format: 20260430-14 atau 20260430-14-16 (Mode: Hourly)
            y=$(echo "$lks_arg1" | cut -c1-4)
            m=$(echo "$lks_arg1" | cut -c5-6)
            d=$(echo "$lks_arg1" | cut -c7-8)
            target_date="$y-$m-$d"
            target_hours=$(echo "$lks_arg1" | cut -d'-' -f2-)
            mode="hourly"
            ;;
        *)
            # Format: 15 atau 15-18 (Mode: Hourly pada hari ini)
            target_hours="$lks_arg1"
            mode="hourly"
            ;;
    esac

    # Path Setup
    t_year="${target_date%%-*}"
    t_month="${target_date%-*}"
    t_dir="$LK_DIR/$t_year/$t_month"
    t_file="$t_dir/$target_date${LK_DEFAULT_FORMAT}"
    indent="    "

    mkdir -p "$t_dir"

    # --- 4. EKSEKUSI: DAILY SUMMARY (-t atau 20260430) ---
    if [ "$mode" = "daily" ]; then
        if [ ! -f "$t_file" ]; then
            printf -- "- [[%s]] - %s\n" "$target_date" "$lks_text" > "$t_file"
            printf "%screated: [[%s]] - %s\n" "$indent" "$target_date" "$curr_time" >> "$t_file"
        else
            tmp_file=$(mktemp)
            # POSIX compliance `sed`: Mengganti baris ke-1 secara aman
            sed "1c\\
- [[$target_date]] - $lks_text
" "$t_file" > "$tmp_file" && mv "$tmp_file" "$t_file"
        fi
        printf "\033[32mDaily Summary updated (%s):\n \033[38;2;0;255;255m%s\033[0m\n" "$target_date" "$lks_text"
        return 0
    fi

    # --- 5. EKSEKUSI: HOURLY SUMMARY (15, 15-18, atau 20260430-14) ---
    
    # Buat header harian standar jika file belum ada
    if [ ! -f "$t_file" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$target_date" > "$t_file"
        printf "%screated: [[%s]] - %s\n" "$indent" "$target_date" "$curr_time" >> "$t_file"
    fi

    # Parse jam start dan jam end (mengabaikan leading zero agar operasi matematis valid)
    start_raw=$(echo "$target_hours" | cut -d'-' -f1 | tr -cd '0-9')
    end_raw=$(echo "$target_hours" | cut -d'-' -f2 | tr -cd '0-9')
    [ -z "$end_raw" ] && end_raw="$start_raw"

    start_h=$(echo "$start_raw" | sed 's/^0*//'); [ -z "$start_h" ] && start_h=0
    end_h=$(echo "$end_raw" | sed 's/^0*//'); [ -z "$end_h" ] && end_h=0

    tmp_file=$(mktemp)
    curr_h="$start_h"
    
    # Looping berdasarkan jangkauan jam (contoh: dari 15 ke 18)
    while [ "$curr_h" -le "$end_h" ]; do
        fmt_h=$(printf "%02d:00" "$curr_h")
        header_line="${indent}- $fmt_h - $lks_text"
        
        # Hapus hourly summary lama (jika ada) khusus untuk jam bersangkutan dari baris 3 ke bawah
        sed "3,\$ { /^${indent}- ${fmt_h} -/d; }" "$t_file" > "$tmp_file" && mv "$tmp_file" "$t_file"
        
        # Tambahkan hourly summary yang baru ke baris paling bawah
        printf "%s\n" "$header_line" >> "$t_file"
        
        curr_h=$((curr_h + 1))
    done

    # --- 6. CHRONOLOGICAL SORTER (Bugfix) ---
    # Memisahkan Header (Baris 1 & 2) lalu mensortir isinya berdasarkan Waktu (Kolom 2)
    # Sort -k2,2 memastikan "15:00" selalu berada tepat DI ATAS "15:10:00"
    head -n 2 "$t_file" > "$tmp_file"
    sed '1,2d' "$t_file" | sort -b -k2,2 -u >> "$tmp_file"
    mv "$tmp_file" "$t_file"

    # Feedback ke Terminal
    if [ "$start_h" = "$end_h" ]; then
        printf "\033[32mHourly Summary updated (%02d:00): \033[38;2;0;255;255m%s\033[0m\n" "$start_h" "$lks_text"
    else
        printf "\033[32mHourly Summary updated (%02d:00-%02d:00): \033[38;2;0;255;255m%s\033[0m\n" "$start_h" "$end_h" "$lks_text"
    fi
}
