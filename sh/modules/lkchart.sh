#!/bin/sh
# Module: lkchart (LogKlerk Visualization Engine - Word Centric, Lines Info, Contextual Theme)
# Updated to v0.0.5: Zero-Subshell Rendering, Native AWK UI, m/d shortcuts, & Concatenation Fix

lkchart() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    # =========================================================================
    # GLOBAL SHELL COLOR (ONLY FOR HELP MENU, NO SUBSHELLS)
    # =========================================================================
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_PURPLE='\033[38;2;170;100;255m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_AMBER='\033[38;2;255;204;0m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_HEADER_ORG='\033[38;2;255;117;0m'
    LK_RED='\033[31m'
    # =========================================================================

    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Error]%b LK Vault (%s) not found.\n" "$LK_RED" "$LK_RESET" "$LK_DIR"
        return 1
    fi

    curr_y=$(date +%Y)
    curr_m=$(date +%Y-%m)
    curr_d=$(date +%d)

    # --- 2. HELP MENU (DEFAULT ROUTE) ---
    if [ $# -eq 0 ] || [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        printf "%b| LK (LogKlerk) --- Visualization Engine Help ---%b\n" "$LK_HEADER_ORG" "$LK_RESET"
        printf "Usage: lkchart [mode]\n\n"
        printf "%b[Shortcuts]%b\n" "$LK_LIME" "$LK_RESET"
        printf "  %bm, month%b      : Daily chart for the current month (Default scope)\n" "$LK_CYAN" "$LK_RESET"
        printf "  %bd, day%b        : Hourly chart for the current day\n\n" "$LK_AMBER" "$LK_RESET"
        printf "%b[Global Modes]%b\n" "$LK_LIME" "$LK_RESET"
        printf "  y, year       : Global yearly chart\n"
        printf "  ym, yyyymm    : Global monthly chart\n"
        printf "  ymd, yyyymmdd : Global daily chart\n\n"
        printf "%b[Scoped Modes]%b\n" "$LK_LIME" "$LK_RESET"
        printf "  YYYY          : Monthly chart for a specific year\n"
        printf "  YYYYMM        : Daily chart for a specific month\n"
        printf "  YYYYMMDD      : Hourly chart for a specific day\n\n"
        return 0
    fi

    # --- 3. TIME SCOPE & ROUTER ---
    chart_mode=""
    find_dir=""
    find_pattern=""
    title_scope=""
    target_file=""

    case "$1" in
        m|month|-m|--month) 
            chart_mode="DAILY_SCOPED"
            find_dir="$LK_DIR/$curr_y/$curr_m"
            find_pattern="${curr_m}-[0-9][0-9].md"
            title_scope="$curr_m"
            gl=10
            ;;
        d|day|-d|--day) 
            chart_mode="HOURLY_SCOPED"
            target_date="$curr_m-$curr_d"
            target_file="$LK_DIR/$curr_y/$curr_m/${target_date}.md"
            title_scope="$target_date"
            ;;
        -y|-Y|y|Y|yyyy|YYYY|year|-year|--year) 
            chart_mode="YEARLY"
            find_dir="$LK_DIR"
            find_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
            gl=4
            title="Global Yearly Matrix"
            ;;
        -ym|-YM|ym|YM|yyyymm|YYYYMM) 
            chart_mode="MONTHLY"
            find_dir="$LK_DIR"
            find_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
            gl=7
            title="Global Monthly Matrix"
            ;;
        -ymd|-YMD|ymd|YMD|yyyymmdd|YYYYMMDD) 
            chart_mode="DAILY"
            find_dir="$LK_DIR"
            find_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
            gl=10
            title="Global Daily Genesis Matrix"
            ;;
        [0-9][0-9][0-9][0-9])
            chart_mode="MONTHLY_SCOPED"
            find_dir="$LK_DIR/$1"
            find_pattern="$1-[0-9][0-9]-[0-9][0-9].md"
            title_scope="$1"
            gl=7
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
            chart_mode="DAILY_SCOPED"
            if [ "${#1}" -eq 6 ]; then
                y="${1%??}"; m="${1#????}"
            else
                y="${1%-*}"; m="${1#*-}"
            fi
            find_dir="$LK_DIR/$y/$y-$m"
            find_pattern="$y-$m-[0-9][0-9].md"
            title_scope="$y-$m"
            gl=10
            ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            chart_mode="HOURLY_SCOPED"
            if [ "${#1}" -eq 8 ]; then
                y="${1%????}"; m_d="${1#????}"; m="${m_d%??}"; d="${m_d#??}"
                target_date="$y-$m-$d"
            else
                target_date="$1"
            fi
            y="${target_date%%-*}"
            m_d="${target_date#*-}"; m="${m_d%%-*}"
            target_file="$LK_DIR/$y/$y-$m/${target_date}.md"
            title_scope="$target_date"
            ;;
        *)
            printf "%b[Error]%b Unknown mode '%s'. Type 'lkchart' for help.\n" "$LK_RED" "$LK_RESET" "$1"
            return 1
            ;;
    esac

    if [ "$chart_mode" = "MONTHLY_SCOPED" ]; then title="Monthly Matrix Scope ($title_scope)"
    elif [ "$chart_mode" = "DAILY_SCOPED" ]; then title="Daily Matrix Scope ($title_scope)"
    elif [ "$chart_mode" = "HOURLY_SCOPED" ]; then title="Hourly Execution Matrix ($title_scope)"
    fi

    printf "%b--- Rendering %s... ---%b\r" "$LK_CYAN" "$title" "$LK_RESET"

    # --- 4. RENDER ENGINE (PURE AWK PIPELINE) ---
    render_awk='
    BEGIN {
        RESET       = "\033[0m"
        CYAN        = "\033[38;2;0;255;255m"
        LIME        = "\033[38;2;100;255;0m"
        PURPLE      = "\033[38;2;170;100;255m"
        GREY        = "\033[38;2;150;150;150m"
        DARKGREY    = "\033[38;2;90;90;90m"
        AMBER       = "\033[38;2;255;204;0m"
        ORANGE      = "\033[38;2;255;102;0m"
        HEADER_ORG  = "\033[38;2;255;117;0m"
        RED         = "\033[31m"
        
        max_words = 0
        count = 0
    }
    {
        split($0, arr, "~")
        pfx[count] = arr[1]
        wds[count] = arr[2] + 0
        lns[count] = arr[3] + 0
        if (wds[count] > max_words) max_words = wds[count]
        count++
    }
    END {
        print "\n" HEADER_ORG "| LK (LogKlerk) --- Visualization Engine ---" RESET
        print "  " PURPLE "[ " title " (By Word Volume) ]" RESET "\n"
        
        if (count == 0) {
            print "    " RED "[Error]" RESET " No data found to chart."
            exit
        }
        
        curr_year = ""
        year_words = 0
        year_lines = 0
        
        for (i = 0; i < count; i++) {
            prefix = pfx[i]
            words = wds[i]
            lines_val = lns[i]
            
            if (mode == "MONTHLY") {
                this_year = substr(prefix, 1, 4)
                if (curr_year != "" && this_year != curr_year) {
                    print "    " DARKGREY "----------------------------------------" RESET
                    print "    " AMBER "=== [[ " curr_year " ]] Total Contribution: " CYAN year_words " words " DARKGREY "| " year_lines " lines ===" RESET
                    print "    " DARKGREY "----------------------------------------" RESET
                    year_words = 0
                    year_lines = 0
                }
                curr_year = this_year
                year_words += words
                year_lines += lines_val
            }
            
            bar_blocks = int((words * 30) / max_words)
            if (bar_blocks == 0 && words > 0) bar_blocks = 1
            
            chart_bar = ""
            for (b = 0; b < bar_blocks; b++) chart_bar = chart_bar "#"
            
            if (mode == "HOURLY_SCOPED") {
                printf "    %s[[%s]]%s %s%-30s%s %s%-11s%s %s| %s lines%s\n", CYAN, prefix, RESET, LIME, chart_bar, RESET, ORANGE, words " words", RESET, DARKGREY, lines_val, RESET
            } else {
                printf "    %s[[%s]]%s %s%-30s%s %s%-11s%s %s| %s lines%s\n", AMBER, prefix, RESET, ORANGE, chart_bar, RESET, CYAN, words " words", RESET, DARKGREY, lines_val, RESET
            }
        }
        
        if (mode == "MONTHLY" && curr_year != "") {
            print "    " DARKGREY "----------------------------------------" RESET
            print "    " AMBER "=== [[ " curr_year " ]] Total Contribution: " CYAN year_words " words " DARKGREY "| " year_lines " lines ===" RESET
            print "    " DARKGREY "----------------------------------------" RESET
        }
        
        print "\n" HEADER_ORG "-------------------------------------------------------" RESET "\n"
    }
    '

    # --- 5. EXECUTION ROUTING (EXTRACT -> SORT -> RENDER) ---
    if [ "$chart_mode" = "HOURLY_SCOPED" ]; then
        if [ ! -f "$target_file" ]; then
            printf "\033[2K\r%b[Error]%b Log file for %s not found.\n" "$LK_RED" "$LK_RESET" "$target_date"
            return 1
        fi
        
        LC_ALL=C awk '
        /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
            if (match($0, /[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/)) {
                ts = substr($0, RSTART, 8)
                hh = substr(ts, 1, 2)
            } else { hh = "00" }
            gsub(/^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - /, "", $0)
            cw[hh] += NF
            cl[hh] += 1
        }
        END { for (h in cw) print h ":00~" cw[h] "~" cl[h] }
        ' "$target_file" | sort | LC_ALL=C awk -v mode="$chart_mode" -v title="$title" "$render_awk"
        
    else
        if [ ! -d "$find_dir" ]; then
            printf "\033[2K\r%b[Error]%b Log directory for %s not found.\n" "$LK_RED" "$LK_RESET" "$title_scope"
            return 1
        fi

        find "$find_dir" -type f -name "$find_pattern" -exec wc {} + 2>/dev/null | grep -v " total$" | LC_ALL=C awk -v gl="$gl" '
        {
            lines = $1; words = $2; path = $4
            n = split(path, a, "/"); filename = a[n]
            if (filename ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$/) {
                pfx = substr(filename, 1, gl)
                cw[pfx] += words
                cl[pfx] += lines
            }
        }
        END { for (p in cw) print p "~" cw[p] "~" cl[p] }
        ' | sort | LC_ALL=C awk -v mode="$chart_mode" -v title="$title" "$render_awk"
    fi
}
