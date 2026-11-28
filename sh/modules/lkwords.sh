#!/bin/sh
# Module: lkwords (Lexical Corpus Analyzer & Semantic Dashboard)
# Version: v0.0.5 (Bulk Category Assignment & Multi-Ignore Parsing)
# POSIX Strict Version (Dash & TTY 16-Color Compatible)

lkwords() {
    # --- 1. Environment & Configuration ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}/lkwords"
    
    LK_IGNORE_FILE="${LK_CONFIG_DIR}/ignore.list"
    LK_CATEGORY_FILE="${LK_CONFIG_DIR}/categories.list"
    LK_MAPPING_FILE="${LK_CONFIG_DIR}/mappings.list"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}/lk.conf" ] && . "${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}/lk.conf"
    LK_DIR="${LK_DIR%/}"

    mkdir -p "$LK_CONFIG_DIR" 2>/dev/null
    touch "$LK_IGNORE_FILE" 2>/dev/null
    touch "$LK_CATEGORY_FILE" 2>/dev/null
    touch "$LK_MAPPING_FILE" 2>/dev/null

    # =========================================================================
    LK_RESET='\033[0m'
    LK_RED='\033[31m'
    LK_GREEN='\033[32m'
    LK_YELLOW='\033[33m'
    LK_CYAN='\033[36m'
    LK_MAGENTA='\033[35m'
    LK_WHITE='\033[37m'
    LK_B_RED='\033[91m'
    LK_GREY='\033[38;5;245m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_DIM='\033[2m'
    # =========================================================================

    SYS_STOP="lkdistraction lksort lkweight lkwords logklerk lki lkc lkv lkrank"

    cmd="$1"
    shift

    case "$cmd" in
        add)
            if [ "$1" = "category" ]; then
                cat_name="$2"
                if [ -z "$cat_name" ]; then
                    printf "%b[Error]%b Provide a category name (e.g., 'lkwords add category verbs').\n" "$LK_B_RED" "$LK_RESET"
                    return 1
                fi
                if grep -qx "$cat_name" "$LK_CATEGORY_FILE"; then
                    printf "%b[Notice]%b Category '%s' already exists.\n" "$LK_YELLOW" "$LK_RESET" "$cat_name"
                else
                    echo "$cat_name" >> "$LK_CATEGORY_FILE"
                    printf "%b[Added]%b Semantic Category %b[%s]%b registered.\n" "$LK_CYAN" "$LK_RESET" "$LK_MAGENTA" "$cat_name" "$LK_RESET"
                fi
            else
                printf "%b[Error]%b Usage: lkwords add category <name>\n" "$LK_B_RED" "$LK_RESET"
            fi
            ;;

        set)
            # Validasi minimal butuh 2 argumen: [kata] dan [kategori]
            if [ $# -lt 2 ]; then
                printf "%b[Error]%b Usage: lkwords set <word1> [word2...] <category>\n" "$LK_B_RED" "$LK_RESET"
                return 1
            fi
            
            # --- ARSITEKTUR BULK PARSING ---
            # Cari argumen yang paling terakhir sebagai 'cat_name'
            for arg in "$@"; do
                cat_name="$arg"
            done
            
            # Hitung batas iterasi (Total argumen dikurangi 1)
            count=$(($# - 1))
            i=0
            mapped_list=""
            
            # Loop melalui kata-kata, hentikan tepat sebelum argumen terakhir
            for word in "$@"; do
                if [ "$i" -eq "$count" ]; then
                    break
                fi
                
                w_low=$(echo "$word" | tr '[:upper:]' '[:lower:]')
                # Hapus pemetaan lama jika ada, lalu tulis pemetaan baru
                sed "/^${w_low}|/d" "$LK_MAPPING_FILE" > "${LK_MAPPING_FILE}.tmp" && mv "${LK_MAPPING_FILE}.tmp" "$LK_MAPPING_FILE"
                echo "${w_low}|${cat_name}" >> "$LK_MAPPING_FILE"
                
                mapped_list="$mapped_list $w_low"
                i=$((i + 1))
            done
            
            printf "%b[Mapped]%b Words%b%s%b assigned to %b[%s]%b.\n" "$LK_GREEN" "$LK_RESET" "$LK_CYAN" "$mapped_list" "$LK_RESET" "$LK_MAGENTA" "$cat_name" "$LK_RESET"
            ;;

        ignore)
            if [ $# -lt 1 ]; then
                printf "%b[Error]%b Provide words to ignore (e.g., 'lkwords ignore dan yang di').\n" "$LK_B_RED" "$LK_RESET"
                return 1
            fi
            
            ignored_list=""
            for word in "$@"; do
                w_low=$(echo "$word" | tr '[:upper:]' '[:lower:]')
                if ! grep -qx "$w_low" "$LK_IGNORE_FILE"; then
                    echo "$w_low" >> "$LK_IGNORE_FILE"
                    ignored_list="$ignored_list $w_low"
                fi
            done
            
            if [ -n "$ignored_list" ]; then
                printf "%b[Ignored]%b Words%b%s%b added to Stopwords filter.\n" "$LK_CYAN" "$LK_RESET" "$LK_GREY" "$ignored_list" "$LK_RESET"
            else
                printf "%b[Notice]%b Words already ignored.\n" "$LK_YELLOW" "$LK_RESET"
            fi
            ;;

        analyze)
            limit="${1:-25}"

            printf "%b--- Extracting & Categorizing Biological Lexicon... ---%b\r" "$LK_CYAN" "$LK_RESET"

            # PIPELINE: 1. Parse Words -> 2. Count -> 3. Map to Category -> 4. Sort -> 5. Matrix Render
            raw_data=$(find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -exec cat {} + 2>/dev/null | \
            LC_ALL=C awk -v ign_file="$LK_IGNORE_FILE" -v map_file="$LK_MAPPING_FILE" -v sys_stop="$SYS_STOP" '
            BEGIN {
                while ((getline w < ign_file) > 0) { if (w != "") ignored[tolower(w)] = 1 }
                close(ign_file)
                while ((getline l < map_file) > 0) { 
                    if (l != "") { split(l, arr, "|"); mapping[arr[1]] = arr[2] } 
                }
                close(map_file)
                split(sys_stop, sys_arr, " ")
                for (i in sys_arr) ignored[sys_arr[i]] = 1
            }
            {
                if ($0 ~ /^[[:space:]]*- #[[:space:]]*\[\[/) next
                if ($0 ~ /^[[:space:]]*created:/) next
                if ($0 ~ /^[[:space:]]*- ##? [0-9]{2}:00/) next
                sub(/^[[:space:]]*- [0-9]{2}:[0-9]{2}:[0-9]{2} - (\[\[[^]]+\]\] >> |\[[^]]+\] >> )?/, "")

                gsub(/[^a-zA-Z0-9]+/, " ")
                $0 = tolower($0)

                for (i=1; i<=NF; i++) {
                    w = $i
                    if (length(w) > 1 && w !~ /^[0-9]+$/ && !(w in ignored)) {
                        freq[w]++
                    }
                }
            }
            END {
                for (w in freq) {
                    c = mapping[w]
                    if (c == "") c = "Unmapped"
                    print c "|" freq[w] "|" w
                }
            }')

            printf "\033[2K\r"
            printf "%b| LK (LogKlerk) --- Semantic Categorization Matrix (Top %s) ---%b\n" "$LK_MAGENTA" "$limit" "$LK_RESET"

            echo "$raw_data" | sort -t'|' -k1,1 -k2,2nr | \
            LC_ALL=C awk -F'|' -v cat_file="$LK_CATEGORY_FILE" -v lim="$limit" '
            BEGIN {
                RESET="\033[0m"; CYAN="\033[36m"; ORANGE="\033[38;2;225;102;0m"; GREY="\033[38;5;245m"; MAGENTA="\033[35m"
                
                num_cats = 0
                while ((getline c < cat_file) > 0) {
                    if (c != "") { cat_arr[++num_cats] = c; cat_known[c] = 1 }
                }
                close(cat_file)
                
                cat_arr[++num_cats] = "Unmapped"
                cat_known["Unmapped"] = 1
                
                col_width = 24
                max_row = 0
            }
            {
                cat = $1; freq = $2; word = $3
                if (cat in cat_known) {
                    count[cat]++
                    if (count[cat] <= lim) {
                        val_str = word " (" freq "x)"
                        pad_len = col_width - length(val_str)
                        if (pad_len < 0) pad_len = 0
                        pad = ""
                        for (s=1; s<=pad_len; s++) pad = pad " "
                        
                        matrix[cat, count[cat]] = CYAN word RESET " " ORANGE "(" freq "x)" RESET pad
                        if (count[cat] > max_row) max_row = count[cat]
                    }
                }
            }
            END {
                # --- PRINT HEADERS ---
                hdr = "  "
                sep = "  "
                for (i=1; i<=num_cats; i++) {
                    c = cat_arr[i]
                    pad_len = col_width - length(c)
                    if (pad_len < 0) pad_len = 0
                    pad = ""
                    for (s=1; s<=pad_len; s++) pad = pad " "
                    
                    hdr = hdr MAGENTA c RESET pad " │ "
                    
                    sep_chunk = ""
                    for (s=1; s<=col_width; s++) sep_chunk = sep_chunk "─"
                    sep = sep GREY sep_chunk "─┼─" RESET
                }
                print hdr
                print sep
                
                # --- PRINT ROWS ---
                for (r=1; r<=max_row; r++) {
                    row_str = "  "
                    for (i=1; i<=num_cats; i++) {
                        c = cat_arr[i]
                        val = matrix[c, r]
                        if (val == "") {
                            pad = ""
                            for (s=1; s<=col_width; s++) pad = pad " "
                            val = pad
                        }
                        row_str = row_str val " " GREY "│" RESET " "
                    }
                    print row_str
                }
                
                # Bottom border
                bot = "  "
                for (i=1; i<=num_cats; i++) {
                    sep_chunk = ""
                    for (s=1; s<=col_width; s++) sep_chunk = sep_chunk "─"
                    bot = bot GREY sep_chunk "─┴─" RESET
                }
                print bot
            }'
            ;;

        trend|vs|context)
            printf "%b[Notice]%b Semantic feature '%s' is temporarily delegated while Tabular Matrix is active.\n" "$LK_YELLOW" "$LK_RESET" "$cmd"
            ;;

        *)
            printf "%bUsage:%b lkwords {analyze|add category|set|ignore} [args]\n" "$LK_YELLOW" "$LK_RESET"
            printf "  lkwords add category verbs   %b(Creates a new column 'verbs' in the dashboard)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkwords set \"dan\" \"di\" verbs %b(Assigns 'dan' and 'di' to the 'verbs' column)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkwords ignore \"yang\" \"the\"  %b(Hides multiple words from calculations)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkwords analyze 30           %b(Renders the Semantic Matrix Dashboard)%b\n" "$LK_DIM" "$LK_RESET"
            ;;
    esac
}
