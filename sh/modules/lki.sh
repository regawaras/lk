#!/bin/sh
# Module: lki (Standalone Interactive with Dynamic Taxonomy Parser & Hybrid Shell Logging)

lki() {
    CATEGORY_STRING="$1"

    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    
    # Default Tail Variables
    LK_TAIL_LINES="10"
    LK_COMMAND_TAIL_LINES="1" # Tail minimal untuk command Linux

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    _lki_update_vars() {
        TODAY=$(date +%Y-%m-%d)
        YEAR=$(date +%Y)
        MONTH=$(date +%Y-%m)
        CURRENT_HOUR=$(date +%H:00)
        LK_TDIR="$LK_DIR/$YEAR/$MONTH"
        FILENAME="$LK_TDIR/$TODAY${LK_DEFAULT_FORMAT}"
    }

    # --- 2. TUI Header Generator ---
    _lki_draw_header() {
        TERM_LINES=$(tput lines 2>/dev/null || stty size 2>/dev/null | cut -d' ' -f1 || echo 24)
        printf "\033[2J\033[1;1H" 
        
        BANNER_LINES=0
        if [ -f "$LK_CONFIG_DIR/assets/banner.txt" ]; then
            printf "\033[38;5;202m"
            cat "$LK_CONFIG_DIR/assets/banner.txt"
            printf "\033[0m"
            
            while IFS= read -r _dummy || [ -n "$_dummy" ]; do
                BANNER_LINES=$((BANNER_LINES + 1))
            done < "$LK_CONFIG_DIR/assets/banner.txt"
        fi
        
        printf "\033[38;5;202m | LK Log Klerk %s %s | Github: https://github.com/regawaras/lk/\n" "$LK_STATUS" "$LK_VERSION"
        printf "\033[38;5;202m | ''Just Type Enter Brutal'' - Log Klerking Creator \n" 
        printf "\033[38;5;202m | -------------- LK Interactive Mode (Hybrid Shell & Taxonomy) --------------\033[0m\n"
        printf "\033[38;2;105;105;105m | Hour Block: \033[38;2;255;220;0m%s\033[38;2;105;105;105m | Source: %s\033[0m\n" "$CURRENT_HOUR" "$LK_CONFIG_DIR"
        
        TUI_START=$((BANNER_LINES + 6))
        
        printf "\033[%d;%dr" "$TUI_START" "$TERM_LINES"
        printf "\033[%d;1H" "$TUI_START"
    }

    _lki_update_vars
    _lki_draw_header

    # Deteksi shell yang sedang aktif
    executing_shell=$(ps -p $$ -o comm= 2>/dev/null || basename "$SHELL" 2>/dev/null || echo "sh")
    executing_shell=$(basename "$executing_shell" | sed 's/^-//')
    SHELL_TAG="[[$executing_shell]] >>"

    # --- 3. Main Interactive Loop ---
    while true; do
        _lki_update_vars
        
        # Reset current tail lines ke standar setiap kali loop berulang
        current_tail_lines="$LK_TAIL_LINES"
        
        disp_prompt=$(echo "$CATEGORY_STRING" | sed 's/ >>$//')
        disp_filename="${FILENAME#$HOME/}"
        [ "$disp_filename" != "$FILENAME" ] && disp_filename="~/$disp_filename"

        if [ -n "$disp_prompt" ]; then
            printf "\033[38;5;202mLog As %s to %s\033[0m\n>> " "$disp_prompt" "$disp_filename"
        else
            printf "\033[38;5;202mLog to %s\033[0m\n>> " "$disp_filename"
        fi

        if ! read -r line; then break; fi
        
        curr_ts=$(date +%H:%M:%S)
        
        printf "\033[F\033[K\033[F\033[K" 
        
        if [ -n "$line" ]; then
            # TUI HISTORY TRACE
            printf "\033[1;35m❯ %s\033[0m\n" "$line"

            cmd="${line%% *}"
            args="${line#* }"
            [ "$cmd" = "$args" ] && args=""

            if [ "$cmd" = "-exit" ] || [ "$cmd" = "-q" ] || [ "$cmd" = "exit" ] || [ "$cmd" = "quit" ]; then
                printf "\033[r"; clear; break
            fi
            
            if [ "$cmd" = "clear" ]; then
                _lki_draw_header
                continue
            fi

            # --- DYNAMIC TAXONOMY PARSER ---
            override_tag=""
            if [ -f "$LK_TAXONOMY_FILE" ] && [ -n "$cmd" ]; then
                override_tag=$(grep "^${cmd}[[:space:]]*()[[:space:]]*{" "$LK_TAXONOMY_FILE" 2>/dev/null | sed -n 's/.*lk_context "\(.*\)" "\$@".*/\1/p')
            fi

            # --- FULLSCREEN INTERCEPTOR ---
            is_fullscreen=0
            case "$cmd" in
                vim|vi|nano|htop|top|less|man|tmux|screen) is_fullscreen=1 ;;
            esac

            # --- HYBRID EVALUATION ENGINE & LOGGING ---
            if [ -n "$override_tag" ]; then
                if [ -z "$args" ]; then
                    CATEGORY_STRING="$override_tag"
                    continue 
                else
                    ACTIVE_TAG="$override_tag"
                    LOG_TEXT="$args"
                fi
            elif [ "$is_fullscreen" -eq 1 ]; then
                printf "\033[r" 
                eval "$line"
                _lki_draw_header 
                ACTIVE_TAG="$SHELL_TAG"
                LOG_TEXT="$line"
                current_tail_lines="$LK_COMMAND_TAIL_LINES" # Gunakan Tail Minimal
            elif command -v "$cmd" >/dev/null 2>&1; then
                eval "$line"
                ACTIVE_TAG="$SHELL_TAG"
                LOG_TEXT="$line"
                current_tail_lines="$LK_COMMAND_TAIL_LINES" # Gunakan Tail Minimal
            else
                # --- STANDARD LOGGING ---
                ACTIVE_TAG="$CATEGORY_STRING"
                LOG_TEXT="$line"
            fi

            # --- Log Writing Execution ---
            mkdir -p "$LK_TDIR"
            indent="    "

            if [ ! -f "$FILENAME" ]; then
                printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$FILENAME"
                printf "%screated: [[%s]] - %s\n" "$indent" "$TODAY" "$curr_ts" >> "$FILENAME"
            fi

            if ! grep -q "^${indent}- ${CURRENT_HOUR} -" "$FILENAME" 2>/dev/null; then
                printf "%s- %s - (Hourly Summary)\n" "$indent" "$CURRENT_HOUR" >> "$FILENAME"
            fi

            if [ -n "$ACTIVE_TAG" ]; then
                log_entry="${indent}${indent}- ${curr_ts} - ${ACTIVE_TAG} ${LOG_TEXT}"
            else
                log_entry="${indent}${indent}- ${curr_ts} - ${LOG_TEXT}"
            fi

            printf "%s\n" "$log_entry" >> "$FILENAME"
            
            # Print Tail Result menggunakan current_tail_lines dinamis
            printf "\033[2m--- Last %s Lines ---\033[0m\n" "$current_tail_lines"
            tail -n "$current_tail_lines" "$FILENAME"
            printf "\033[2m------------------------------------------------------------\033[0m\n"
        fi
    done
    printf "\033[r" 
}
