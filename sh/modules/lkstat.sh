#!/bin/sh
# Module: lkstat (LogKlerk Universal Analytics Engine)
# Updated to v0.0.6: Cybernetic vs Biological Word Separation (Pure Manual Parsing)
# POSIX Strict Version (Dash Compatible)

lkstat() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.6}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    # =========================================================================
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_PURPLE='\033[38;2;170;100;255m'
    LK_ORANGE='\033[38;2;255;102;0m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_HEADER_ORG='\033[38;2;255;117;0m'
    LK_RED='\033[31m'
    LK_MAGENTA='\033[38;2;255;100;255m'
    # =========================================================================

    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Error]%b LK Vault (%s) not found.\n" "$LK_ORANGE" "$LK_RESET" "$LK_DIR"
        return 1
    fi

    # --- 2. TIME SCOPE PARSER ---
    lks_scope="Global Lifetime"
    lks_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
    lks_month_days=30
    is_month_scope=0
    find_dir="$LK_DIR"

    if [ -n "$1" ]; then
        case "$1" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9])
                lks_range_start="${1%-*}"
                lks_range_end="${1#*-}"
                lks_scope="Yearly Range ($lks_range_start to $lks_range_end)"
                find_dir="$LK_DIR"
                ;;
            [0-9][0-9][0-9][0-9])
                find_dir="$LK_DIR/$1"
                lks_pattern="$1-[0-9][0-9]-[0-9][0-9].md"
                lks_scope="Yearly Scope ($1)"
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
                if [ "${#1}" -eq 6 ]; then
                    y="${1%??}"; m="${1#????}"
                else
                    y="${1%-*}"; m="${1#*-}"
                fi
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="$y-$m-[0-9][0-9].md"
                lks_scope="Monthly Scope ($y-$m)"
                is_month_scope=1
                lks_month_days=$(cal "$m" "$y" 2>/dev/null | awk 'NF {DAYS = $NF}; END {print DAYS}')
                [ -z "$lks_month_days" ] && lks_month_days=30
                ;;
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                if [ "${#1}" -eq 8 ]; then
                    y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
                    target_date="$y-$m-$d"
                else
                    target_date="$1"
                fi
                y="${target_date%%-*}"
                m_d="${target_date#*-}"; m="${m_d%%-*}"
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="${target_date}.md"
                lks_scope="Daily Scope ($target_date)"
                ;;
            *)
                printf "%b[Error]%b Invalid scope. Use YYYY, YYYY-MM, YYYY-MM-DD, or YYYY-YYYY.\n" "$LK_RED" "$LK_RESET"
                return 1
                ;;
        esac
    fi

    printf "%b--- Initializing Quantum Analytics for %s... ---%b\r" "$LK_CYAN" "$lks_scope" "$LK_RESET"

    # --- 3. FAST GLOBAL BASELINE (Single Pass) ---
    sys_genesis=$(find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" 2>/dev/null | sort | head -n 1 | awk -F'/' '{print $NF}' | sed 's/\.md//')
    [ -z "$sys_genesis" ] && sys_genesis="Unknown"

    gl_data=$(find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" 2>/dev/null | LC_ALL=C awk '
    {
        f++
        while((getline l < $0) > 0) w += split(l, a, " ")
        close($0)
    }
    END { print f+0, w+0 }')
    
    gl_files="${gl_data% *}"
    gl_words="${gl_data#* }"

    # --- 4. THE ULTIMATE AWK PIPELINE ---
    if echo "$lks_scope" | grep -q "Yearly Range"; then
        cmd="for y in \$(seq $lks_range_start $lks_range_end 2>/dev/null || awk 'BEGIN{for(i=$lks_range_start;i<=$lks_range_end;i++) print i}'); do find \"$LK_DIR/\$y\" -type f -name \"\${y}-[0-9][0-9]-[0-9][0-9].md\" 2>/dev/null; done"
    else
        cmd="find \"$find_dir\" -type f -name \"$lks_pattern\" 2>/dev/null"
    fi

    eval "$cmd" | sort | LC_ALL=C awk -v scope="$lks_scope" -v m_days="$lks_month_days" -v is_mo="$is_month_scope" -v gl_words="$gl_words" -v gl_files="$gl_files" -v genesis="$sys_genesis" '
    BEGIN {
        RESET       = "\033[0m"
        CYAN        = "\033[38;2;0;255;255m"
        LIME        = "\033[38;2;100;255;0m"
        PURPLE      = "\033[38;2;170;100;255m"
        ORANGE      = "\033[38;2;255;102;0m"
        GREY        = "\033[38;2;150;150;150m"
        AMBER       = "\033[38;2;255;204;0m"
        HEADER_ORG  = "\033[38;2;255;117;0m"
        RED         = "\033[31m"
        MAGENTA     = "\033[38;2;255;100;255m"
        
        pref_idx = 0
        total_raw_words = 0
        total_man_words = 0
        total_auto_words = 0
    }
    {
        file = $0
        scoped_files++
        file_man_words = 0
        file_lines = 0
        
        n = split(file, a, "/")
        fname = a[n]
        date_str = substr(fname, 1, 10)

        # In-RAM File Processing
        while ((getline line < file) > 0) {
            file_lines++
            raw_nf = split(line, temp_raw, " ")
            
            # --- THE AUTOMATION PURIFIER (RegEx Stripping) ---
            man_line = line
            
            # 1. Strip Interstitial Timestamps: "    - 15:44:28 - "
            gsub(/^[[:space:]]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] -[[:space:]]*/, "", man_line)
            
            # 2. Strip Hourly Headers: "    - ## 15:00 - "
            gsub(/^[[:space:]]*- ## [0-2][0-9]:00 -[[:space:]]*/, "", man_line)
            
            # 3. Strip Taxonomy Context: "[[Brave gemini.google.com]] >> "
            gsub(/\[\[[^\]]+\]\] >>[[:space:]]*/, "", man_line)
            
            # 4. Strip Custom Tags: "![Brave gemini.google.com]! "
            gsub(/!\[[^\]]+\]![[:space:]]*/, "", man_line)
            
            # 5. Strip Daily Summaries Headers: "- # [[2026-05-15]] - "
            gsub(/^[[:space:]]*- #* ?\[\[[^\]]+\]\] -[[:space:]]*/, "", man_line)

            # Hitung jumlah kata murni setelah dibersihkan
            man_nf = split(man_line, words_arr, " ")
            auto_nf = raw_nf - man_nf
            if (auto_nf < 0) auto_nf = 0
            
            # Global Counters
            total_raw_words += raw_nf
            total_man_words += man_nf
            total_auto_words += auto_nf
            file_man_words += man_nf
            
            # --- Behavioral Extractors (Using RAW line) ---
            if (line ~ /^[[:space:]]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - /) {
                match(line, /[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/)
                hr = substr(line, RSTART, 2)
                hour_counts[hr]++
                total_logs++
            }
            
            tmp_line = line
            while (match(tmp_line, /!\[[^\]]+\]!/)) {
                tag = substr(tmp_line, RSTART+2, RLENGTH-4)
                if (tag != "PLAN") tags[tag]++ 
                tmp_line = substr(tmp_line, RSTART+RLENGTH)
            }
            
            tmp_line = line
            while (match(tmp_line, /\[\[[^\]]+\]\] >>/)) {
                tax = substr(tmp_line, RSTART+2, RLENGTH-7)
                if (tax !~ /^[0-9]{4}-[0-9]{2}/) taxonomies[tax]++
                tmp_line = substr(tmp_line, RSTART+RLENGTH)
            }

            # --- Lexical Analysis (Using MANUAL words ONLY) ---
            for (i=1; i<=man_nf; i++) {
                w = words_arr[i]
                if (w ~ /^[a-zA-Z]+$/) pure_w++
                else if (w ~ /^[a-zA-Z0-9]+$/) alpha_w++
                else if (w ~ /\|/) piped_w++
                else sym_w++
            }
        }
        close(file)

        # Track Local Bests (Berdasarkan Kata Manual!)
        if (file_man_words > max_verbose_words) {
            max_verbose_words = file_man_words
            max_verbose_date = date_str
        }
        if (file_lines > max_file_lines) {
            max_file_lines = file_lines
            max_file_name = fname
        }

        # Track Growth (Chronologically Ordered)
        if (scope ~ /Yearly Scope/) gl = 7;
        else if (scope ~ /Monthly Scope/) gl = 10;
        else if (scope ~ /Daily Scope/) gl = 0;
        else gl = 4;

        if (gl > 0) {
            prefix = substr(date_str, 1, gl)
            if (!(prefix in growth)) {
                pref_order[++pref_idx] = prefix
            }
            # Growth matrix menggunakan Raw Words agar selaras dengan gl_words
            growth[prefix] += file_man_words 
            if (growth[prefix] > max_growth_words) max_growth_words = growth[prefix]
        }
    }
    END {
        printf "\033[2K\r\n"
        print HEADER_ORG "| LK (LogKlerk) --- Analytics Engine : " scope " ---" RESET
        
        if (scoped_files == 0) {
            print "  " RED "[Error]" RESET " No data found in this scope."
            exit
        }

        # Calculations
        scope_pct = (gl_words > 0) ? int((total_raw_words * 100) / gl_words) : 0
        man_pct = (total_raw_words > 0) ? int((total_man_words * 100) / total_raw_words) : 0
        auto_pct = 100 - man_pct
        avg_logs = int(total_logs / scoped_files)
        avg_words_per_log = (total_logs > 0) ? int(total_man_words / total_logs) : 0
        
        # 1. Origin & Scale
        print "  " PURPLE "[ 1. Universal Origin & Scale ]" RESET
        print "    System Genesis       : " AMBER genesis RESET " (First recorded entry)"
        print "    Scope Contribution   : " CYAN total_raw_words RESET " raw words (" ORANGE scope_pct "%" RESET " of Global Vault)"
        print "    Scope Active Days    : " CYAN scoped_files RESET " / " GREY gl_files RESET " Global Active Days\n"
        
        # Growth Matrix (Now strictly based on Manual Typing Volume)
        if (gl > 0) {
            print "  " PURPLE "[ Pure Cognitive Growth Matrix (Manual Word Volume) ]" RESET
            for (i=1; i<=pref_idx; i++) {
                p = pref_order[i]
                w = growth[p]
                if (max_growth_words > 0 && w > 0) {
                    bar_len = int((w * 30) / max_growth_words)
                    if (bar_len == 0) bar_len = 1
                    bar = ""
                    for(b=0; b<bar_len; b++) bar = bar "#"
                    printf "    %s[[%s]]%s %s%s%s %s%d words%s\n", GREY, p, RESET, LIME, bar, RESET, CYAN, w, RESET
                }
            }
            print ""
        }

        # 2. Lexical
        print "  " PURPLE "[ 2. Lexical & Verbosity Analysis ]" RESET
        print "    Total Words Recorded : " GREY total_raw_words RESET " words"
        print "      ├── Manual Typed   : " CYAN total_man_words RESET " words (" LIME man_pct "%" RESET " Biological)"
        print "      └── Auto-Generated : " GREY total_auto_words RESET " words (" ORANGE auto_pct "%" RESET " Cybernetic)"
        print "    Manual Lexical Breakdown:"
        print "      ├── Pure Words     : " GREY pure_w+0 RESET " (a-z)"
        print "      ├── Alphanumeric   : " GREY alpha_w+0 RESET " (a-z, 0-9)"
        print "      ├── Piped Phrases  : " LIME piped_w+0 RESET " (x|y|z formatting)"
        print "      └── Sym/Punctuation: " GREY sym_w+0 RESET
        print "    Average Verbosity    : " CYAN avg_words_per_log RESET " manual words / log entry\n"

        # 3. Conceptual Dominance
        print "  " PURPLE "[ 3. Conceptual Dominance (Top Metadata) ]" RESET
        print "    " AMBER "Top Context Tags (![...]):" RESET
        tag_c = 0
        for (k=1; k<=3; k++) {
            max_v = 0; max_k = ""
            for (t in tags) { if (tags[t] > max_v) { max_v = tags[t]; max_k = t } }
            if (max_k != "") {
                printf "      ├── %s%s%s (%s mentions)\n", MAGENTA, max_k, RESET, max_v
                delete tags[max_k]
                tag_c++
            }
        }
        if (tag_c == 0) print "      └── " GREY "None recorded." RESET
        
        print "    " ORANGE "Top Taxonomies ([[...]] >>):" RESET
        tax_c = 0
        for (k=1; k<=3; k++) {
            max_v = 0; max_k = ""
            for (t in taxonomies) { if (taxonomies[t] > max_v) { max_v = taxonomies[t]; max_k = t } }
            if (max_k != "") {
                printf "      ├── %s%s%s (%s mentions)\n", ORANGE, max_k, RESET, max_v
                delete taxonomies[max_k]
                tax_c++
            }
        }
        if (tax_c == 0) print "      └── " GREY "None recorded." RESET
        print ""

        # 4. Local Bests
        print "  " PURPLE "[ 4. Local Bests (Scope Extremes) ]" RESET
        print "    Most Verbose Day     : " CYAN max_verbose_date RESET " (" ORANGE max_verbose_words RESET " manual words)"
        print "    Average Activity     : " CYAN avg_logs RESET " logs / active day"
        print "    Largest Log File     : " CYAN max_file_name RESET " (" GREY max_file_lines RESET " lines)\n"

        # 5. Behavioral
        peak_hr = "N/A"
        peak_count = 0
        for (h in hour_counts) {
            if (hour_counts[h] > peak_count) {
                peak_count = hour_counts[h]; peak_hr = h
            }
        }
        
        persona = "Unknown"
        if (peak_hr != "N/A") {
            hr_num = peak_hr + 0
            if (hr_num >= 22 || hr_num <= 3) persona = "Nocturnal (Night Owl)"
            else if (hr_num >= 4 && hr_num <= 8) persona = "Early Riser (Morning Bird)"
            else if (hr_num >= 9 && hr_num <= 15) persona = "Daylight Worker"
            else persona = "Evening Grinder"
        }

        print "  " PURPLE "[ 5. Behavioral Metrics ]" RESET
        print "    System Persona       : " AMBER persona RESET
        print "    Peak Productivity    : " LIME peak_hr ":xx" RESET " (" peak_count " logs recorded in scope)"
        
        if (is_mo == 1 && m_days > 0) {
            cons = int((scoped_files * 100) / m_days)
            print "    Monthly Consistency  : " CYAN scoped_files "/" m_days RESET " days recorded in " scope
            
            bar_len = 20
            filled = int((cons * bar_len) / 100)
            empty = bar_len - filled
            
            bar_f = ""; for(b=0;b<filled;b++) bar_f = bar_f "#"
            bar_e = ""; for(b=0;b<empty;b++) bar_e = bar_e "-"
            
            print "    Consistency Rate     : [" LIME bar_f GREY bar_e RESET "] " LIME cons "%" RESET
        }

        print "\n" HEADER_ORG "-------------------------------------------------------" RESET "\n"
    }'
}
