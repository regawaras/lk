#!/bin/sh
# Module: lksort (LogKlerk Sorter - Universal Table Analytics)

lksort() {
    # --- 1. Environment Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;255;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[90m')
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_ORANGE=$(printf '\033[38;2;225;102;0m')
    # =========================================================================

    # --- 2. Help Menu ---
    if [ $# -eq 0 ]; then
        printf "%s| LK Analytics --- Universal Sorting Engine ---%s\n" "$LK_ORANGE" "$LK_RESET"
        printf "Usage: lksort [filter] [metric] [order]\n\n"
        printf "%s[filter]%s (Optional)\n" "$LK_CYAN" "$LK_RESET"
        printf "  YYYY       : Filter by year (e.g., 2026)\n"
        printf "  YYYYMM     : Filter by month (e.g., 202604)\n"
        printf "  YYYY-MM    : Filter by month (e.g., 2026-04)\n\n"
        printf "%s[metric]%s (Optional, Default: date)\n" "$LK_LIME" "$LK_RESET"
        printf "  date       : Sort by chronology\n"
        printf "  size       : Sort by file size\n"
        printf "  words      : Sort by word count\n"
        printf "  lines      : Sort by line count\n\n"
        printf "%s[order]%s  (Optional, Default: asc)\n" "$LK_AMBER" "$LK_RESET"
        printf "  asc        : Smallest/oldest to largest/newest (Highlights largest at the bottom)\n"
        printf "  desc       : Largest/newest to smallest/oldest\n\n"
        printf "%sExamples:\n" "$LK_GREY"
        printf "  lksort 202604           -> Chronological table for April 2026\n"
        printf "  lksort 2026 words desc  -> Files with the most words in 2026 (top to bottom)\n"
        printf "  lksort size             -> Smallest to largest files globally%s\n" "$LK_RESET"
        return 0
    fi

    # --- 3. Smart Argument Parsing (Time-Scope Filter) ---
    filter_dir="$LK_DIR"
    filter_label="All Notes"

    case "$1" in
        [0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9])
            if [ "${#1}" -eq 6 ]; then
                y="${1%??}"
                m="${1#????}"
            else
                y="${1%-*}"
                m="${1#*-}"
            fi
            filter_dir="$LK_DIR/$y/$y-$m"
            filter_label="$y-$m"
            shift 
            ;;
        [0-9][0-9][0-9][0-9])
            y="$1"
            filter_dir="$LK_DIR/$y"
            filter_label="$y"
            shift
            ;;
    esac

    if [ ! -d "$filter_dir" ]; then
        printf "\033[31m[Error]\033[0m Data or directory for '\033[38;2;255;255;0m%s\033[0m' not found.\n" "$filter_label"
        return 1
    fi

    # --- 4. Parameter Resolution (Metric & Order) ---
    if [ -z "$1" ]; then
        metric="date"
        order="asc"
    else
        metric="$1"
        if [ -n "$2" ]; then
            order="$2"
        else
            # Default to ascending for readability (largest values at the bottom of the terminal)
            order="asc"
        fi
    fi

    # --- 5. Determine Sorting Column Based on Metric ---
    # wc output: "   lines   words   bytes   path/file"
    case "$metric" in
        table|date)
            [ "$order" = "asc" ] && sort_flag="-k4,4" || sort_flag="-k4,4r"
            ;;
        lines)
            [ "$order" = "asc" ] && sort_flag="-n -k1,1" || sort_flag="-nr -k1,1"
            ;;
        words|wordcount)
            [ "$order" = "asc" ] && sort_flag="-n -k2,2" || sort_flag="-nr -k2,2"
            ;;
        size)
            [ "$order" = "asc" ] && sort_flag="-n -k3,3" || sort_flag="-nr -k3,3"
            ;;
        *)
            printf "\033[31m[Error]\033[0m Metric '%s' unknown. Type 'lksort' for help.\n" "$metric"
            return 1 ;;
    esac

    printf "%s| LK Analytics --- [%s] sorted by %s (%s) ---%s\n" "$LK_ORANGE" "$filter_label" "$metric" "$order" "$LK_RESET"

    # --- 6. Universal Analytics Engine ---
    find "$filter_dir" -type f -name "*.md" -exec wc {} + | grep -v " total$" | sort $sort_flag | \
    awk -v base="$LK_DIR/" -v reset="$LK_RESET" -v amber="$LK_AMBER" -v lime="$LK_LIME" -v cyan="$LK_CYAN" -v grey="$LK_GREY" '
    function human(x) {
        if (x>=1073741824) {return sprintf("%5.1f GiB", x/1073741824)}
        if (x>=1048576) {return sprintf("%5.1f MiB", x/1048576)}
        if (x>=1024) {return sprintf("%5.1f KiB", x/1024)}
        return sprintf("%5d B  ", x)
    }
    {
        lines = $1; words = $2; bytes = $3; path = $4
        n = split(path, a, "/"); filename = a[n]
        sub(/\.md$/, "", filename)
        sub(base, "", path)
        printf "%s[%-10s]%s ── %s%5d L%s │ %s%6d W%s │ %s%9s%s ── %s%s%s\n", amber, filename, reset, lime, lines, reset, cyan, words, reset, lime, human(bytes), reset, grey, path, reset
    }'
}
