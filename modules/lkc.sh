# Modul: Chronological Reader (lkc)
lkc() {
    _lk_get_time
    lkc_filename="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    lkc_indent="    "

    if [ -z "$1" ]; then
        if [ -f "$lkc_filename" ]; then
            awk '$0 ~ /^[ ]{4}- [0-2][0-9]:00/ { print "\033[38;2;0;255;255m" $0 "\033[0m"; next } { print }' "$lkc_filename"
        else
            echo "File does not exist yet."
        fi
        return 0
    fi

    case "$1" in
        -a|-all|--all)
            printf "\033[38;2;255;117;0m--- All Daily Summaries ---\033[0m\n"
            find "$LK_DIR" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
            return 0 ;;
        -y|-year|--year)
            lkc_tdir="$LK_DIR/$YEAR"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
            return 0 ;;
        -m|-month|--month)
            lkc_tdir="$LK_DIR/$YEAR/$MONTH"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk 'FNR==1' {} + | sort
            return 0 ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            lkc_ty="${1%%-*}"; lkc_tm="${1%-*}"; lkc_tfile="$LK_DIR/$lkc_ty/$lkc_tm/$1.md"
            if [ -f "$lkc_tfile" ]; then
                printf "\033[38;2;255;117;0m--- Daily Log (%s) ---\033[0m\n" "$1"
                awk '$0 ~ /^[ ]{4}- [0-2][0-9]:00/ { print "\033[38;2;0;255;255m" $0 "\033[0m"; next } { print }' "$lkc_tfile"
            fi
            return 0 ;;
    esac

    [ ! -f "$lkc_filename" ] && return 1

    case "$1" in
        *-*)
            lkc_sh=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_sh" ] && lkc_sh=0
            lkc_eh=$(echo "$1" | cut -d'-' -f2 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_eh" ] && lkc_eh=0
            lkc_sfmt=$(printf "%02d:00" "$lkc_sh"); lkc_efmt=$(printf "%02d:00" "$lkc_eh")
            awk -v start="${lkc_indent}- $lkc_sfmt" -v end_limit="${lkc_indent}- $lkc_efmt" '
                $0 ~ start {found=1}
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ { split($0, a, "- "); split(a[2], b, " "); if (b[1] > substr(end_limit, 7)) found=0 }
                found { if ($0 ~ /^[ ]{4}- [0-2][0-9]:00/) print "\033[38;2;0;255;255m" $0 "\033[0m"; else print }
            ' "$lkc_filename"
            ;;
        *)
            lkc_h=$(echo "$1" | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_h" ] && lkc_h=0
            lkc_fmt=$(printf "%02d:00" "$lkc_h")
            awk -v target="${lkc_indent}- $lkc_fmt" '
                $0 ~ target { found=1; print "\033[38;2;0;255;255m" $0 "\033[0m"; next }
                found && $0 ~ /^[ ]{4}- [0-2][0-9]:00/ {found=0}
                found {print}
            ' "$lkc_filename"
            ;;
    esac
}

lkcd() {
    _lk_get_time
    lkcd_fn="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    [ ! -f "$lkcd_fn" ] && return 1
    printf "\033[38;2;255;117;0m--- Daily Hourly Summary (%s) ---\033[0m\n" "$TODAY"
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
