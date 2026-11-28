#!/bin/sh
# Module: lkplan (LogKlerk Planner - Intent Router & Diff Checker)
# Updated to v0.0.5: Zero-Subshell Overhead, Pure AWK Octal Constants, & Single-Pass Array Pipeline

lkplan() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="/run/media/nixos/c9a0990e-ba7f-4860-ba3b-1a7cd1182b50/home/regawaras/als/lk/"
    LK_DEFAULT_FORMAT=".md"
    
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION (ZERO-SUBSHELL OVERHEAD)
    # Dideklarasikan sebagai string literal, hindari $(printf) sama sekali!
    # =========================================================================
    LK_RESET='\033[0m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_HEADER_ORG='\033[38;2;255;117;0m'
    LK_RED='\033[31m'
    LK_MAGENTA='\033[38;2;255;0;255m' # Specific color for PLAN
    # =========================================================================

    lksm_target="$1"
    shift
    
    # --- PLAN INJECTION ---
    lksm_text="![PLAN]! $*"

    # --- 1. STRICT INPUT VALIDATION ---
    if [ -z "$*" ]; then
        # Menggunakan %b agar printf menerjemahkan literal backslash (\033) secara native
        printf "%b[Error]%b Plan text is empty.\n" "$LK_RED" "$LK_RESET"
        printf "Usage:\n"
        printf "  lkplan %b2026%b \"Text\"        %b(Set Yearly Plan)%b\n" "$LK_AMBER" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lkplan %b202604%b \"Text\"      %b(Set Monthly Plan)%b\n" "$LK_CYAN" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lkplan %b20260422%b \"Text\"    %b(Set Daily Plan)%b\n" "$LK_ORANGE" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lkplan %b14%b \"Text\"          %b(Set Hourly Plan for Today)%b\n" "$LK_LIME" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lkplan %b01-03%b \"Text\"       %b(Set Batch Hourly Plan)%b\n" "$LK_LIME" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        return 1
    fi

    case "$lksm_target" in
        *[!0-9-]*)
            printf "%b[Error]%b Invalid target format: '%s'. Target must be a valid Time/Date numeric string.\n" "$LK_RED" "$LK_RESET" "$lksm_target"
            return 1
            ;;
    esac
    # ----------------------------------

    lksm_curr_year=$(date +%Y)
    lksm_curr_month=$(date +%Y-%m)
    lksm_curr_today=$(date +%Y-%m-%d)
    lksm_curr_ts=$(date +%H:%M:%S)
    lksm_indent="    "

    # Engine Pewarnaan Internal menggunakan Native AWK Octal Constants
    _lksm_highlight_tag() {
        printf "%s\n" "$1" | LC_ALL=C awk '
        BEGIN {
            RESET   = "\033[0m"
            GREY    = "\033[38;2;150;150;150m"
            ORANGE  = "\033[38;2;225;102;0m"
            MAGENTA = "\033[38;2;255;0;255m"
        }
        {
            if (match($0, /^!\[[^\]]+\]!/)) {
                tag = substr($0, RSTART, RLENGTH)
                msg = substr($0, RLENGTH + 1)
                sub(/^[[:space:]]+/, "", msg)
                
                if (tag == "![PLAN]!") {
                    printf "%s%s%s %s%s%s", MAGENTA, tag, RESET, GREY, msg, RESET
                } else {
                    printf "%s%s%s %s%s%s", ORANGE, tag, RESET, GREY, msg, RESET
                }
            } else {
                printf "%s%s%s", GREY, $0, RESET
            }
        }'
    }

    # Penulisan Ulang _lksm_show_hourly agar 100% menggunakan Native AWK dan membuang Subshell Loop 'while'
    _lksm_show_hourly() {
        local t_file="$1"
        local t_date="$2"
        printf "\n%b| LK (LogKlerk) --- Hourly Plan & Summaries (%s) ---%b\n" "$LK_MAGENTA" "$t_date" "$LK_RESET"
        
        local d_sum=$(head -n 1 "$t_file")
        printf "%b%s%b\n" "$LK_AMBER" "$d_sum" "$LK_RESET"
        
        grep -E "^[[:space:]]*- (## )?[0-2][0-9]:00 -" "$t_file" | sed 's/^[[:space:]]*//' | sort | \
        LC_ALL=C awk '
        BEGIN {
            RESET   = "\033[0m"
            CYAN    = "\033[38;2;0;255;255m"
            GREY    = "\033[38;2;150;150;150m"
            ORANGE  = "\033[38;2;225;102;0m"
            MAGENTA = "\033[38;2;255;0;255m"
        }
        {
            # Ekstrak Jam
            match($0, /^- (## )?[0-2][0-9]:00 -[[:space:]]*/)
            hr = substr($0, 1, RLENGTH)
            rest = substr($0, RLENGTH + 1)
            sub(/[[:space:]]+$/, "", hr) # Clean trailing spaces from hour string
            
            # Deteksi dan Warna Tag
            if (match(rest, /^!\[[^\]]+\]!/)) {
                tag = substr(rest, RSTART, RLENGTH)
                msg = substr(rest, RLENGTH + 1)
                sub(/^[[:space:]]+/, "", msg)
                
                t_col = (tag == "![PLAN]!") ? MAGENTA : ORANGE
                hr_col = (tag == "![PLAN]!") ? MAGENTA : CYAN
                
                print "    " hr_col hr " " RESET t_col tag RESET " " GREY msg RESET
            } else {
                print "    " CYAN hr " " RESET GREY rest RESET
            }
        }'
        printf "%b---------------------------------------------------%b\n" "$LK_MAGENTA" "$LK_RESET"
    }

    case "$lksm_target" in
        [0-9][0-9][0-9][0-9])
            lksm_y="$lksm_target"
            lksm_tdir="$LK_DIR/$lksm_y"
            lksm_tfile="$lksm_tdir/$lksm_y$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"
            
            if [ ! -f "$lksm_tfile" ]; then
                lksm_prev_raw="(Empty)"
                printf -- "- # [[%s]] - %s\n" "$lksm_y" "$lksm_text" > "$lksm_tfile"
                printf "%screated: [[%s-01-01]] - %s\n" "$lksm_indent" "$lksm_y" "$lksm_curr_ts" >> "$lksm_tfile"
            else
                lksm_prev_raw=$(sed -n "1s/^[[:space:]]*-[[:space:]]*#*[[:space:]]*\[\[$lksm_y\]\][[:space:]]*-[[:space:]]*//p" "$lksm_tfile")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                lksm_tmp=$(mktemp)
                LC_ALL=C awk -v new_text="- # [[$lksm_y]] - $lksm_text" 'NR==1{print new_text; next} {print}' "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%b✔%b Yearly Plan %b(%s)%b %bUpdated.%b\n" "$LK_LIME" "$LK_RESET" "$LK_MAGENTA" "$lksm_y" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %b%s%b | %s %b->%b %s\n" "$LK_CYAN" "$lksm_y" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_prev_raw")" "$LK_ORANGE" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_text")"
            ;;

        [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
            if [ "${#lksm_target}" -eq 6 ]; then
                lksm_y="${lksm_target%??}"
                lksm_m="${lksm_target#????}"
            else
                lksm_y="${lksm_target%-*}"
                lksm_m="${lksm_target#*-}"
            fi
            
            lksm_tdir="$LK_DIR/$lksm_y"
            lksm_tfile="$lksm_tdir/$lksm_y$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"

            if [ ! -f "$lksm_tfile" ]; then
                printf -- "- # [[%s]] - (Yearly Summary)\n" "$lksm_y" > "$lksm_tfile"
                printf "%screated: [[%s-01-01]] - %s\n" "$lksm_indent" "$lksm_y" "$lksm_curr_ts" >> "$lksm_tfile"
            fi

            lksm_tmp=$(mktemp)
            
            if grep -q "^[[:space:]]*-[[:space:]]*#*[[:space:]]*\[\[$lksm_y-$lksm_m\]\]" "$lksm_tfile"; then
                lksm_prev_raw=$(sed -n "s/^[[:space:]]*-[[:space:]]*#*[[:space:]]*\[\[$lksm_y-$lksm_m\]\][[:space:]]*-[[:space:]]*//p" "$lksm_tfile" | head -n 1)
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                LC_ALL=C awk -v y="$lksm_y" -v m="$lksm_m" -v text="$lksm_text" -v ind="$lksm_indent" '
                $0 ~ "^[[:space:]]*-[[:space:]]*#*[[:space:]]*\\[\\[" y "-" m "\\]\\]" {
                    print ind "- # [[" y "-" m "]] - " text; next
                } {print}' "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            else
                lksm_prev_raw="(Empty)"
                printf "%s- # [[%s-%s]] - %s\n" "$lksm_indent" "$lksm_y" "$lksm_m" "$lksm_text" >> "$lksm_tfile"
                head -n 2 "$lksm_tfile" > "$lksm_tmp"
                sed '1,2d' "$lksm_tfile" | sort -b -k2,2 >> "$lksm_tmp"
                mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%b✔%b Monthly Plan %b(%s-%s)%b %bUpdated.%b\n" "$LK_LIME" "$LK_RESET" "$LK_MAGENTA" "$lksm_y" "$lksm_m" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %b%s-%s%b | %s %b->%b %s\n" "$LK_CYAN" "$lksm_y" "$lksm_m" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_prev_raw")" "$LK_ORANGE" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_text")"
            ;;

        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            if [ "${#lksm_target}" -eq 8 ]; then
                lksm_y="${lksm_target%????}"
                lksm_m_d="${lksm_target#????}"
                lksm_m="${lksm_m_d%??}"
                lksm_d="${lksm_m_d#??}"
                lksm_target_date="$lksm_y-$lksm_m-$lksm_d"
            else
                lksm_target_date="$lksm_target"
                lksm_y="${lksm_target_date%%-*}"
                _temp_m_d="${lksm_target_date#*-}"
                lksm_m="${_temp_m_d%%-*}"
            fi
            
            lksm_tdir="$LK_DIR/$lksm_y/$lksm_y-$lksm_m"
            lksm_tfile="$lksm_tdir/$lksm_target_date$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"

            if [ ! -f "$lksm_tfile" ]; then
                lksm_prev_raw="(Empty)"
                printf -- "- # [[%s]] - %s\n" "$lksm_target_date" "$lksm_text" > "$lksm_tfile"
                printf "%screated: [[%s]] - %s\n" "$lksm_indent" "$lksm_target_date" "$lksm_curr_ts" >> "$lksm_tfile"
            else
                lksm_prev_raw=$(sed -n "1s/^[[:space:]]*-[[:space:]]*#*[[:space:]]*\[\[$lksm_target_date\]\][[:space:]]*-[[:space:]]*//p" "$lksm_tfile")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                lksm_tmp=$(mktemp)
                LC_ALL=C awk -v date="$lksm_target_date" -v text="$lksm_text" 'NR==1{print "- # [[" date "]] - " text; next} {print}' "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%b✔%b Daily Plan %b(%s)%b %bUpdated.%b\n" "$LK_LIME" "$LK_RESET" "$LK_MAGENTA" "$lksm_target_date" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %b%s%b | %s %b->%b %s\n\n" "$LK_CYAN" "$lksm_target_date" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_prev_raw")" "$LK_ORANGE" "$LK_RESET" "$(_lksm_highlight_tag "$lksm_text")"
            
            if command -v lkcm >/dev/null 2>&1 || type lkcm >/dev/null 2>&1; then
                lkcm "${lksm_y}${lksm_m}"
            else
                _lksm_show_hourly "$lksm_tfile" "$lksm_target_date"
            fi
            ;;

        *)
            lksm_tdir="$LK_DIR/$lksm_curr_year/$lksm_curr_month"
            lksm_tfile="$lksm_tdir/$lksm_curr_today$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"

            if [ ! -f "$lksm_tfile" ]; then
                printf -- "- # [[%s]] - (Daily Summary)\n" "$lksm_curr_today" > "$lksm_tfile"
                printf "%screated: [[%s]] - %s\n" "$lksm_indent" "$lksm_curr_today" "$lksm_curr_ts" >> "$lksm_tfile"
            fi

            case "$lksm_target" in
                *-*)
                    lksm_s_raw=$(printf "%s" "$lksm_target" | cut -d'-' -f1 | tr -cd '0-9')
                    lksm_e_raw=$(printf "%s" "$lksm_target" | cut -d'-' -f2 | tr -cd '0-9')
                    ;;
                *)
                    lksm_s_raw=$(printf "%s" "$lksm_target" | tr -cd '0-9')
                    lksm_e_raw="$lksm_s_raw"
                    ;;
            esac

            lksm_start="${lksm_s_raw#"${lksm_s_raw%%[!0]*}"}"
            [ -z "$lksm_start" ] && lksm_start=0

            lksm_end="${lksm_e_raw#"${lksm_e_raw%%[!0]*}"}"
            [ -z "$lksm_end" ] && lksm_end=0

            if [ "$lksm_end" -lt "$lksm_start" ]; then
                printf "%b[Error]%b Invalid hour range: End hour (%s) cannot be less than Start hour (%s).\n" "$LK_RED" "$LK_RESET" "$lksm_end" "$lksm_start"
                return 1
            fi

            lksm_tmp=$(mktemp)
            
            # --- PEMBARUAN V0.0.5: ZERO-LOOP PURE AWK OCTAL CONSTANTS ---
            lksm_diff_log=$(LC_ALL=C awk -v s_hr="$lksm_start" -v e_hr="$lksm_end" -v new_txt="$lksm_text" -v tmp_file="$lksm_tmp" '
            BEGIN {
                RESET   = "\033[0m"
                CYAN    = "\033[38;2;0;255;255m"
                GREY    = "\033[38;2;150;150;150m"
                ORANGE  = "\033[38;2;225;102;0m"
                MAGENTA = "\033[38;2;255;0;255m"
                
                for (i = s_hr; i <= e_hr; i++) targets[i] = 1
                diff_log = ""
            }
            
            function highlight(txt,   tag, msg, res) {
                if (match(txt, /^!\[[^\]]+\]!/)) {
                    tag = substr(txt, RSTART, RLENGTH)
                    msg = substr(txt, RLENGTH + 1)
                    sub(/^[[:space:]]+/, "", msg)
                    if (tag == "![PLAN]!") res = MAGENTA tag RESET GREY " " msg RESET
                    else res = ORANGE tag RESET GREY " " msg RESET
                } else {
                    res = GREY txt RESET
                }
                return res
            }
            
            {
                if ($0 ~ /^ {4}- (## )?[0-2][0-9]:00/) {
                    match($0, /[0-2][0-9]:00/)
                    curr_h = substr($0, RSTART, 2) + 0
                    
                    for (i = s_hr; i <= e_hr; i++) {
                        if (targets[i] == 1 && i < curr_h) {
                            fmt = sprintf("%02d:00", i)
                            print "    - ## " fmt " - " new_txt > tmp_file
                            diff_log = diff_log "    " MAGENTA fmt RESET " | " highlight("(Empty)") " \033[38;2;255;102;0m->\033[0m " highlight(new_txt) "\n"
                            targets[i] = 0
                        }
                    }
                    
                    if (curr_h >= s_hr && curr_h <= e_hr && targets[curr_h] == 1) {
                        fmt = sprintf("%02d:00", curr_h)
                        match($0, /^ {4}- (## )?[0-2][0-9]:00[[:space:]]*-?[[:space:]]*/)
                        old_txt = substr($0, RLENGTH + 1)
                        if (old_txt == "") old_txt = "(Empty)"
                        
                        print "    - ## " fmt " - " new_txt > tmp_file
                        diff_log = diff_log "    " MAGENTA fmt RESET " | " highlight(old_txt) " \033[38;2;255;102;0m->\033[0m " highlight(new_txt) "\n"
                        targets[curr_h] = 0
                        next
                    }
                }
                print $0 > tmp_file
            }
            END {
                for (i = s_hr; i <= e_hr; i++) {
                    if (targets[i] == 1) {
                        fmt = sprintf("%02d:00", i)
                        print "    - ## " fmt " - " new_txt > tmp_file
                        diff_log = diff_log "    " MAGENTA fmt RESET " | " highlight("(Empty)") " \033[38;2;255;102;0m->\033[0m " highlight(new_txt) "\n"
                    }
                }
                printf "%s", diff_log
            }' "$lksm_tfile")

            mv "$lksm_tmp" "$lksm_tfile"
            
            printf "%b✔%b Hourly Plan %b(%02d:00-%02d:00)%b %bUpdated.%b\n" "$LK_LIME" "$LK_RESET" "$LK_MAGENTA" "$lksm_start" "$lksm_end" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "%b" "$lksm_diff_log"
            
            _lksm_show_hourly "$lksm_tfile" "$lksm_curr_today"
            ;;
    esac
}
