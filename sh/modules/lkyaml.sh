#!/bin/sh
# Module: lkyaml (LogKlerk YAML Telemetry Analyzer)
# Function: Frontmatter Metadata Extraction & Chronological Ranging
# Update: Zero-Redundancy Timeline Range Grouping

lkyaml() {
    # --- 1. Environment & Configuration ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    # Global Colors
    LK_RESET='\033[0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_ORANGE='\033[38;2;255;102;0m'
    LK_HEADER_ORG='\033[38;2;255;117;0m'
    LK_RED='\033[31m'

    if [ ! -d "$LK_DIR" ]; then
        printf "%b[Error]%b LK Vault (%s) not found.\n" "$LK_RED" "$LK_RESET" "$LK_DIR"
        return 1
    fi

    # --- 2. Arguments & Time Scope Parser ---
    target_action="help"
    target_key=""
    find_dir="$LK_DIR"
    lks_pattern="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md"
    lks_scope="Global Lifetime"
    curr_y=$(date +%Y)
    curr_m=$(date +%Y-%m)

    while [ $# -gt 0 ]; do
        case "$1" in
            # Actions
            keys|k)          target_action="keys"; shift; continue ;;
            values|v|val)    target_action="values"; target_key="$2"; shift 2; continue ;;
            timeline|t|time) target_action="timeline"; target_key="$2"; shift 2; continue ;;
            dump|d)          target_action="dump"; shift; continue ;;
            
            # Time Scopes
            m|month|-m|--month)
                find_dir="$LK_DIR/$curr_y/$curr_m"
                lks_pattern="${curr_m}-[0-9][0-9].md"
                lks_scope="Monthly Scope ($curr_m)"
                shift; continue ;;
            [0-9][0-9][0-9][0-9])
                find_dir="$LK_DIR/$1"
                lks_pattern="$1-[0-9][0-9]-[0-9][0-9].md"
                lks_scope="Yearly Scope ($1)"
                shift; continue ;;
            [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
                if [ "${#1}" -eq 6 ]; then y="${1%??}"; m="${1#????}"; else y="${1%-*}"; m="${1#*-}"; fi
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="$y-$m-[0-9][0-9].md"
                lks_scope="Monthly Scope ($y-$m)"
                shift; continue ;;
            [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                if [ "${#1}" -eq 8 ]; then 
                    y=$(echo "$1" | cut -c1-4); m=$(echo "$1" | cut -c5-6); d=$(echo "$1" | cut -c7-8)
                else 
                    y=$(echo "$1" | cut -d'-' -f1); m=$(echo "$1" | cut -d'-' -f2); d=$(echo "$1" | cut -d'-' -f3)
                fi
                find_dir="$LK_DIR/$y/$y-$m"
                lks_pattern="$y-$m-$d.md"
                lks_scope="Daily Scope ($y-$m-$d)"
                shift; continue ;;
            *)
                shift; continue ;;
        esac
    done

    if [ "$target_action" = "help" ]; then
        printf "%b| LK (LogKlerk) --- YAML Telemetry Analyzer ---%b\n" "$LK_HEADER_ORG" "$LK_RESET"
        printf " Usage: lkyaml [TIME] [ACTION] [ARGS]\n\n"
        printf " Actions:\n"
        printf "   %bkeys%b             : Rank all unique YAML keys.\n" "$LK_LIME" "$LK_RESET"
        printf "   %bvalues [Key]%b     : Rank all unique values for a specific Key.\n" "$LK_CYAN" "$LK_RESET"
        printf "   %btimeline [Key]%b   : Show chronological state transitions for a Key.\n" "$LK_ORANGE" "$LK_RESET"
        printf "   %bdump%b             : Raw extraction of all YAML blocks.\n\n" "$LK_CYAN" "$LK_RESET"
        return 0
    fi

    printf "%b--- Analyzing YAML Telemetry for %s... ---%b\r" "$LK_CYAN" "$lks_scope" "$LK_RESET"

    # --- 3. Direct Streaming AWK Engine (With Contiguous Ranging) ---
    find "$find_dir" -type f -name "$lks_pattern" 2>/dev/null | sort | \
    LC_ALL=C awk -v act="$target_action" -v t_key="$target_key" -v scope="$lks_scope" '
    BEGIN {
        printf "\033[2K\r"
        RESET   = "\033[0m"
        CYAN    = "\033[38;2;0;255;255m"
        GREY    = "\033[38;2;150;150;150m"
        ORANGE  = "\033[38;2;255;102;0m"
        AMBER   = "\033[38;2;255;204;0m"
        HEADER  = "\033[38;2;255;117;0m"
        
        if (act == "keys") {
            print HEADER "| LK (LogKlerk) --- YAML Keys Frequency ---" RESET
            print "  " GREY "Scope: " scope RESET "\n"
        } else if (act == "values") {
            print HEADER "| LK (LogKlerk) --- YAML Values Analyzer ---" RESET
            print "  " GREY "Scope: " scope " | Key: [" t_key "]" RESET "\n"
        } else if (act == "timeline") {
            print HEADER "| LK (LogKlerk) --- YAML Chronological Timeline ---" RESET
            print "  " GREY "Scope: " scope " | Key: [" t_key "]" RESET "\n"
        }
        
        prev_val = ""
        start_dt = ""
        end_dt = ""
        display_key = t_key
    }
    
    function print_timeline_range() {
        if (prev_val != "") {
            # Jika rentang hari hanya 1 hari, cetak dengan padding ruang kosong agar sejajar
            if (start_dt == end_dt) {
                date_str = AMBER "[[" start_dt "]]" RESET "                  "
            } else {
                date_str = AMBER "[[" start_dt "]]" RESET GREY " -> " RESET AMBER "[[" end_dt "]]" RESET
            }
            printf "    %s | %s%s:%s %s\"%s\"%s\n", date_str, ORANGE, display_key, RESET, CYAN, prev_val, RESET
        }
    }

    {
        file = $0
        in_yaml = 0
        
        n = split(file, parts, "/")
        basename = parts[n]
        sub(/\.md$/, "", basename)
        dt = basename
        
        while ((getline line < file) > 0) {
            if (line ~ /^---[ \t]*$/) {
                if (!in_yaml) { in_yaml = 1; continue }
                else { in_yaml = 0; if(act=="dump") print "---"; break }
            }
            
            if (in_yaml && line ~ /^[^:]+:/) {
                if (act == "dump") { print CYAN line RESET; continue }
                
                match(line, /^[^:]+:[ \t]*/)
                k = substr(line, 1, RLENGTH)
                sub(/:[ \t]*$/, "", k)
                
                v = substr(line, RLENGTH + 1)
                sub(/^["'\'' \t]+/, "", v)
                sub(/["'\'' \t]+$/, "", v)
                
                if (act == "keys") { 
                    key_arr[k]++ 
                } 
                else if (act == "values" && tolower(k) == tolower(t_key)) { 
                    val_arr[v]++ 
                }
                else if (act == "timeline" && tolower(k) == tolower(t_key)) {
                    display_key = k
                    if (prev_val != "" && v != prev_val) {
                        # Tiba-tiba state berubah, cetak state sebelumnya dari rentang memori
                        print_timeline_range()
                        start_dt = dt
                    } else if (prev_val == "") {
                        # Tangkapan pertama kali
                        start_dt = dt
                    }
                    prev_val = v
                    end_dt = dt
                }
            }
        }
        close(file)
    }
    
    END {
        if (act == "keys") {
            for (i in key_arr) { print key_arr[i] "~" i | "sort -nr" }
            close("sort -nr")
        } 
        else if (act == "values") {
            count = 0
            for (i in val_arr) { count++; print val_arr[i] "~" i | "sort -nr" }
            close("sort -nr")
            if (count == 0) print "    " GREY "No values found for key: " t_key RESET
        }
        else if (act == "timeline" && prev_val != "") {
            # Cetak rentang terakhir yang belum dikeluarkan dari buffer
            print_timeline_range()
        }
        
        print HEADER "-------------------------------------------" RESET
    }' | LC_ALL=C awk -v act="$target_action" '
    BEGIN {
        RESET  = "\033[0m"
        LIME   = "\033[38;2;100;255;0m"
        GREY   = "\033[38;2;150;150;150m"
        CYAN   = "\033[38;2;0;255;255m"
    }
    {
        if ($0 ~ /~/) {
            split($0, arr, "~")
            count = arr[1]
            name = arr[2]
            
            if (act == "keys") {
                print "    " LIME name RESET " (" GREY count "x" RESET ")"
            } else if (act == "values") {
                print "    " CYAN name RESET " (" GREY count "x" RESET ")"
            }
        } else {
            print $0
        }
    }'
}
