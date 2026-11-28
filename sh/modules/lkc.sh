#!/bin/sh
# Modul: Chronological Reader (lkc) - Standalone & Config-Aware

lkc() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    
    lkc_filename="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    lkc_indent="    "

    # --- 2. Universal TUI Color Parser ---
    # Mewarnai setiap string "- [[YYYY-MM-DD]]" menjadi kuning
    # Mewarnai setiap string "    - HH:00" menjadi cyan
    LKC_COLOR_AWK='
    $0 ~ /^- \[\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]\]/ {
        print "\033[38;2;255;255;0m" $0 "\033[0m"; next
    }
    $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {
        print "\033[38;2;0;255;255m" $0 "\033[0m"; next
    }
    { print }
    '

    # --- 3. Mode Eksekusi Tanpa Argumen (Hari Ini) ---
    if [ -z "$1" ]; then
        if [ -f "$lkc_filename" ]; then
            awk "$LKC_COLOR_AWK" "$lkc_filename"
        else
            echo "File does not exist yet."
        fi
        return 0
    fi

    # --- 4. Mode Filter Dinamis ---
    case "$1" in
        -a|-all|--all)
            printf "\033[38;2;255;117;0m--- All Daily Summaries ---\033[0m\n"
            find "$LK_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort | awk "$LKC_COLOR_AWK"
            return 0 ;;
        -y|-year|--year)
            lkc_tdir="$LK_DIR/$YEAR"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort | awk "$LKC_COLOR_AWK"
            return 0 ;;
        -m|-month|--month)
            lkc_tdir="$LK_DIR/$YEAR/$MONTH"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort | awk "$LKC_COLOR_AWK"
            return 0 ;;
        
        # --- Ekstraksi Tanggal Spesifik (Mendukung YYYYMMDD atau YYYY-MM-DD) ---
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            if [ "${#1}" -eq 8 ]; then
                y="${1%????}"
                m_d="${1#????}"
                m="${m_d%??}"
                d="${m_d#??}"
                target_date="$y-$m-$d"
            else
                target_date="$1"
            fi
            
            lkc_ty="${target_date%%-*}"
            lkc_tm="${target_date%-*}"
            lkc_tfile="$LK_DIR/$lkc_ty/$lkc_tm/$target_date.md"
            
            if [ -f "$lkc_tfile" ]; then
                printf "\033[38;2;255;117;0m--- Daily Log (%s) ---\033[0m\n" "$target_date"
                awk "$LKC_COLOR_AWK" "$lkc_tfile"
            else
                echo "File does not exist yet: $lkc_tfile"
            fi
            return 0 ;;
    esac

    # Cek eksistensi file jika menggunakan filter pencarian jam
    [ ! -f "$lkc_filename" ] && return 1

    # --- 5. Mode Filter Jam (Range atau Satuan) ---
    case "$1" in
        *-*)
            lkc_sh=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_sh" ] && lkc_sh=0
            lkc_eh=$(echo "$1" | cut -d'-' -f2 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_eh" ] && lkc_eh=0
            lkc_sfmt=$(printf "%02d:00" "$lkc_sh"); lkc_efmt=$(printf "%02d:00" "$lkc_eh")
            
            awk -v start="${lkc_indent}- $lkc_sfmt" -v end_limit="${lkc_indent}- $lkc_efmt" '
                $0 ~ start {found=1}
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ { split($0, a, "- "); split(a[2], b, " "); if (b[1] > substr(end_limit, 7)) found=0 }
                found { 
                    if ($0 ~ /^- \[\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]\]/) print "\033[38;2;255;255;0m" $0 "\033[0m"
                    else if ($0 ~ /^[ ]{4}- [0-2][0-9]:00/) print "\033[38;2;0;255;255m" $0 "\033[0m"
                    else print 
                }
            ' "$lkc_filename"
            ;;
        *)
            lkc_h=$(echo "$1" | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_h" ] && lkc_h=0
            lkc_fmt=$(printf "%02d:00" "$lkc_h")
            
            awk -v target="${lkc_indent}- $lkc_fmt" '
                $0 ~ target { found=1; print "\033[38;2;0;255;255m" $0 "\033[0m"; next }
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {found=0}
                found {
                    if ($0 ~ /^- \[\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]\]/) print "\033[38;2;255;255;0m" $0 "\033[0m"
                    else if ($0 ~ /^[ ]{4}- [0-2][0-9]:00/) print "\033[38;2;0;255;255m" $0 "\033[0m"
                    else print
                }
            ' "$lkc_filename"
            ;;
    esac
}

lkcd() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    
    lkcd_fn="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    [ ! -f "$lkcd_fn" ] && return 1
    
    printf "\033[38;2;255;117;0m--- Daily Summary (%s) ---\033[0m\n" "$TODAY"
    
    # Baris 1 otomatis terwarna kuning
    head -n 1 "$lkcd_fn" | awk '{print "\033[38;2;255;255;0m" $0 "\033[0m"}'
    
    grep "\- [0-2][0-9]:00 " "$lkcd_fn" | sed 's/^[[:space:]]*//' | awk '!seen[$2]++' | sort -k2,2 | while IFS= read -r line; do
        printf "\033[38;2;0;255;255m    %s\033[0m\n" "$line"
    done
    printf "\033[38;2;255;117;0m----------------------------------\033[0m\n"
}

lkch() {
    lkch_curr=$(date +%H)
    lkc "$lkch_curr"
}
