#!/bin/sh
# Module: lkrank (LogKlerk Frequency Ranker)
# Updated to v0.0.5 (Hotfix): Length-Topology Limiters, Unlimited Scope & NLP.

lkrank() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk" # Default fallback
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"
    
    # =========================================================================
    # GLOBAL SHELL COLOR
    # =========================================================================
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_ORANGE='\033[38;2;255;102;0m'
    LK_PURPLE='\033[38;2;170;100;255m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_HEADER_ORG='\033[38;2;255;117;0m'
    LK_RED='\033[31m'
    # =========================================================================

    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Error]%b LK Vault (%s) not found.\n" "$LK_RED" "$LK_RESET" "$LK_DIR"
        return 1
    fi
    
    # --- 2. Arguments & Time Scope Parser ---
    target_mode="all"
    top_n=10
    explicit_top=0
    find_dir="$LK_DIR"
    lks_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
    lks_scope="Global Lifetime"
    lks_range_start=""
    lks_range_end=""
    
    curr_y=$(date +%Y)
    curr_m=$(date +%Y-%m)
    
    while [ $# -gt 0 ]; do
        case "$1" in
            # Explicit Flag
            -n) top_n="$2"; explicit_top=1; shift 2; continue ;;
            
            # Natural Word Modes
            -x|tax|taxonomy*)  target_mode="tax"; shift; continue ;;
            -t|ctx|context*)   target_mode="ctx"; shift; continue ;;
            -l|lnk|hyperlink*) target_mode="lnk"; shift; continue ;;
            -h|hsh|hashtag*)   target_mode="hsh"; shift; continue ;;
            -a|all)            target_mode="all"; shift; continue ;;
            
            # Unlimited/Max Keyword Trigger
            max|full|unlimited) top_n=999999; explicit_top=1; shift; continue ;;

            # Dashed Time Scopes
            m|month|-m|--month)
                find_dir="$LK_DIR/$curr_y/$curr_m"
                lks_pattern="${curr_m}-[0-9][0-9].md"
                lks_scope="Monthly Scope ($curr_m)"
                shift; continue ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9])
                lks_range_start="${1%-*}"
                lks_range_end="${1#*-}"
                lks_scope="Yearly Range ($lks_range_start to $lks_range_end)"
                find_dir="$LK_DIR"
                shift; continue ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                y=$(echo "$1" | cut -d'-' -f1); m=$(echo "$1" | cut -d'-' -f2); d=$(echo "$1" | cut -d'-' -f3)
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="$y-$m-$d.md"
                lks_scope="Daily Scope ($y-$m-$d)"
                shift; continue ;;
            [0-9][0-9][0-9][0-9]-[0-9][0-9])
                y="${1%-*}"; m="${1#*-}"
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="$y-$m-[0-9][0-9].md"
                lks_scope="Monthly Scope ($y-$m)"
                shift; continue ;;

            # Pure Numeric Length-Topology Parser (Time vs Arbitrary Limit)
            [0-9]*)
                if echo "$1" | grep -qE "^[0-9]+$"; then
                    len="${#1}"
                    if [ "$len" -eq 8 ]; then
                        y=$(echo "$1" | cut -c1-4); m=$(echo "$1" | cut -c5-6); d=$(echo "$1" | cut -c7-8)
                        find_dir="$LK_DIR/$y/$y-$m"
                        lks_pattern="$y-$m-$d.md"
                        lks_scope="Daily Scope ($y-$m-$d)"
                    elif [ "$len" -eq 6 ]; then
                        y=$(echo "$1" | cut -c1-4); m=$(echo "$1" | cut -c5-6)
                        find_dir="$LK_DIR/$y/$y-$m"
                        lks_pattern="$y-$m-[0-9][0-9].md"
                        lks_scope="Monthly Scope ($y-$m)"
                    elif [ "$len" -eq 4 ] && [ "$1" -ge 1900 ] 2>/dev/null && [ "$1" -le 2100 ] 2>/dev/null; then
                        find_dir="$LK_DIR/$1"
                        lks_pattern="$1-[0-9][0-9]-[0-9][0-9].md"
                        lks_scope="Yearly Scope ($1)"
                    else
                        # Arbitrary Limit Number Constraint (e.g., 8, 11, 100, 10000)
                        top_n="$1"
                        explicit_top=1
                    fi
                fi
                shift; continue ;;
            *) 
                shift; continue ;;
        esac
    done

    # Dynamic Limit Auto-Scaling
    if [ "$explicit_top" -eq 0 ] && [ "$target_mode" != "all" ]; then
        top_n=50
    fi

    printf "%b--- Crunching Frequencies for %s... ---%b\r" "$LK_CYAN" "$lks_scope" "$LK_RESET"

    # --- 3. The Extraction & Ranking Pipeline ---
    if [ -n "$lks_range_start" ]; then
        cmd="for y in \$(seq $lks_range_start $lks_range_end 2>/dev/null || awk 'BEGIN{for(i=$lks_range_start;i<=$lks_range_end;i++) print i}'); do find \"$LK_DIR/\$y\" -type f -name \"\${y}-[0-9][0-9]-[0-9][0-9].md\" 2>/dev/null; done"
    else
        cmd="find \"$find_dir\" -type f -name \"$lks_pattern\" 2>/dev/null"
    fi

    eval "$cmd" | xargs cat 2>/dev/null | LC_ALL=C awk -v mode="$target_mode" -v top="$top_n" '
    BEGIN {
        # Silent extraction
    }
    {
        line = $0
        
        if (mode == "all" || mode == "ctx") {
            t_line = line
            while (match(t_line, /!\[[^\]]+\]!/)) {
                tag = substr(t_line, RSTART+2, RLENGTH-4)
                if (tag != "PLAN") ctx_arr[tag]++ 
                t_line = substr(t_line, RSTART+RLENGTH)
            }
        }
        
        if (mode == "all" || mode == "tax") {
            t_line = line
            while (match(t_line, /\[\[[^\]]+\]\] >>/)) {
                tax = substr(t_line, RSTART+2, RLENGTH-7)
                if (tax !~ /^[0-9]{4}-[0-9]{2}/) tax_arr[tax]++
                t_line = substr(t_line, RSTART+RLENGTH)
            }
        }
        
        if (mode == "all" || mode == "lnk") {
            t_line = line
            while (match(t_line, /\[\[[^\]]+\]\]/)) {
                lnk = substr(t_line, RSTART+2, RLENGTH-4)
                remainder = substr(t_line, RSTART+RLENGTH)
                
                if (remainder !~ /^ >>/ && lnk !~ /^[0-9]{4}-[0-9]{2}/) {
                    lnk_arr[lnk]++
                }
                t_line = remainder
            }
        }
        
        if (mode == "all" || mode == "hsh") {
            t_line = line
            while (match(t_line, /(^|[[:space:]])#[a-zA-Z0-9_-]+/)) {
                hsh = substr(t_line, RSTART, RLENGTH)
                sub(/^[[:space:]]+/, "", hsh)
                hsh_arr[hsh]++
                t_line = substr(t_line, RSTART+RLENGTH)
            }
        }
    }
    END {
        if (mode == "all" || mode == "ctx") { for (i in ctx_arr) print ctx_arr[i] "~CTX~" i }
        if (mode == "all" || mode == "tax") { for (i in tax_arr) print tax_arr[i] "~TAX~" i }
        if (mode == "all" || mode == "lnk") { for (i in lnk_arr) print lnk_arr[i] "~LNK~" i }
        if (mode == "all" || mode == "hsh") { for (i in hsh_arr) print hsh_arr[i] "~HSH~" i }
    }' | sort -nr | LC_ALL=C awk -v top="$top_n" -v scope="$lks_scope" '
    BEGIN {
        RESET  = "\033[0m"
        ORANGE = "\033[38;2;255;102;0m"
        MAGENTA= "\033[38;2;255;100;255m"
        CYAN   = "\033[38;2;0;255;255m"
        LIME   = "\033[38;2;100;255;0m"
        GREY   = "\033[38;2;150;150;150m"
        HEADER = "\033[38;2;255;117;0m"
        
        ctx_c=0; tax_c=0; lnk_c=0; hsh_c=0
    }
    {
        split($0, arr, "~")
        count = arr[1]; type = arr[2]; name = arr[3]
        
        if (type == "CTX" && ctx_c < top) { ctx_str = ctx_str "    " MAGENTA name RESET " (" GREY count "x" RESET ")\n"; ctx_c++ }
        if (type == "TAX" && tax_c < top) { tax_str = tax_str "    " ORANGE name RESET " (" GREY count "x" RESET ")\n"; tax_c++ }
        if (type == "LNK" && lnk_c < top) { lnk_str = lnk_str "    " CYAN name RESET " (" GREY count "x" RESET ")\n"; lnk_c++ }
        if (type == "HSH" && hsh_c < top) { hsh_str = hsh_str "    " LIME name RESET " (" GREY count "x" RESET ")\n"; hsh_c++ }
    }
    END {
        printf "\033[2K\r"
        if (top == 999999) { rank_label = "Full/Max Scope" } else { rank_label = "Top " top }
        print HEADER "| LK (LogKlerk) --- Frequency Ranker [" rank_label "] ---" RESET
        print "  " GREY "Scope: " scope RESET "\n"
        
        if (ctx_c > 0) { print "  \033[38;2;170;100;255m[ Context Tags (![x]!) ]\033[0m\n" ctx_str }
        if (tax_c > 0) { print "  \033[38;2;170;100;255m[ Taxonomies ([[x]] >>) ]\033[0m\n" tax_str }
        if (lnk_c > 0) { print "  \033[38;2;170;100;255m[ Hyperlinks ([[x]]) ]\033[0m\n" lnk_str }
        if (hsh_c > 0) { print "  \033[38;2;170;100;255m[ Hashtags (#x) ]\033[0m\n" hsh_str }
        
        if (ctx_c == 0 && tax_c == 0 && lnk_c == 0 && hsh_c == 0) {
            print "  " GREY "No data matched the query." RESET "\n"
        }
        print HEADER "-------------------------------------------------------" RESET
    }'
}
