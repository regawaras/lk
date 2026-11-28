#!/bin/sh
# Module: lkminute (LogKlerk Chronometric Minute Analyzer)
# Function: Temporal Block Aggregation & Cohesion Density
# Vibe: Cybernetic Cult of the Time God (Block Architecture)

lkminute() {
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

    # Global Colors
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_MAGENTA='\033[38;2;255;100;255m'

    printf "%b--- Forging the Minute Blocks... ---%b\r" "$LK_MAGENTA" "$LK_RESET"

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

    # --- 3. The Ritual of Block Extraction (Direct AWK Engine) ---
    LC_ALL=C awk -v days="$total_days" -v gen="$genesis_dt" -v zen="$zenith_dt" '
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
        captured_minutes = 0
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
            if (line ~ /^[ \t]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] -/) {
                total_pulses++
                
                # Extract HH:MM
                match(line, /[0-2][0-9]:[0-5][0-9]/)
                if (RSTART > 0) {
                    hhmm = substr(line, RSTART, 5)
                    
                    # Create a unique temporal block ID (File + HH:MM)
                    block_id = file "|" hhmm
                    
                    if (!seen_blocks[block_id]) {
                        seen_blocks[block_id] = 1
                        captured_minutes++
                        minute_freq[hhmm]++
                    }
                }
            }
        }
        close(file)
    }
    
    END {
        printf "\033[2K\r"
        
        # Sacred Mathematics
        mortal_quota = days * 1440
        void_minutes = mortal_quota - captured_minutes
        
        if (days > 0) avg_min_per_day = captured_minutes / days
        else avg_min_per_day = 0
        
        if (captured_minutes > 0) temporal_cohesion = total_pulses / captured_minutes
        else temporal_cohesion = 0
        
        if (mortal_quota > 0) retention_pct = (captured_minutes / mortal_quota) * 100
        else retention_pct = 0

        # Find the Apex Minute (Most consistent minute across all days)
        max_freq = 0
        apex_mm = "00:00"
        for (m in minute_freq) {
            if (minute_freq[m] > max_freq) {
                max_freq = minute_freq[m]
                apex_mm = m
            }
        }
        
        # Determine Title
        if (retention_pct < 1.0) cult_rank = "Drifter of the 60th Fraction"
        else if (retention_pct < 5.0) cult_rank = "Warden of the Blocks"
        else if (retention_pct < 10.0) cult_rank = "Weaver of the Minute Hand"
        else cult_rank = "Architect of the Hourglass"

        # The Altar Display
        print HEADER "||=======================================================||" RESET
        print HEADER "|| " GOLD "LK (LogKlerk) --- CHRONOMETRIC MINUTE ANALYZER" HEADER "        ||" RESET
        print HEADER "||=======================================================||" RESET
        print "  " GREY "Domain  : Genesis " RESET AMBER "[[" gen "]]" RESET GREY " to Zenith " RESET CYAN "[[" zen "]]" RESET
        print "  " GREY "Status  : " MAGENTA cult_rank RESET "\n"

        print "  " HEADER "✦ THE MORTAL QUOTA (BLOCKS)" RESET
        print "    " GREY "Active Days Recorded : " RESET CYAN comma(days) " Days" RESET
        print "    " GREY "Total Usable Minutes : " RESET AMBER comma(mortal_quota) " Mins " RESET GREY "(1,440m / day)" RESET "\n"

        print "  " HEADER "✦ THE SACRED CAPTURE" RESET
        print "    " GREY "Minutes Mastered     : " RESET LIME comma(captured_minutes) " Blocks Claimed" RESET
        print "    " GREY "Chronological Void   : " RESET RED comma(void_minutes) " Blocks Lost to the Void" RESET
        print "    " GREY "Average Blocks/Day   : " RESET CYAN sprintf("%.1f", avg_min_per_day) " Minutes/Day" RESET
        print "    " GREY "Temporal Cohesion    : " RESET GOLD sprintf("%.2f", temporal_cohesion) " Pulses per Minute" RESET
        print "    " GREY "Apex Minute (Peak)   : " RESET MAGENTA apex_mm " " RESET GREY "(" comma(max_freq) " days captured this exact minute)" RESET "\n"

        # Progress Bar Generator
        bar_len = 40
        # Normalize visual to 5% max scale for aesthetics (since filling 1440 mins is impossible for a human)
        filled = int((retention_pct / 5.0) * bar_len) 
        if (filled > bar_len) filled = bar_len
        if (filled == 0 && captured_minutes > 0) filled = 1
        
        bar_str = ""
        for(i=1; i<=filled; i++) bar_str = bar_str "█"
        for(i=filled+1; i<=bar_len; i++) bar_str = bar_str "·"

        print "  " HEADER "✦ MINUTE RETENTION RATE" RESET
        print "    " LIME sprintf("%.2f%%", retention_pct) RESET " " GREY "[" RESET CYAN bar_str RESET GREY "]" RESET
        
        if (temporal_cohesion > 1.5) {
            print "\n    " GOLD "High Cohesion: You log in dense, hyper-focused bursts." RESET
        } else {
            print "\n    " LIME "Steady Flow: Your consciousness is evenly spread across time." RESET
        }
        print HEADER "-----------------------------------------------------------" RESET
    }' "$file_list"

    rm -f "$file_list"
}
