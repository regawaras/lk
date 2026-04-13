# LogKlerk (LK) - A POSIX-compliant Daily Notes Terminal
# Compatible with dash, sh, bash, zsh

# --- Configuration & Paths ---
# LogKlerk (LK) - Core Dispatcher
LK_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/logklerk"
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
    hs_time_input="$1"
    shift
    hs_summary_text="$*"
    _lk_get_time
    hs_target_dir="$LK_DIR/$YEAR/$MONTH"
    hs_filename="$hs_target_dir/$TODAY.md"
    hs_indent="    "

    mkdir -p "$hs_target_dir"
    if [ ! -f "$hs_filename" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$hs_filename"
        printf "%screated: [[%s]] - %s\n" "$hs_indent" "$TODAY" "$FULL_TIMESTAMP" >> "$hs_filename"
    fi

    case "$hs_time_input" in
        *-*)
            hs_start_raw=$(echo "$hs_time_input" | cut -d'-' -f1 | tr -cd '0-9')
            hs_end_raw=$(echo "$hs_time_input" | cut -d'-' -f2 | tr -cd '0-9')
            ;;
        *)
            hs_start_raw=$(echo "$hs_time_input" | tr -cd '0-9')
            hs_end_raw="$hs_start_raw"
            ;;
    esac

    hs_start=$(echo "$hs_start_raw" | sed 's/^0*//')
    hs_end=$(echo "$hs_end_raw" | sed 's/^0*//')
    [ -z "$hs_start" ] && hs_start=0
    [ -z "$hs_end" ] && hs_end=0

    hs_tmp_file=$(mktemp)
    hs_current=$hs_start
    while [ "$hs_current" -le "$hs_end" ]; do
        hs_fmt=$(printf "%02d:00" "$hs_current")
        hs_header="${hs_indent}- $hs_fmt - $hs_summary_text"
        sed '3,$ { /^'"${hs_indent}"'- '"$hs_fmt"' -/d; }' "$hs_filename" > "$hs_tmp_file" && mv "$hs_tmp_file" "$hs_filename"
        printf "%s\n" "$hs_header" >> "$hs_filename"
        hs_current=$((hs_current + 1))
    done

    head -n 2 "$hs_filename" > "$hs_tmp_file"
    sed '1,2d' "$hs_filename" | sort -b -k2,2 -u >> "$hs_tmp_file"
    mv "$hs_tmp_file" "$hs_filename"
    printf "\033[32mSummary updated & Sorted range %s-%s: \033[38;2;0;255;255m%s\033[0m\n" "$hs_start" "$hs_end" "$hs_summary_text"
    lkcs
}
