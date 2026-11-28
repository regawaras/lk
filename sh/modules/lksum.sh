#!/bin/sh
# Module: lksum (LogKlerk Summarizer - Standalone Time Router & Diff Checker)

lksum() {
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')        # Success Checkmark & New Text
    LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Time/Target Highlight
    LK_GREY=$(printf '\033[90m')                    # Dim Text & Old Text
    LK_AMBER=$(printf '\033[38;2;255;204;0m')       # Daily Summary Date
    LK_ORANGE=$(printf '\033[38;2;225;102;0m')      # Highlight Warning & Arrow
    LK_HEADER_ORG=$(printf '\033[38;2;255;117;0m')  # Header Separator
    # =========================================================================

    lksm_target="$1"
    shift
    lksm_text="$*"

    if [ -z "$lksm_text" ]; then
        printf "\033[31m[Error]\033[0m Summary text is empty.\n"
        printf "Usage:\n"
        printf "  lksum %s2026%s \"Text\"        %s(Update Yearly Summary)%s\n" "$LK_AMBER" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lksum %s202604%s \"Text\"      %s(Update Monthly Summary)%s\n" "$LK_CYAN" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lksum %s20260422%s \"Text\"    %s(Update Daily Summary)%s\n" "$LK_ORANGE" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lksum %s14%s \"Text\"          %s(Update Hourly Summary for Today)%s\n" "$LK_LIME" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        printf "  lksum %s01-03%s \"Text\"       %s(Update Batch Hourly Summary)%s\n" "$LK_LIME" "$LK_RESET" "$LK_GREY" "$LK_RESET"
        return 1
    fi

    lksm_curr_year=$(date +%Y)
    lksm_curr_month=$(date +%Y-%m)
    lksm_curr_today=$(date +%Y-%m-%d)
    lksm_curr_ts=$(date +%H:%M:%S)
    lksm_indent="    "

    # Helper function to display Hourly Summaries after updating
    _lksm_show_hourly() {
        local t_file="$1"
        local t_date="$2"
        printf "\n%s| LK (LogKlerk) --- Hourly Summaries (%s) ---%s\n" "$LK_HEADER_ORG" "$t_date" "$LK_RESET"
        
        local d_sum=$(head -n 1 "$t_file")
        printf "%s%s%s\n" "$LK_AMBER" "$d_sum" "$LK_RESET"
        
        grep "\- [0-2][0-9]:00 " "$t_file" | sed 's/^[[:space:]]*//' | awk '!seen[$2]++' | sort -k2,2 | while IFS= read -r line; do
            printf "    %s%s%s\n" "$LK_CYAN" "$line" "$LK_RESET"
        done
        printf "%s---------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
    }

    case "$lksm_target" in
        # ==========================================
        # 1. YEARLY SUMMARY (Format: YYYY)
        # ==========================================
        [0-9][0-9][0-9][0-9])
            lksm_y="$lksm_target"
            lksm_tdir="$LK_DIR/$lksm_y"
            lksm_tfile="$lksm_tdir/$lksm_y$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"
            
            if [ ! -f "$lksm_tfile" ]; then
                lksm_prev_raw="(Empty)"
                printf -- "- [[%s]] - %s\n" "$lksm_y" "$lksm_text" > "$lksm_tfile"
                printf "%screated: [[%s-01-01]] - %s\n" "$lksm_indent" "$lksm_y" "$lksm_curr_ts" >> "$lksm_tfile"
            else
                lksm_prev_raw=$(sed -n "1s/^- \[\[$lksm_y\]\] - //p" "$lksm_tfile")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                lksm_tmp=$(mktemp)
                sed "1c\\
- [[$lksm_y]] - $lksm_text" "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%s✔%s Yearly Summary %s(%s)%s %sUpdated.%s\n" "$LK_LIME" "$LK_RESET" "$LK_CYAN" "$lksm_y" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %s%s%s | %s%s%s %s->%s %s%s%s\n" "$LK_CYAN" "$lksm_y" "$LK_RESET" "$LK_GREY" "$lksm_prev_raw" "$LK_RESET" "$LK_ORANGE" "$LK_RESET" "$LK_LIME" "$lksm_text" "$LK_RESET"
            ;;

        # ==========================================
        # 2. MONTHLY SUMMARY (Format: YYYYMM)
        # ==========================================
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
                printf -- "- [[%s]] - (Yearly Summary)\n" "$lksm_y" > "$lksm_tfile"
                printf "%screated: [[%s-01-01]] - %s\n" "$lksm_indent" "$lksm_y" "$lksm_curr_ts" >> "$lksm_tfile"
            fi

            lksm_m_str="${lksm_indent}- [[$lksm_y-$lksm_m]] -"
            lksm_tmp=$(mktemp)
            
            if grep -q "^$lksm_m_str" "$lksm_tfile"; then
                lksm_prev_raw=$(grep "^$lksm_m_str" "$lksm_tfile" | sed "s/^$lksm_m_str //")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                sed "/^$lksm_m_str/c\\
$lksm_m_str $lksm_text" "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            else
                lksm_prev_raw="(Empty)"
                printf "%s %s\n" "$lksm_m_str" "$lksm_text" >> "$lksm_tfile"
                head -n 2 "$lksm_tfile" > "$lksm_tmp"
                sed '1,2d' "$lksm_tfile" | sort -b -k2,2 >> "$lksm_tmp"
                mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%s✔%s Monthly Summary %s(%s-%s)%s %sUpdated.%s\n" "$LK_LIME" "$LK_RESET" "$LK_CYAN" "$lksm_y" "$lksm_m" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %s%s-%s%s | %s%s%s %s->%s %s%s%s\n" "$LK_CYAN" "$lksm_y" "$lksm_m" "$LK_RESET" "$LK_GREY" "$lksm_prev_raw" "$LK_RESET" "$LK_ORANGE" "$LK_RESET" "$LK_LIME" "$lksm_text" "$LK_RESET"
            ;;

        # ==========================================
        # 3. DAILY SUMMARY (Format: YYYYMMDD)
        # ==========================================
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
                lksm_m="${lksm_target_date%-*}"
            fi
            
            lksm_tdir="$LK_DIR/$lksm_y/$lksm_y-$lksm_m"
            lksm_tfile="$lksm_tdir/$lksm_target_date$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"

            if [ ! -f "$lksm_tfile" ]; then
                lksm_prev_raw="(Empty)"
                printf -- "- [[%s]] - %s\n" "$lksm_target_date" "$lksm_text" > "$lksm_tfile"
                printf "%screated: [[%s]] - %s\n" "$lksm_indent" "$lksm_target_date" "$lksm_curr_ts" >> "$lksm_tfile"
            else
                lksm_prev_raw=$(sed -n "1s/^- \[\[$lksm_target_date\]\] - //p" "$lksm_tfile")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                lksm_tmp=$(mktemp)
                sed "1c\\
- [[$lksm_target_date]] - $lksm_text" "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
            fi
            
            printf "%s✔%s Daily Summary %s(%s)%s %sUpdated.%s\n" "$LK_LIME" "$LK_RESET" "$LK_CYAN" "$lksm_target_date" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            printf "    %s%s%s | %s%s%s %s->%s %s%s%s\n" "$LK_CYAN" "$lksm_target_date" "$LK_RESET" "$LK_GREY" "$lksm_prev_raw" "$LK_RESET" "$LK_ORANGE" "$LK_RESET" "$LK_LIME" "$lksm_text" "$LK_RESET"
            
            _lksm_show_hourly "$lksm_tfile" "$lksm_target_date"
            ;;

        # ==========================================
        # 4. HOURLY SUMMARY (Format: HH or HH-HH)
        # ==========================================
        *)
            lksm_tdir="$LK_DIR/$lksm_curr_year/$lksm_curr_month"
            lksm_tfile="$lksm_tdir/$lksm_curr_today$LK_DEFAULT_FORMAT"
            mkdir -p "$lksm_tdir"

            if [ ! -f "$lksm_tfile" ]; then
                printf -- "- [[%s]] - (Daily Summary)\n" "$lksm_curr_today" > "$lksm_tfile"
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

            lksm_tmp=$(mktemp)
            lksm_curr="$lksm_start"
            lksm_diff_log=""
            
            while [ "$lksm_curr" -le "$lksm_end" ]; do
                lksm_fmt=$(printf "%02d:00" "$lksm_curr")
                lksm_h_str="${lksm_indent}- $lksm_fmt -"
                
                # Failsafe: Capture previous state before overwriting
                lksm_prev_raw=$(grep "^${lksm_h_str}" "$lksm_tfile" | sed "s/^${lksm_h_str} //")
                [ -z "$lksm_prev_raw" ] && lksm_prev_raw="(Empty)"
                
                # Append to Diff History Log
                lksm_diff_log="${lksm_diff_log}    ${LK_CYAN}${lksm_fmt}${LK_RESET} | ${LK_GREY}${lksm_prev_raw}${LK_RESET} \033[38;2;255;102;0m->\033[0m ${LK_LIME}${lksm_text}${LK_RESET}\n"
                
                sed "3,\$ { /^${lksm_h_str}/d; }" "$lksm_tfile" > "$lksm_tmp" && mv "$lksm_tmp" "$lksm_tfile"
                printf "%s %s\n" "$lksm_h_str" "$lksm_text" >> "$lksm_tfile"
                lksm_curr=$((lksm_curr + 1))
            done

            head -n 2 "$lksm_tfile" > "$lksm_tmp"
            sed '1,2d' "$lksm_tfile" | sort -b -k2,2 -u >> "$lksm_tmp"
            mv "$lksm_tmp" "$lksm_tfile"
            
            printf "%s✔%s Hourly Summary %s(%02d:00-%02d:00)%s %sUpdated.%s\n" "$LK_LIME" "$LK_RESET" "$LK_CYAN" "$lksm_start" "$lksm_end" "$LK_RESET" "$LK_GREY" "$LK_RESET"
            
            # Print the Diff History Log
            printf "%b" "$lksm_diff_log"
            
            _lksm_show_hourly "$lksm_tfile" "$lksm_curr_today"
            ;;
    esac
}
