#!/bin/sh
# Module: lkspace (LogKlerk Spatial Context Injector)
# Function: Chronotope Mapping (Time-Space Sacredity YAML Frontmatter)
# Update: Retroactive Backfilling (Auto-create missing files for Date/Ranges)

lkspace() {
    # --- 1. Environment & Config ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${LK_CONFIG_DIR:-${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}}"
    LK_SPACE_MAP="${LK_CONFIG_DIR}/modules/lkspace.map"
    LK_DIR="${LK_DIR:-${HOME}/.local/share/logklerk}"
    LK_DIR="${LK_DIR%/}"

    # Global Colors
    LK_RESET='\033[0m'
    LK_LIME='\033[38;2;100;255;0m'
    LK_CYAN='\033[38;2;0;255;255m'
    LK_PURPLE='\033[38;2;170;100;255m'
    LK_GREY='\033[38;2;150;150;150m'
    LK_RED='\033[31m'
    LK_AMBER='\033[38;2;255;204;0m'

    # Ensure mapping config exists
    mkdir -p "${LK_SPACE_MAP%/*}" 2>/dev/null
    [ ! -f "$LK_SPACE_MAP" ] && touch "$LK_SPACE_MAP"

    # --- 2. Subcommand: add (Mapping Custom Variables) ---
    if [ "$1" = "add" ]; then
        shift
        if [ -z "$1" ] || [ "${1#*=}" = "$1" ]; then
            printf "%b[Syntax Error]%b Format must be: lkspace add var=\"Long Name\"\n" "$LK_RED" "$LK_RESET"
            printf "Example: lkspace add os=\"Operating System\"\n"
            return 1
        fi
        
        var_key="${1%%=*}"
        var_val_raw="${1#*=}"
        var_val=$(echo "$var_val_raw" | sed "s/^['\"]//; s/['\"]$//")

        # Atomic update in map file
        sed -i "/^${var_key}=/d" "$LK_SPACE_MAP" 2>/dev/null
        printf "%s=\"%s\"\n" "$var_key" "$var_val" >> "$LK_SPACE_MAP"
        
        printf "%b✔%b Space Variable Mapped: %b%s%b -> %b%s%b\n" "$LK_LIME" "$LK_RESET" "$LK_PURPLE" "$var_key" "$LK_RESET" "$LK_CYAN" "$var_val" "$LK_RESET"
        return 0
    fi

    # --- 3. Input Validation & Mapping Resolution ---
    target_time="$1"
    target_var="$2"
    shift 2
    target_val="$*"

    if [ -z "$target_time" ] || [ -z "$target_var" ] || [ -z "$target_val" ]; then
        printf "%b[Syntax Error]%b Usage: lkspace [TIME] [VAR] [VALUE]\n" "$LK_RED" "$LK_RESET"
        printf "Examples:\n  lkspace 202510 os NixOS\n  lkspace 2024-03-19 os \"Ubuntu Linux\"\n"
        return 1
    fi

    # Clean quotes from value
    target_val=$(echo "$target_val" | sed "s/^['\"]//; s/['\"]$//")

    # Resolve from lkspace.map (or fallback to User Input if not mapped)
    mapped_var=$(grep "^${target_var}=" "$LK_SPACE_MAP" | cut -d'=' -f2- | sed "s/^['\"]//; s/['\"]$//")
    if [ -z "$mapped_var" ]; then
        mapped_var="$target_var"
        printf "%b[Warn]%b Variable '%s' is not mapped. Using raw name.\n" "$LK_AMBER" "$LK_RESET" "$target_var"
    fi

    # --- 4. Chronotope Parsing Engine (Time -> Files) ---
    file_list=$(mktemp)

    # 4a. Year Scope (YYYY) -> Berlaku hanya untuk file yang sudah ada
    if echo "$target_time" | grep -qE "^[0-9]{4}$"; then
        find "$LK_DIR/$target_time" -type f -name "*.md" 2>/dev/null > "$file_list"
        scope_name="Year $target_time"
        
    # 4b. Month Scope (YYYYMM or YYYY-MM) -> Berlaku hanya untuk file yang sudah ada
    elif echo "$target_time" | grep -qE "^[0-9]{6}$|^[0-9]{4}-[0-9]{2}$"; then
        if echo "$target_time" | grep -q "-"; then
            y=$(echo "$target_time" | cut -d'-' -f1)
            m=$(echo "$target_time" | cut -d'-' -f2)
        else
            y=$(echo "$target_time" | cut -c1-4)
            m=$(echo "$target_time" | cut -c5-6)
        fi
        find "$LK_DIR/$y/$y-$m" -type f -name "*.md" 2>/dev/null > "$file_list"
        scope_name="Month $y-$m"
        
    # 4c. Date Scope (YYYYMMDD or YYYY-MM-DD) -> FORCE CREATE jika tidak ada
    elif echo "$target_time" | grep -qE "^[0-9]{8}$|^[0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
        if echo "$target_time" | grep -q "-"; then
            y=$(echo "$target_time" | cut -d'-' -f1)
            m=$(echo "$target_time" | cut -d'-' -f2)
            d=$(echo "$target_time" | cut -d'-' -f3)
        else
            y=$(echo "$target_time" | cut -c1-4)
            m=$(echo "$target_time" | cut -c5-6)
            d=$(echo "$target_time" | cut -c7-8)
        fi
        f="$LK_DIR/$y/$y-$m/$y-$m-$d.md"
        mkdir -p "${f%/*}"
        [ ! -f "$f" ] && touch "$f"
        echo "$f" > "$file_list"
        scope_name="Date $y-$m-$d"
        
    # 4d. Range Scope (YYYYMMDD-YYYYMMDD) -> FORCE CREATE jika tidak ada
    elif echo "$target_time" | grep -qE "^[0-9]{8}-[0-9]{8}$"; then
        start_date="${target_time%-*}"
        end_date="${target_time#*-}"
        sy=$(echo "$start_date" | cut -c1-4); sm=$(echo "$start_date" | cut -c5-6); sd=$(echo "$start_date" | cut -c7-8)
        ey=$(echo "$end_date" | cut -c1-4); em=$(echo "$end_date" | cut -c5-6); ed=$(echo "$end_date" | cut -c7-8)

        curr="$sy-$sm-$sd"
        end="$ey-$em-$ed"
        scope_name="Range $curr to $end"

        # GNU Date Loop + Retroactive Creation
        while [ "$curr" != "$(date -I -d "$end + 1 day" 2>/dev/null)" ]; do
            cy=$(echo "$curr" | cut -d'-' -f1); cm=$(echo "$curr" | cut -d'-' -f2)
            f="$LK_DIR/$cy/$cy-$cm/$curr.md"
            mkdir -p "${f%/*}"
            [ ! -f "$f" ] && touch "$f"
            echo "$f" >> "$file_list"
            curr=$(date -I -d "$curr + 1 day" 2>/dev/null)
        done
    else
        printf "%b[Error]%b Invalid time target format.\n" "$LK_RED" "$LK_RESET"
        rm -f "$file_list"
        return 1
    fi

    file_count=$(wc -l < "$file_list")
    if [ "$file_count" -eq 0 ]; then
        printf "%b[Info]%b No files found for temporal target: %s\n" "$LK_CYAN" "$LK_RESET" "$scope_name"
        rm -f "$file_list"
        return 0
    fi

    printf "%b--- Injecting Chronotope Metadata ---%b\n" "$LK_CYAN" "$LK_RESET"
    printf " Scope : %b%s%b (%s files)\n" "$LK_PURPLE" "$scope_name" "$LK_RESET" "$file_count"
    printf " Key   : %b%s%b\n" "$LK_LIME" "$mapped_var" "$LK_RESET"
    printf " Value : %b\"%s\"%b\n" "$LK_CYAN" "$target_val" "$LK_RESET"

    # --- 5. Atomic YAML Prepend/Inject Engine ---
    while IFS= read -r file; do
        # Penanganan Khusus untuk File Historis yang baru saja diciptakan (0-byte)
        if [ ! -s "$file" ]; then
            printf -- "---\n%s: \"%s\"\n---\n\n" "$mapped_var" "$target_val" > "$file"
            continue
        fi

        tmp_file="${file}.tmp"
        awk -v key="$mapped_var" -v val="\"$target_val\"" '
        BEGIN { in_yaml=0; injected=0 }
        
        NR==1 && /^---[ \t]*$/ { in_yaml=1; print; next }
        
        in_yaml==1 && /^---[ \t]*$/ {
            if (!injected) { print key ": " val; injected=1 }
            in_yaml=0; print; next
        }
        
        in_yaml==1 {
            if ($0 ~ "^" key ":") { print key ": " val; injected=1 }
            else { print }
            next
        }
        
        NR==1 && !/^---[ \t]*$/ {
            print "---"
            print key ": " val
            print "---"
            print ""
            print
            injected=1
            next
        }
        { print }
        ' "$file" > "$tmp_file" && mv "$tmp_file" "$file"

    done < "$file_list"

    rm -f "$file_list"
    printf "%b✔%b Injection Complete.\n" "$LK_LIME" "$LK_RESET"
}
