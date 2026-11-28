#!/bin/sh
# Module: Chronological Reader (lkc) - Standalone & Config-Aware & Hard Fork ##
# Updated to v0.0.5: Zero-Subshell Overhead, Pure AWK Constants & Absolute Pattern Matcher

# =========================================================================
# COLOR PALETTE CONFIGURATION (ZERO-SUBSHELL OVERHEAD)
# Dideklarasikan sebagai string literal murni
# =========================================================================
LK_RESET='\033[0m'
LK_AMBER='\033[38;2;255;204;0m'       # Daily Summary Date
LK_LIME='\033[38;2;100;255;0m'        # Timestamps
LK_GREY='\033[38;2;150;150;150m'      # Light Grey for Summary Text
LK_PATH_GREY='\033[38;2;85;85;85m'    # Very Dim Grey for File Paths
LK_CYAN='\033[38;2;0;255;255m'        # Hourly Summary Time
LK_ORANGE='\033[38;2;255;102;0m'      # Tags Taxonomy & Main ![TAGS]!
LK_MAGENTA='\033[38;2;255;100;255m'   # Light Purple / Magenta for ![PLAN]!
LK_HEADER_ORG='\033[38;2;255;117;0m'  # Header Separator
# =========================================================================

# PEMBARUAN: Smart Summary Extractor (Absolute Pattern Matching)
# Mengabaikan posisi baris, YAML, atau teks acak. Hanya mencari Format Summary Resmi.
_LK_EXTRACTOR='
/^[[:space:]]*-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
    print $0;
    nextfile;
}
'

# Universal Colorizer Engine (Native AWK)
_lkc_colorizer() {
    tr -d '\033\015\010\007' | LC_ALL=C awk '
    BEGIN {
        RESET   = "\033[0m"
        AMBER   = "\033[38;2;255;204;0m"
        LIME    = "\033[38;2;100;255;0m"
        GREY    = "\033[38;2;150;150;150m"
        CYAN    = "\033[38;2;0;255;255m"
        ORANGE  = "\033[38;2;255;102;0m"
        MAGENTA = "\033[38;2;255;100;255m"
    }
    
    # Catch Date (YYYY-MM-DD) Daily Summary (Safe Regex #?)
    $0 ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ {
        match($0, /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\][[:space:]]*-?[[:space:]]*/)
        prefix = substr($0, 1, RLENGTH)
        rest = substr($0, RLENGTH + 1)
        
        if (match(rest, /^!\[[^\]]+\]!/)) {
            tag = substr(rest, RSTART, RLENGTH)
            msg = substr(rest, RLENGTH + 1)
            t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
            print AMBER prefix RESET t_col tag RESET GREY msg RESET
        } else {
            print AMBER prefix RESET GREY rest RESET
        }
        next
    }
    
    # Catch Monthly Summary Item in yearly file
    $0 ~ /^[ ]{4}- \[\[[0-9]{4}-[0-9]{2}\]\]/ {
        print CYAN $0 RESET; next
    }
    
    # Catch Hourly Summary Item (Safe Regex ##?)
    $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
        match($0, /^[ ]{4}- (## )?[0-2][0-9]:00[[:space:]]*-?[[:space:]]*/)
        prefix = substr($0, 1, RLENGTH)
        rest = substr($0, RLENGTH + 1)
        
        if (match(rest, /^!\[[^\]]+\]!/)) {
            tag = substr(rest, RSTART, RLENGTH)
            msg = substr(rest, RLENGTH + 1)
            t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
            print CYAN prefix RESET t_col tag RESET GREY msg RESET
        } else {
            print CYAN prefix RESET GREY rest RESET
        }
        next
    }
    
    # Catch Regular Log / Taxonomy
    $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
        ts_part = substr($0, 1, 21)
        rest_part = substr($0, 22)
        
        if (match(rest_part, /^\[\[.*\]\] >>/)) {
            tag_part = substr(rest_part, 1, RLENGTH)
            msg_part = substr(rest_part, RLENGTH + 1)
            print LIME ts_part ORANGE tag_part GREY msg_part RESET
        } else {
            print LIME ts_part GREY rest_part RESET
        }
        next
    }
    { print GREY $0 RESET }
    '
}

lkc() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    TODAY=$(date +%Y-%m-%d)
    YEAR=$(date +%Y)
    MONTH=$(date +%Y-%m)
    
    lkc_filename="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    lkc_indent="    "

    if [ -z "$1" ]; then
        if [ -f "$lkc_filename" ]; then
            printf "%b| LK (LogKlerk) --- All Activities of the Day (%s) ---%b\n" "$LK_HEADER_ORG" "$TODAY" "$LK_RESET"
            _lkc_colorizer < "$lkc_filename"
            printf "%b----------------------------------------%b\n" "$LK_HEADER_ORG" "$LK_RESET"
        else
            printf "\033[31m[Warning]\033[0m File does not exist yet.\n"
        fi
        return 0
    fi

    case "$1" in
        -a|-all|--all)
            printf "%b--- All Daily Summaries ---%b\n" "$LK_HEADER_ORG" "$LK_RESET"
            find "$LK_DIR" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            printf "%b----------------------------------------%b\n" "$LK_HEADER_ORG" "$LK_RESET"
            return 0 ;;
        -y|-year|--year)
            lkc_tdir="$LK_DIR/$YEAR"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            return 0 ;;
        -m|-month|--month)
            lkc_tdir="$LK_DIR/$YEAR/$MONTH"
            [ -d "$lkc_tdir" ] && find "$lkc_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
            return 0 ;;
        
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            if [ "${#1}" -eq 8 ]; then
                y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
                target_date="$y-$m-$d"
            else
                target_date="$1"
            fi
            
            lkc_ty="${target_date%%-*}"
            lkc_tm="${target_date%-*}"
            lkc_tfile="$LK_DIR/$lkc_ty/$lkc_tm/$target_date.md"
            
            if [ -f "$lkc_tfile" ]; then
                printf "%b| LK (LogKlerk) --- All Activities of the Day (%s) ---%b\n" "$LK_HEADER_ORG" "$target_date" "$LK_RESET"
                _lkc_colorizer < "$lkc_tfile"
                printf "%b----------------------------------------%b\n" "$LK_HEADER_ORG" "$LK_RESET"
            else
                printf "\033[31m[Warning]\033[0m File does not exist yet: %s\n" "$lkc_tfile"
            fi
            return 0 ;;
    esac

    [ ! -f "$lkc_filename" ] && return 1

    case "$1" in
        *-*)
            lkc_sh=$(echo "$1" | cut -d'-' -f1 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_sh" ] && lkc_sh=0
            lkc_eh=$(echo "$1" | cut -d'-' -f2 | tr -cd '0-9' | sed 's/^0*//'); [ -z "$lkc_eh" ] && lkc_eh=0
            lkc_sfmt=$(printf "%02d:00" "$lkc_sh"); lkc_efmt=$(printf "%02d:00" "$lkc_eh")
            
            awk -v start="${lkc_indent}- ## $lkc_sfmt" -v start_leg="${lkc_indent}- $lkc_sfmt" -v end_limit="${lkc_efmt}" '
                $0 ~ start || $0 ~ start_leg {found=1}
                found && $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ {
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
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    if [ -z "$1" ]; then
        lkcd_date=$(date +%Y-%m-%d)
    else
        if [ "${#1}" -eq 8 ]; then
            y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
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
    
    printf "%b| LK (LogKlerk) --- Daily Hourly Summary (%s) ---%b\n" "$LK_HEADER_ORG" "$lkcd_date" "$LK_RESET"
    
    # 1. Cetak Daily Summary
    awk "$_LK_EXTRACTOR" "$lkcd_fn" | _lkc_colorizer
    
    # 2. Cetak Hourly Summaries (Optimasi Zero-Loop: Satu Pipeline AWK)
    awk '/^[[:space:]]*- (## )?[0-2][0-9]:00 / {
        sub(/^[[:space:]]+/, "")
        line = "    " $0
        if (!seen[line]++) {
            print line
        }
    }' "$lkcd_fn" | sort -k2,2 | _lkc_colorizer
    
    printf "%b----------------------------------%b\n" "$LK_HEADER_ORG" "$LK_RESET"
}

lkch() {
    lkch_curr=$(date +%H)
    printf "%b| LK (LogKlerk) --- Hourly Summary (%s:00) ---%b\n" "$LK_HEADER_ORG" "$lkch_curr" "$LK_RESET"
    lkc "$lkch_curr"
}

lkcm() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    if [ -z "$1" ]; then
        lkcm_year=$(date +%Y)
        lkcm_month=$(date +%Y-%m)
    else
        if [ "${#1}" -eq 6 ]; then
            lkcm_year="${1%??}"; _m="${1#????}"
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

    printf "%b| LK (LogKlerk) --- Monthly Daily Summary (%s) ---%b\n" "$LK_HEADER_ORG" "$lkcm_month" "$LK_RESET"
    find "$lkcm_tdir" -type f -name "*.md" -exec awk "$_LK_EXTRACTOR" {} + | sort | _lkc_colorizer
}

lkcy() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    lksy_target_path="$LK_DIR"
    view_mode="default"
    max_len=38
    is_full_mode=0

    for arg in "$@"; do
        case "$arg" in
            min|mini)       view_mode="mini"; max_len=25 ;;
            mid|med|medium) view_mode="mid"; max_len=55 ;;
            max|maximum)    view_mode="max"; max_len=80 ;;
            fit)            view_mode="fit"; max_len=120 ;;
            full)           view_mode="full"; max_len=9999; is_full_mode=1 ;; 
            
            [0-9][0-9][0-9][0-9])
                if [ -d "$LK_DIR/$arg" ]; then
                    lksy_target_path="$LK_DIR/$arg"
                else
                    printf "\033[31m[Error]\033[0m Folder tahun %s tidak ditemukan.\n" "$arg"
                    return 1
                fi
                ;;
            *)
                printf "\033[31m[Error]\033[0m Argumen tidak dikenal: %s\n" "$arg"
                printf "Usage: lkcy [YYYY] [min|mid|max|fit|full]\n"
                return 1
                ;;
        esac
    done

    if [ "$is_full_mode" -eq 1 ]; then
        tput rmam 2>/dev/null
        trap 'tput smam 2>/dev/null; trap - INT' INT
    fi

    printf "%b| LK (LogKlerk) --- Historical Genesis Timeline (ASC) [View: %s] ---%b\n" "$LK_HEADER_ORG" "$view_mode" "$LK_RESET"

    # --- 3. The Genesis Engine (Direct Streamer, Native Colors) ---
    find "$lksy_target_path" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" | sort | \
    LC_ALL=C awk -v max_len="$max_len" -v lkdir="$LK_DIR" '
    BEGIN {
        RESET     = "\033[0m"
        AMBER     = "\033[38;2;255;204;0m"
        ORANGE    = "\033[38;2;255;102;0m"
        GREY      = "\033[38;2;150;150;150m"
        PATH_GREY = "\033[38;2;85;85;85m"
        RED       = "\033[31m"
        MAGENTA   = "\033[38;2;255;100;255m"
    }
    {
        file = $0;
        summary_found = 0; txt = ""; dt = "";
        rel_path = file;
        sub(lkdir "/", "", rel_path);

        n = split(file, parts, "/");
        basename = parts[n];
        file_date = substr(basename, 1, 10);
        dt = "[[" file_date "]]";

        while ((getline line < file) > 0) {
            # Safe literal regex for #? matching
            if (line ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/) {
                txt = line;
                sub(/^[[:space:]]*-[[:space:]]*#?[[:space:]]*\[\[[^\]]+\]\][[:space:]]*[-:]?[[:space:]]*/, "", txt);
                summary_found = 1;
                break;
            }
        }
        close(file);

        if (!summary_found) {
            txt = "[Summary Not Found/Not Yet Summarized]";
        }
        sub(/[[:space:]]+$/, "", txt);

        if (txt == "" && summary_found) {
            txt = "(Empty Summary)";
        } else if (txt == "") {
             txt = "[Empty File / Anomaly]";
        }

        # --- Dynamic Padding & Tag Segmentation ---
        txt_color = GREY;
        tag_str = "";
        tag_color = ORANGE;
        rest_str = txt;

        if (txt ~ /^\[Anomaly/ || txt ~ /^\[Empty/ || txt ~ /^\(Empty/ || txt ~ /^\[Summary Not Found/) {
            txt_color = RED;
            colored_txt = txt_color txt RESET;
            raw_len = length(txt);
        } else {
            if (match(txt, /^!\[[^\]]+\]!/)) {
                tag_str = substr(txt, RSTART, RLENGTH);
                rest_str = substr(txt, RLENGTH + 1);
                sub(/^[[:space:]]+/, "", rest_str);

                if (tag_str == "![PLAN]!") tag_color = MAGENTA;
            }

            raw_len = length(tag_str) + (tag_str != "" ? 1 : 0) + length(rest_str);
            if (tag_str == "") raw_len = length(rest_str);

            if (max_len != 9999 && raw_len > max_len) {
                avail_len = max_len - length(tag_str) - (tag_str != "" ? 1 : 0);
                if (avail_len < 3) {
                    raw_txt = substr((tag_str != "" ? tag_str " " rest_str : rest_str), 1, max_len - 3) "...";
                    tag_str = ""; rest_str = raw_txt;
                    colored_txt = txt_color raw_txt RESET;
                    raw_len = length(raw_txt);
                } else {
                    rest_str = substr(rest_str, 1, avail_len - 3) "...";
                    raw_len = max_len;
                }
            }

            if (tag_str != "") {
                colored_txt = tag_color tag_str RESET " " txt_color rest_str RESET;
                raw_len = length(tag_str) + 1 + length(rest_str);
            } else {
                colored_txt = txt_color rest_str RESET;
                raw_len = length(rest_str);
            }
        }

        # Manual Padding Generator
        pad_spaces = "";
        if (max_len != 9999 && raw_len < max_len) {
            for (i = 0; i < (max_len - raw_len); i++) pad_spaces = pad_spaces " ";
        }

        # Print Output
        printf "%s%-14s%s %s%s %s(%s)%s\n", AMBER, dt, RESET, colored_txt, pad_spaces, PATH_GREY, rel_path, RESET;
    }' 2>/dev/null
    printf "%b------------------------------------------------------------%b\n" "$LK_HEADER_ORG" "$LK_RESET"

    if [ "$is_full_mode" -eq 1 ]; then
        tput smam 2>/dev/null
        trap - INT
    fi
}
