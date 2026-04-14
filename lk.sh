# LogKlerk (LK) - A POSIX-compliant Daily Notes Terminal
# Compatible with dash, sh, bash, zsh

# --- Configuration & Paths ---
# LogKlerk (LK) - Core Dispatcher
LK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lk"
LK_CONFIG_FILE="$LK_CONFIG_DIR/lk.conf"
LK_MODULES_DIR="$LK_CONFIG_DIR/modules"
LK_TAXONOMY_FILE="$LK_CONFIG_DIR/taxonomy.sh"

LK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk"

if [ -f "$LK_CONFIG_FILE" ]; then
    . "$LK_CONFIG_FILE"
fi

if [ -d "$LK_MODULES_DIR" ]; then
    for mod_file in "$LK_MODULES_DIR"/*.sh; do
        [ -f "$mod_file" ] && . "$mod_file"
    done
fi

if [ -f "$LK_TAXONOMY_FILE" ]; then
    . "$LK_TAXONOMY_FILE"
fi

_lk_get_time() {
    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    CURRENT_HOUR=$(date +%H:00)
    FULL_TIMESTAMP=$(date +%H:%M:%S)
}

_lk_set_daily_summary() {
    ds_target_date="$1"
    shift
    ds_summary_text="$*"
    ds_year="${ds_target_date%%-*}"
    ds_month="${ds_target_date%-*}"
    ds_full_ts=$(date +%H:%M:%S)
    ds_target_dir="$LK_DIR/$ds_year/$ds_month"
    ds_filename="$ds_target_dir/$ds_target_date.md"
    
    mkdir -p "$ds_target_dir"
    if [ ! -f "$ds_filename" ]; then
        printf -- "- [[%s]] - %s\n" "$ds_target_date" "$ds_summary_text" >> "$ds_filename"
        printf "    created: [[%s]] - %s\n" "$ds_target_date" "$ds_full_ts" >> "$ds_filename"
    else
        ds_tmp_file=$(mktemp)
        sed "1c\\
- [[$ds_target_date]] - $ds_summary_text
" "$ds_filename" > "$ds_tmp_file" && mv "$ds_tmp_file" "$ds_filename"
    fi
    printf "\033[32mDaily Summary updated (%s): \033[38;2;0;255;255m%s\033[0m\n" "$ds_target_date" "$ds_summary_text"
}

_lk_set_summary() {
    # Menggunakan prefix 'lksv_' (LogKlerk Summary Variable) untuk simulasi scope
    lksv_time_input="$1"
    shift
    lksv_summary_text="$*"
    
    _lk_get_time
    lksv_target_dir="$LK_DIR/$YEAR/$MONTH"
    lksv_filename="$lksv_target_dir/$TODAY.md"
    lksv_indent="    "

    mkdir -p "$lksv_target_dir"
    if [ ! -f "$lksv_filename" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$lksv_filename"
        printf "%screated: [[%s]] - %s\n" "$lksv_indent" "$TODAY" "$FULL_TIMESTAMP" >> "$lksv_filename"
    fi

    # POSIX-compliant parsing: Memastikan hanya jam yang diproses
    case "$lksv_time_input" in
        *-*)
            lksv_start_raw=$(echo "$lksv_time_input" | cut -d'-' -f1 | tr -cd '0-9')
            lksv_end_raw=$(echo "$lksv_time_input" | cut -d'-' -f2 | tr -cd '0-9')
            ;;
        *)
            lksv_start_raw=$(echo "$lksv_time_input" | tr -cd '0-9')
            lksv_end_raw="$lksv_start_raw"
            ;;
    esac

    # Menghapus leading zero tanpa sed (lebih cepat di POSIX)
    lksv_start=$(echo "$lksv_start_raw" | sed 's/^0*//'); [ -z "$lksv_start" ] && lksv_start=0
    lksv_end=$(echo "$lksv_end_raw" | sed 's/^0*//'); [ -z "$lksv_end" ] && lksv_end=0

    lksv_tmp_file=$(mktemp)
    lksv_current="$lksv_start"
    while [ "$lksv_current" -le "$lksv_end" ]; do
        lksv_fmt=$(printf "%02d:00" "$lksv_current")
        lksv_header="${lksv_indent}- $lksv_fmt - $lksv_summary_text"
        
        # POSIX sed untuk menghapus baris lama sebelum update
        sed "3,\$ { /^${lksv_indent}- ${lksv_fmt} -/d; }" "$lksv_filename" > "$lksv_tmp_file" && mv "$lksv_tmp_file" "$lksv_filename"
        printf "%s\n" "$lksv_header" >> "$lksv_filename"
        lksv_current=$((lksv_current + 1))
    done

    # Sorting kronologis tanpa merusak struktur
    head -n 2 "$lksv_filename" > "$lksv_tmp_file"
    sed '1,2d' "$lksv_filename" | sort -b -k2,2 -u >> "$lksv_tmp_file"
    mv "$lksv_tmp_file" "$lksv_filename"
    
    printf "\033[32mSummary updated (%02d-%02d): \033[38;2;0;255;255m%s\033[0m\n" "$lksv_start" "$lksv_end" "$lksv_summary_text"
    lkcd
}
