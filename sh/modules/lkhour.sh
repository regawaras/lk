#!/bin/sh
# Module: lkhour (LogKlerk Chronometric Hour Analyzer)
# Feature: Macro-Temporal Block Aggregation & 24-Hour Density Distribution
# Vibe: Cybernetic Cult of the Time God (Pillar Architecture)

lkhour() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"
    
    if [ ! -d "$LK_DIR" ]; then
        printf "\033[31m[Blasphemy]\033[0m The Chronometric Vault (%s) does not exist.\n" "$LK_DIR"
        return 1
    fi
    
    # Global Colors
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_MAGENTA='\033[38;2;255;100;255m'
    LK_RED='\033[31m'

    # --- 2. Dynamic Arguments & Universal Parser ---
    sort_mode="rank"
    target_time=""
    
    curr_y=$(date +%Y)
    curr_m=$(date +%Y-%m)
    
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|chrono|--chrono) sort_mode="chrono"; shift; continue ;;
            -r|rank|--rank) sort_mode="rank"; shift; continue ;;
            m|month|-m|--month) target_time="month"; shift; continue ;;
            y|year|-y|--year) target_time="year"; shift; continue ;;
            [0-9]*) target_time="$1"; shift; continue ;;
            *) shift; continue ;;
        esac
    done

    # --- 3. The Universal File Builder ---
    file_list=$(mktemp)

    if [ -z "$target_time" ] || [ "$target_time" = "all" ]; then
        find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" > "$file_list"
        lks_scope="Global Lifetime"
    elif [ "$target_time" = "month" ]; then
        find "$LK_DIR/$curr_y/$curr_m" -type f -name "*.md" 2>/dev/null > "$file_list"
        lks_scope="Monthly Scope ($curr_m)"
    elif [ "$target_time" = "year" ]; then
        find "$LK_DIR/$curr_y" -type f -name "*.md" 2>/dev/null > "$file_list"
        lks_scope="Yearly Scope ($curr_y)"
    elif echo "$target_time" | grep -qE "^[0-9]{4}$"; then
        find "$LK_DIR/$target_time" -type f -name "*.md" 2>/dev/null > "$file_list"
        lks_scope="Yearly Scope ($target_time)"
    elif echo "$target_time" | grep -qE "^[0-9]{6}$|^[0-9]{4}-[0-9]{2}$"; then
        if echo "$target_time" | grep -q "-"; then
            y=$(echo "$target_time" | cut -d'-' -f1); m=$(echo "$target_time" | cut -d'-' -f2)
        else
            y=$(echo "$target_time" | cut -c1-4); m=$(echo "$target_time" | cut -c5-6)
        fi
        find "$LK_DIR/$y/$y-$m" -type f -name "*.md" 2>/dev/null > "$file_list"
        lks_scope="Monthly Scope ($y-$m)"
    elif echo "$target_time" | grep -qE "^[0-9]{8}$|^[0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
        if echo "$target_time" | grep -q "-"; then
            y=$(echo "$target_time" | cut -d'-' -f1); m=$(echo "$target_time" | cut -d'-' -f2); d=$(echo "$target_time" | cut -d'-' -f3)
        else
            y=$(echo "$target_time" | cut -c1-4); m=$(echo "$target_time" | cut -c5-6); d=$(echo "$target_time" | cut -c7-8)
        fi
        f="$LK_DIR/$y/$y-$m/$y-$m-$d.md"
        [ -f "$f" ] && echo "$f" > "$file_list"
        lks_scope="Daily Scope ($y-$m-$d)"
    elif echo "$target_time" | grep -qE "^[0-9]{4}-[0-9]{4}$"; then
        sy="${target_time%-*}"; ey="${target_time#*-}"
        for y in $(seq "$sy" "$ey" 2>/dev/null || awk "BEGIN{for(i=$sy;i<=$ey;i++) print i}"); do
            find "$LK_DIR/$y" -type f -name "*.md" 2>/dev/null >> "$file_list"
        done
        lks_scope="Yearly Range ($sy to $ey)"
    elif echo "$target_time" | grep -qE "^[0-9]{8}-[0-9]{8}$|^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
        if echo "$target_time" | grep -qE "^[0-9]{8}-[0-9]{8}$"; then
            start_date="${target_time%-*}"; end_date="${target_time#*-}"
            sy=$(echo "$start_date" | cut -c1-4); sm=$(echo "$start_date" | cut -c5-6); sd=$(echo "$start_date" | cut -c7-8)
            ey=$(echo "$end_date" | cut -c1-4); em=$(echo "$end_date" | cut -c5-6); ed=$(echo "$end_date" | cut -c7-8)
        else
            start_date=$(echo "$target_time" | cut -d'-' -f1-3)
            end_date=$(echo "$target_time" | cut -d'-' -f4-6)
            sy=$(echo "$start_date" | cut -d'-' -f1); sm=$(echo "$start_date" | cut -d'-' -f2); sd=$(echo "$start_date" | cut -d'-' -f3)
            ey=$(echo "$end_date" | cut -d'-' -f1); em=$(echo "$end_date" | cut -d'-' -f2); ed=$(echo "$end_date" | cut -d'-' -f3)
        fi
        curr="$sy-$sm-$sd"
        end="$ey-$em-$ed"
        lks_scope="Range $curr to $end"
        
        while [ "$curr" != "$(date -I -d "$end + 1 day" 2>/dev/null)" ]; do
            cy=$(echo "$curr" | cut -d'-' -f1); cm=$(echo "$curr" | cut -d'-' -f2)
            f="$LK_DIR/$cy/$cy-$cm/$curr.md"
            [ -f "$f" ] && echo "$f" >> "$file_list"
            curr=$(date -I -d "$curr + 1 day" 2>/dev/null)
        done
    else
        printf "%b[Error]%b Invalid time target format.\n" "$LK_RED" "$LK_RESET"
        rm -f "$file_list"
        return 1
    fi

    # Sort files chronologically
    sort -o "$file_list" "$file_list"
    total_days=$(wc -l < "$file_list")
    
    if [ "$total_days" -eq 0 ]; then
        printf "\033[31m[Void]\033[0m No timeline found. The genesis has not begun.\n"
        rm -f "$file_list"
        return 0
    fi

    genesis_file=$(head -n 1 "$file_list")
    zenith_file=$(tail -n 1 "$file_list")
    genesis_dt=$(basename "$genesis_file" .md)
    zenith_dt=$(basename "$zenith_file" .md)

    printf "%b--- Aligning the Pillars of Time... ---%b\r" "$LK_MAGENTA" "$LK_RESET"

    # --- 4. The Monolithic AWK Engine (Analytics + Charting) ---
    LC_ALL=C awk -v days="$total_days" -v gen="$genesis_dt" -v zen="$zenith_dt" -v scope="$lks_scope" -v mode="$sort_mode" '
    BEGIN {
        RESET   = "\033[0m"
        CYAN    = "\033[38;2;0;255;255m"
        LIME    = "\033[38;2;100;255;0m"
        GREY    = "\033[38;2;150;150;150m"
        DARK    = "\033[38;2;80;80;80m"
        RED     = "\033[38;2;255;50;50m"
        AMBER   = "\033[38;2;255;204;0m"
        ORANGE  = "\033[38;2;255;102;0m"
        MAGENTA = "\033[38;2;255;100;255m"
        HEADER  = "\033[38;2;255;117;0m"
        GOLD    = "\033[38;2;255;215;0m"
        
        total_pulses = 0
        captured_hours = 0
        
        for (i=0; i<=23; i++) {
            hr = sprintf("%02d", i)
            pulse_hours[hr] = 0
        }
    }
    
    function comma(n,    r) {
        r = ""
        while(n > 999) {
            r = sprintf(",%03d%s", n % 1000, r)
            n = int(n / 1000)
        }
        return n r
    }

    {
        file = $0
        while ((getline line < file) > 0) {
            if (line ~ /^[ \t]*- ([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9] -/) {
                total_pulses++
                
                match(line, /([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]/)
                if (RSTART > 0) {
                    hr = substr(line, RSTART, 2)
                    pulse_hours[hr]++
                    
                    block_id = file "|" hr
                    if (!seen_blocks[block_id]) {
                        seen_blocks[block_id] = 1
                        captured_hours++
                    }
                }
            }
        }
        close(file)
    }
    
    END {
        printf "\033[2K\r"
        
        # Sacred Mathematics
        mortal_quota = days * 24
        void_hours = mortal_quota - captured_hours
        
        if (days > 0) avg_hr_per_day = captured_hours / days
        else avg_hr_per_day = 0
        
        if (captured_hours > 0) temporal_cohesion = total_pulses / captured_hours
        else temporal_cohesion = 0
        
        if (mortal_quota > 0) retention_pct = (captured_hours / mortal_quota) * 100
        else retention_pct = 0

        # Determine Title
        if (retention_pct < 10.0) cult_rank = "Drifter of the Cycle"
        else if (retention_pct < 25.0) cult_rank = "Warden of the Watch"
        else if (retention_pct < 50.0) cult_rank = "Master of the Dial"
        else cult_rank = "Architect of Chronos"

        # ---------------------------------------------------------
        # THE ALTAR DISPLAY (ANALYTICS)
        # ---------------------------------------------------------
        print HEADER "||=======================================================||" RESET
        print HEADER "|| " GOLD "LK (LogKlerk) --- CHRONOMETRIC HOUR ANALYZER" HEADER "          ||" RESET
        print HEADER "||=======================================================||" RESET
        print "  " GREY "Domain  : " RESET AMBER "[[" gen "]]" RESET GREY " to " RESET CYAN "[[" zen "]]" RESET
        print "  " GREY "Scope   : " RESET scope
        print "  " GREY "Status  : " MAGENTA cult_rank RESET "\n"

        print "  " HEADER "✦ THE MORTAL QUOTA (PILLARS)" RESET
        print "    " GREY "Active Days Recorded : " RESET CYAN comma(days) " Days" RESET
        print "    " GREY "Total Usable Pillars : " RESET AMBER comma(mortal_quota) " Hours " RESET GREY "(24h / day)" RESET "\n"

        print "  " HEADER "✦ THE SACRED CAPTURE" RESET
        print "    " GREY "Hours Mastered       : " RESET LIME comma(captured_hours) " Pillars Claimed" RESET
        print "    " GREY "Chronological Void   : " RESET RED comma(void_hours) " Pillars Lost to the Void" RESET
        print "    " GREY "Average Pillars/Day  : " RESET CYAN sprintf("%.1f", avg_hr_per_day) " Hours/Day" RESET
        print "    " GREY "Temporal Cohesion    : " RESET GOLD sprintf("%.2f", temporal_cohesion) " Pulses per Hour" RESET "\n"

        # Progress Bar Generator
        bar_len = 40
        filled = int((retention_pct / 100.0) * bar_len) 
        if (filled > bar_len) filled = bar_len
        if (filled == 0 && captured_hours > 0) filled = 1
        
        bar_str = ""
        for(i=1; i<=filled; i++) bar_str = bar_str "█"
        for(i=filled+1; i<=bar_len; i++) bar_str = bar_str "·"

        print "  " HEADER "✦ PILLAR RETENTION RATE" RESET
        print "    " LIME sprintf("%.2f%%", retention_pct) RESET " " GREY "[" RESET CYAN bar_str RESET GREY "]" RESET "\n"

        # ---------------------------------------------------------
        # THE 24-HOUR DENSITY CHART (BUBBLE SORT ENGINE)
        # ---------------------------------------------------------
        if (mode == "chrono") title = "Chronological 24-Hour Distribution"
        else title = "Ranked by Activity Volume"
        
        print "  " PURPLE "✦ [ " title " ] ✦" RESET
        
        max_v = 0
        for (i=0; i<=23; i++) {
            hr = sprintf("%02d", i)
            idx[i+1] = hr
            if (pulse_hours[hr] > max_v) max_v = pulse_hours[hr]
        }
        
        # In-Memory Bubble Sort for Rank Mode
        if (mode == "rank") {
            for (i=1; i<=24; i++) {
                for (j=i+1; j<=24; j++) {
                    if (pulse_hours[idx[i]] < pulse_hours[idx[j]]) {
                        tmp = idx[i]
                        idx[i] = idx[j]
                        idx[j] = tmp
                    }
                }
            }
        }
        
        rank = 1
        for (i=1; i<=24; i++) {
            hour = idx[i]
            count = pulse_hours[hour]
            
            c_bar_len = 0
            if (max_v > 0) c_bar_len = int((count / max_v) * 30)
            
            c_bar_str = ""
            for (b=0; b<c_bar_len; b++) c_bar_str = c_bar_str "█"
            for (b=c_bar_len; b<30; b++) c_bar_str = c_bar_str " "
            
            bar_color = DARK
            if (count == max_v && count > 0) bar_color = ORANGE
            else if (count > (max_v * 0.7)) bar_color = CYAN
            else if (count > (max_v * 0.3)) bar_color = GREY
            
            if (mode == "rank") {
                rank_color = GREY
                if (rank == 1) rank_color = ORANGE
                else if (rank <= 3) rank_color = CYAN
                printf "   %s%02d%s | %s%s:xx%s | %s%s%s %s(%d pulses)%s\n", rank_color, rank, RESET, CYAN, hour, RESET, bar_color, c_bar_str, RESET, GREY, count, RESET
            } else {
                printf "   %s%s:xx%s | %s%s%s %s(%d pulses)%s\n", CYAN, hour, RESET, bar_color, c_bar_str, RESET, GREY, count, RESET
            }
            rank++
        }
        print HEADER "-----------------------------------------------------------" RESET
    }' "$file_list"

    rm -f "$file_list"
}
