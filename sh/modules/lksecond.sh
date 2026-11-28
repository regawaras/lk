#!/bin/sh
# Module: lksecond (LogKlerk Chronometric Micro-Analyzer)
# Function: Temporal Entropy & Second-Level Pulse Extraction
# Vibe: Cybernetic Cult of the Time God

lksecond() {
    # --- 1. Environment & Configuration ---
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

    # Global Colors for Initial Output
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_MAGENTA='\033[38;2;255;100;255m'

    printf "%b--- Awakening the Chronometric Engine... ---%b\r" "$LK_MAGENTA" "$LK_RESET"

    # --- 2. Temporal Mass Gathering ---
    file_list=$(mktemp)
    find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" | sort > "$file_list"
    
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

    # --- 3. The Ritual of Extraction (AWK Engine) ---
    xargs cat 2>/dev/null < "$file_list" | LC_ALL=C awk -v days="$total_days" -v gen="$genesis_dt" -v zen="$zenith_dt" '
    BEGIN {
        RESET   = "\033[0m"
        CYAN    = "\033[38;2;0;255;255m"
        LIME    = "\033[38;2;100;255;0m"
        GREY    = "\033[38;2;150;150;150m"
        RED     = "\033[38;2;255;50;50m"
        AMBER   = "\033[38;2;255;204;0m"
        MAGENTA = "\033[38;2;255;100;255m"
        HEADER  = "\033[38;2;255;117;0m"
        GOLD    = "\033[38;2;255;215;0m"
        
        total_pulses = 0
    }
    
    # Comma formatter for big numbers (Zero-dependency)
    function comma(n,    r) {
        r = ""
        while(n > 999) {
            r = sprintf(",%03d%s", n % 1000, r)
            n = int(n / 1000)
        }
        return n r
    }

    # Pulse Catcher (Extract exactly HH:MM:SS format)
    /^[ \t]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] -/ {
        total_pulses++
        
        match($0, /[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/)
        if (RSTART > 0) {
            hr = substr($0, RSTART, 2)
            hour_counts[hr]++
        }
    }
    
    END {
        printf "\033[2K\r"
        
        # Sacred Mathematics
        mortal_quota = days * 86400
        void_seconds = mortal_quota - total_pulses
        
        if (days > 0) avg_pulse = total_pulses / days
        else avg_pulse = 0
        
        if (mortal_quota > 0) retention_pct = (total_pulses / mortal_quota) * 100
        else retention_pct = 0

        # Find the Apex Hour (Hour with most pulses)
        max_pulse = 0
        apex_hr = "00"
        for (h in hour_counts) {
            if (hour_counts[h] > max_pulse) {
                max_pulse = hour_counts[h]
                apex_hr = h
            }
        }
        
        # Determine Title
        if (retention_pct < 0.1) cult_rank = "Initiate of the Void"
        else if (retention_pct < 0.5) cult_rank = "Acolyte of Seconds"
        else if (retention_pct < 1.0) cult_rank = "Weaver of the Timeline"
        else cult_rank = "Architect of Chronos"

        # The Altar Display
        print HEADER "||=======================================================||" RESET
        print HEADER "|| " GOLD "LK (LogKlerk) --- CHRONOMETRIC MASS ANALYZER" HEADER "        ||" RESET
        print HEADER "||=======================================================||" RESET
        print "  " GREY "Domain  : Genesis " RESET AMBER "[[" gen "]]" RESET GREY " to Zenith " RESET CYAN "[[" zen "]]" RESET
        print "  " GREY "Status  : " MAGENTA cult_rank RESET "\n"

        print "  " HEADER "✦ THE MORTAL QUOTA" RESET
        print "    " GREY "Active Days Recorded : " RESET CYAN comma(days) " Days" RESET
        print "    " GREY "Total Usable Seconds : " RESET AMBER comma(mortal_quota) " Sec " RESET GREY "(86,400s / day)" RESET "\n"

        print "  " HEADER "✦ THE SACRED CAPTURE" RESET
        print "    " GREY "Captured Pulses      : " RESET LIME comma(total_pulses) " Seconds Defied Entropy" RESET
        print "    " GREY "Chronological Void   : " RESET RED comma(void_seconds) " Seconds Lost to the Void" RESET
        print "    " GREY "Average Capture/Day  : " RESET CYAN sprintf("%.2f", avg_pulse) " Seconds/Day" RESET
        print "    " GREY "Apex Hour (Densest)  : " RESET MAGENTA apex_hr ":00 " RESET GREY "(" comma(max_pulse) " pulses localized here)" RESET "\n"

        # Progress Bar Generator
        bar_len = 40
        filled = int((retention_pct / 1.0) * bar_len) # Normalize visual to 1% max scale for aesthetics
        if (filled > bar_len) filled = bar_len
        if (filled == 0 && total_pulses > 0) filled = 1
        
        bar_str = ""
        for(i=1; i<=filled; i++) bar_str = bar_str "█"
        for(i=filled+1; i<=bar_len; i++) bar_str = bar_str "·"

        print "  " HEADER "✦ PULSE RETENTION RATE" RESET
        print "    " LIME sprintf("%.3f%%", retention_pct) RESET " " GREY "[" RESET CYAN bar_str RESET GREY "]" RESET
        
        if (retention_pct < 0.05) {
            print "\n    " RED "WARNING: Heavy entropy detected. Time is bleeding." RESET
        } else {
            print "\n    " LIME "Entropy contained. The Timeline acknowledges your effort." RESET
        }
        print HEADER "-----------------------------------------------------------" RESET
    }'

    rm -f "$file_list"
}
