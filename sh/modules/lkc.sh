#!/bin/sh
# Module: Chronological Reader (lkc) - Standalone & Config-Aware & Hard Fork ##

# =========================================================================
# COLOR PALETTE CONFIGURATION (Global Variables)
# =========================================================================
LK_RESET=$(printf '\033[0m')
LK_AMBER=$(printf '\033[38;2;255;204;0m')       # Daily Summary Date
LK_LIME=$(printf '\033[38;2;100;255;0m')        # Timestamps
LK_GREY=$(printf '\033[90m')                    # Plain Text Log
LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Hourly Summary Time
LK_ORANGE=$(printf '\033[38;2;255;102;0m')      # Taxonomy Tags [[...]] >>
LK_HEADER_ORG=$(printf '\033[38;2;255;117;0m')  # Header Separator
# =========================================================================

# Smart Summary Extractor (Ignores YAML Frontmatter & Empty Lines)
_LK_EXTRACTOR='
FNR==1 {
    if ($0 ~ /^---/) { yaml=1; next }
    else { print; nextfile }
}
yaml && /^---/ { yaml=0; next }
yaml { next }
/^[[:space:]]*$/ { next }
{ print; nextfile }
'

# Universal Colorizer Engine (Pipes Input)
_lkc_colorizer() {
    # Data Sanitization: Kill Rogue Terminal Escape Codes (ESC, CR, BS, BEL)
    tr -d '\033\015\010\007' | \
    awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
    
    # Catch Date (YYYY-MM-DD), Month (YYYY-MM), and Year (YYYY) -> AMBER
    $0 ~ /^-[[:space:]]*(#)?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
        print amber $0 reset; next
    }
    # Catch Monthly Summary Item in yearly file (Indent 4 spaces + [[YYYY-MM]]) -> CYAN
    $0 ~ /^[ ]{4}- \[\[[0-9]{4}-[0-9]{2}\]\]/ {
        print cyan $0 reset; next
    }
    # Catch Hourly Summary Item (Supports new "## HH:00" and legacy "HH:00") -> CYAN
    $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
        print cyan $0 reset; next
    }
    # Catch Regular Log / Taxonomy (Green Timestamp, Orange Tag, Grey Log)
    $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
        ts_part = substr($0, 1, 21)
        rest_part = substr($0, 22)
        
        if (match(rest_part, /^\[\[.*\]\] >>/)) {
            tag_part = substr(rest_part, 1, RLENGTH)
            msg_part = substr(rest_part, RLENGTH + 1)
            print lime ts_part orange tag_part grey msg_part reset
        } else {
            print lime ts_part grey rest_part reset
        }
        next
    }
    { print grey $0 reset }
    '
}

lkc() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    
    lkc_filename="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    lkc_indent="    "

    # --- 2. Execution Mode Without Arguments (Today) ---
    if [ -z "$1" ]; then
        if [ -f "$lkc_filename" ]; then
            printf "%s| LK (LogKlerk) --- All Activities of the Day (%s) ---%s\n" "$LK_HEADER_ORG" "$TODAY" "$LK_RESET"
            _lkc_colorizer < "$lkc_filename"
            printf "%s----------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
        else
            printf "\033[31m[Warning]\033[0m File does not exist yet.\n"
        fi
        return 0
    fi

    # --- 3. Dynamic Filter Mode ---
    case "$1" in
        -a|-all|--all)
            printf "%s--- All Daily Summaries ---%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            find "$LK_DIR" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            printf "%s----------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            return 0 ;;
        -y|-year|--year)
            lkc_tdir="$LK_DIR/$YEAR"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            return 0 ;;
        -m|-month|--month)
            lkc_tdir="$LK_DIR/$YEAR/$MONTH"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            return 0 ;;
        
        # --- Specific Date Extraction ---
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
                printf "%s| LK (LogKlerk) --- All Activities of the Day (%s) ---%s\n" "$LK_HEADER_ORG" "$target_date" "$LK_RESET"
                _lkc_colorizer < "$lkc_tfile"
                printf "%s----------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            else
                printf "\033[31m[Warning]\033[0m File does not exist yet: %s\n" "$lkc_tfile"
            fi
            return 0 ;;
    esac

    [ ! -f "$lkc_filename" ] && return 1

    # --- 4. Hour Filter Mode (UPDATED FOR '##' HARD FORK) ---
    case "$1" in
        *-*)
            lkc_sh=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_sh" ] && lkc_sh=0
            lkc_eh=$(echo "$1" | cut -d'-' -f2 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_eh" ] && lkc_eh=0
            lkc_sfmt=$(printf "%02d:00" "$lkc_sh"); lkc_efmt=$(printf "%02d:00" "$lkc_eh")
            
            awk -v start="${lkc_indent}- ## $lkc_sfmt" -v start_leg="${lkc_indent}- $lkc_sfmt" -v end_limit="${lkc_efmt}" '
                $0 ~ start || $0 ~ start_leg {found=1}
                found && $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
                    # Ekstrak HH:00 untuk komparasi dengan end_limit
                    match($0, /[0-2][0-9]:00/)
                    curr_hh = substr($0, RSTART, 5)
                    if (curr_hh > end_limit) found=0
                }
                found { print }
            ' "$lkc_filename" | _lkc_colorizer
            ;;
        *)
            lkc_h=$(echo "$1" | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_h" ] && lkc_h=0
            lkc_fmt=$(printf "%02d:00" "$lkc_h")
            
            awk -v target="${lkc_indent}- ## $lkc_fmt" -v target_leg="${lkc_indent}- $lkc_fmt" '
                $0 ~ target || $0 ~ target_leg { found=1; print; next }
                found && $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {found=0}
                found { print }
            ' "$lkc_filename" | _lkc_colorizer
            ;;
    esac
}

lkcd() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    if [ -z "$1" ]; then
        lkcd_date=$(date +%Y-%m-%d)
    else
        if [ "${#1}" -eq 8 ]; then
            y="${1%????}"
            m_d="${1#????}"
            m="${m_d%??}"
            d="${m_d#??}"
            lkcd_date="$y-$m-$d"
        elif echo "$1" | grep -q '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$'; then
            lkcd_date="$1"
        else
            printf "\033[31m[Error]\033[0m Invalid date format. Use YYYYMMDD or YYYY-MM-DD.\n"
            return 1
        fi
    fi

    lkcd_year="${lkcd_date%%-*}"
    lkcd_month="${lkcd_date%-*}"
    lkcd_fn="$LK_DIR/$lkcd_year/$lkcd_month/$lkcd_date.md"
    
    if [ ! -f "$lkcd_fn" ]; then
        printf "\033[31m[Warning]\033[0m Log file for date \033[38;2;255;255;0m%s\033[0m not found.\n" "$lkcd_date"
        return 1
    fi
    
    printf "%s| LK (LogKlerk) --- Daily Hourly Summary (%s) ---%s\n" "$LK_HEADER_ORG" "$lkcd_date" "$LK_RESET"
    
    awk "$_LK_EXTRACTOR" "$lkcd_fn" | _lkc_colorizer
    
    # FIX: Updated to detect "## HH:00"
    grep -E "\- (## )?[0-2][0-9]:00 " "$lkcd_fn" | sed 's/^[[:space:]]*//' | awk '!seen[$0]++' | sort -k2,2 | while IFS= read -r line; do
        printf "%s    %s%s\n" "$LK_CYAN" "$line" "$LK_RESET"
    done
    
    printf "%s----------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
}

lkch() {
    lkch_curr=$(date +%H)
    printf "%s| LK (LogKlerk) --- Hourly Summary (%s:00) ---%s\n" "$LK_HEADER_ORG" "$lkch_curr" "$LK_RESET"
    lkc "$lkch_curr"
}

lkcm() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    if [ -z "$1" ]; then
        lkcm_year=$(date +%Y)
        lkcm_month=$(date +%Y-%m)
    else
        if [ "${#1}" -eq 6 ]; then
            lkcm_year="${1%??}"
            _m="${1#????}"
            lkcm_month="$lkcm_year-$_m"
        elif [ "${#1}" -eq 7 ] && echo "$1" | grep -q '^[0-9]\{4\}-[0-9]\{2\}$'; then
            lkcm_year="${1%-*}"
            lkcm_month="$1"
        else
            printf "\033[31m[Error]\033[0m Invalid month format.\n"
            return 1
        fi
    fi

    lkcm_tdir="$LK_DIR/$lkcm_year/$lkcm_month"

    if [ ! -d "$lkcm_tdir" ]; then
        printf "\033[31m[Warning]\033[0m Log directory for month \033[38;2;255;255;0m%s\033[0m not found.\n" "$lkcm_month"
        return 1
    fi

    printf "%s| LK (LogKlerk) --- Monthly Daily Summary (%s) ---%s\n" "$LK_HEADER_ORG" "$lkcm_month" "$LK_RESET"
    find "$lkcm_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
}

lkcy() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    if [ -z "$1" ]; then
        lkcy_year=$(date +%Y)
    else
        if [ "${#1}" -eq 4 ] && echo "$1" | grep -q '^[0-9]\{4\}$'; then
            lkcy_year="$1"
        else
            printf "\033[31m[Error]\033[0m Invalid year format. Use YYYY.\n"
            return 1
        fi
    fi

    lkcy_file="$LK_DIR/$lkcy_year/$lkcy_year.md"

    if [ ! -f "$lkcy_file" ]; then
        printf "\033[31m[Warning]\033[0m Yearly summary file \033[38;2;255;255;0m%s.md\033[0m not found.\n" "$lkcy_year"
        return 1
    fi

    printf "%s| LK (LogKlerk) --- Yearly Monthly Summary (%s) ---%s\n" "$LK_HEADER_ORG" "$lkcy_year" "$LK_RESET"
    _lkc_colorizer < "$lkcy_file"
}
