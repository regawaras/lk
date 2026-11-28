#!/bin/sh
# Module: lkdistraction (Cognitive Hijack & Dopamine Leak Analytics)
# POSIX Strict Version (Dash & TTY 16-Color Compatible)

lkdistraction() {
    # --- 1. Environment & Configuration ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DISTRACT_FILE="${LK_CONFIG_DIR}/distractions.list"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    # Ensure list file exists
    mkdir -p "$LK_CONFIG_DIR" 2>/dev/null
    touch "$LK_DISTRACT_FILE" 2>/dev/null

    # =========================================================================
    # UNIVERSAL 16-COLOR ANSI (TTY COMPATIBLE)
    # =========================================================================
    LK_RESET='\033[0m'
    LK_RED='\033[31m'
    LK_GREEN='\033[32m'
    LK_YELLOW='\033[33m'
    LK_BLUE='\033[34m'
    LK_MAGENTA='\033[35m'
    LK_CYAN='\033[36m'
    LK_WHITE='\033[37m'
    LK_BRIGHT_RED='\033[91m'
    LK_BRIGHT_YELLOW='\033[93m'
    # =========================================================================

    cmd="$1"
    shift

    case "$cmd" in
        add)
            if [ -z "$1" ]; then
                printf "%b[Error]%b Please provide a distraction pattern (e.g., \"Scrolling on Tiktok\").\n" "$LK_BRIGHT_RED" "$LK_RESET"
                return 1
            fi
            echo "$1" >> "$LK_DISTRACT_FILE"
            printf "%b[Added]%b Cognitive hijack pattern: %b%s%b\n" "$LK_GREEN" "$LK_RESET" "$LK_YELLOW" "$1" "$LK_RESET"
            ;;
        list)
            printf "%b--- Known Cognitive Hijackers (Distraction Patterns) ---%b\n" "$LK_CYAN" "$LK_RESET"
            if [ ! -s "$LK_DISTRACT_FILE" ]; then
                printf "  %bNo distraction patterns defined yet.%b\n" "$LK_WHITE" "$LK_RESET"
            else
                cat -n "$LK_DISTRACT_FILE" | while read -r num line; do
                    printf "  %b[%s]%b %s\n" "$LK_MAGENTA" "$num" "$LK_RESET" "$line"
                done
            fi
            ;;
        rm|remove)
            if [ -z "$1" ]; then
                printf "%b[Error]%b Provide line number to remove.\n" "$LK_BRIGHT_RED" "$LK_RESET"
                return 1
            fi
            sed "${1}d" "$LK_DISTRACT_FILE" > "${LK_DISTRACT_FILE}.tmp" && mv "${LK_DISTRACT_FILE}.tmp" "$LK_DISTRACT_FILE"
            printf "%b[Removed]%b Pattern at line %s deleted.\n" "$LK_YELLOW" "$LK_RESET" "$1"
            ;;
        track)
            if [ ! -d "$LK_DIR" ]; then
                printf "%b[Error]%b LK Vault not found.\n" "$LK_BRIGHT_RED" "$LK_RESET"
                return 1
            fi

            if [ ! -s "$LK_DISTRACT_FILE" ]; then
                printf "%b[Error]%b Distraction list is empty. Add patterns using 'lkdistraction add'.\n" "$LK_BRIGHT_RED" "$LK_RESET"
                return 1
            fi

            printf "%b--- Initializing Neural Distraction Scan... ---%b\r" "$LK_CYAN" "$LK_RESET"

            # Parse scope (similar to lkstat)
            find_dir="$LK_DIR"
            lks_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
            if [ -n "$1" ]; then
                case "$1" in
                    [0-9][0-9][0-9][0-9]) find_dir="$LK_DIR/$1"; lks_pattern="$1-[0-9][0-9]-[0-9][0-9].md" ;;
                    [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
                        if [ "${#1}" -eq 6 ]; then y="${1%??}"; m="${1#????}"; else y="${1%-*}"; m="${1#*-}"; fi
                        find_dir="$LK_DIR/$y/$y-$m"; lks_pattern="$y-$m-[0-9][0-9].md"
                        ;;
                esac
            fi

            find "$find_dir" -type f -name "$lks_pattern" 2>/dev/null | sort | LC_ALL=C awk -v d_file="$LK_DISTRACT_FILE" '
            BEGIN {
                RESET   = "\033[0m"
                RED     = "\033[31m"
                GREEN   = "\033[32m"
                YELLOW  = "\033[33m"
                CYAN    = "\033[36m"
                MAGENTA = "\033[35m"
                WHITE   = "\033[37m"
                B_RED   = "\033[91m"
                
                # Load Distraction Patterns into Array
                p_count = 0
                while ((getline p < d_file) > 0) {
                    if (p != "") {
                        patterns[++p_count] = p
                    }
                }
                close(d_file)
            }
            {
                file = $0
                while ((getline line < file) > 0) {
                    # Extract timestamp hour
                    if (line ~ /^[ ]*- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - /) {
                        match(line, /[0-2][0-9]:[0-5][0-9]:[0-5][0-9]/)
                        ts = substr(line, RSTART, 8)
                        hr = substr(ts, 1, 2)
                        
                        total_logs++

                        # Check against all distraction patterns
                        distracted = 0
                        for (i=1; i<=p_count; i++) {
                            if (index(tolower(line), tolower(patterns[i])) != 0) {
                                hijack_counts[patterns[i]]++
                                vuln_hours[hr]++
                                distracted = 1
                                total_distractions++
                                break # Count only one distraction per log line
                            }
                        }
                        
                        if (distracted == 0) {
                            focus_logs++
                        }
                    }
                }
                close(file)
            }
            END {
                printf "\033[2K\r\n"
                print CYAN "| LK (LogKlerk) --- Neural Distraction Analytics ---" RESET
                
                if (total_logs == 0) {
                    print "  " RED "No logs found to analyze." RESET
                    exit
                }

                # 1. Macro Ratio
                distract_pct = int((total_distractions * 100) / total_logs)
                focus_pct = 100 - distract_pct
                
                print "  " MAGENTA "[ 1. The Dopamine Leak Ratio ]" RESET
                print "    Total Timestamps Scanned : " WHITE total_logs RESET " logs"
                print "    Focus / Productive State : " GREEN focus_logs RESET " logs (" GREEN focus_pct "%" RESET ")"
                print "    Cognitive Hijack State   : " B_RED total_distractions RESET " logs (" B_RED distract_pct "%" RESET ")\n"

                # 2. Vulnerability Window (Hour Analysis)
                print "  " MAGENTA "[ 2. Executive Function Vulnerability (By Hour) ]" RESET
                max_v_count = 0
                peak_v_hr = "N/A"
                for (h in vuln_hours) {
                    if (vuln_hours[h] > max_v_count) {
                        max_v_count = vuln_hours[h]; peak_v_hr = h
                    }
                }
                
                if (peak_v_hr != "N/A") {
                    print "    Peak Distraction Hour : " B_RED peak_v_hr ":00" RESET " (" YELLOW max_v_count " incidents" RESET ")"
                    print "    Timeframe Persona     : " WHITE "This is when your willpower battery is depleted." RESET
                } else {
                    print "    " GREEN "No vulnerability pattern detected." RESET
                }
                print ""

                # 3. Dominant Hijackers
                print "  " MAGENTA "[ 3. Dominant Hijackers (Top 5 Distractions) ]" RESET
                for (k=1; k<=5; k++) {
                    max_c = 0; max_p = ""
                    for (p in hijack_counts) {
                        if (hijack_counts[p] > max_c) {
                            max_c = hijack_counts[p]; max_p = p
                        }
                    }
                    if (max_p != "") {
                        printf "    ├── %s%s%s : %s%d%s occurrences\n", RED, max_p, RESET, YELLOW, max_c, RESET
                        delete hijack_counts[max_p]
                    }
                }
                print "\n" CYAN "------------------------------------------------------------" RESET
            }'
            ;;
        *)
            printf "%bUsage:%b lkdistraction {add|list|rm|track} [args]\n" "$LK_YELLOW" "$LK_RESET"
            ;;
    esac
}
