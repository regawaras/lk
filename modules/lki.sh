_lk_interactive_mode() {
    CATEGORY_STRING="$1"
    _lk_get_time
    FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
    
    TERM_LINES=$(tput lines 2>/dev/null || stty size 2>/dev/null | cut -d' ' -f1 || echo 24)
    
    printf "\033[2J\033[1;1H"
    
    LK_BANNER_FILE="$LK_CONFIG_DIR/banner.txt"
    if [ -f "$LK_BANNER_FILE" ]; then
        printf "\033[?7l"
        printf "\033[38;2;255;200;0m"
        cat "$LK_BANNER_FILE"
        printf "\033[0m\n"          
        printf "\033[?7h"
        BANNER_LINES=$(awk 'END{print NR}' "$LK_BANNER_FILE" 2>/dev/null || echo 0)
        TUI_OFFSET=$((BANNER_LINES + 1))
    else
        TUI_OFFSET=0
    fi
    # ---
	printf "\033[38;2;255;200;0m| >> ---------- LK (Log Klerking) Structured Mode: Chronological ---------- << |\033[0m\n"
	printf "\033[2;38;2;255;117;0m| Type -help for menu or simply lkh, or -exit to quit.\033[0m\n"
	printf "\033[2;38;2;255;117;0m| Current Log Directory: %s\033[0m\n" "$LK_DIR"
	printf "\033[2;38;2;255;117;0m| Notes entering hour block: \033[0;1;38;2;255;200;0m%s\033[0m\n\n" "$CURRENT_HOUR"
    
    TUI_START=$((TUI_OFFSET + 6))
    	printf "\033[%d;%dr" "$TUI_START" "$TERM_LINES"
    	printf "\033[%d;1H" "$TUI_START"

        # --- 1. RENDER DYNAMIC PROMPT ---
	disp_prompt=$(echo "$CATEGORY_STRING" | sed 's/ >>$//')
	while true; do
	disp_filename="${FILENAME#$HOME/}"
        [ "$disp_filename" != "$FILENAME" ] && disp_filename="~/$disp_filename"

	if [ -n "$disp_prompt" ]; then
            printf "\033[38;2;255;165;0m| Logging Mode as %s to %s\033[0m\n>> " "$disp_prompt" "$disp_filename"
        else
            printf "\033[38;2;255;165;0m| Log to %s\033[0m\n>> " "$disp_filename"
        fi

        if ! read -r line; then break; fi
	printf "\033[F\033[K\033[F\033[K"
        
        if [ -n "$line" ]; then
            printf "\033[F\033[K"
            cmd="${line%% *}"
            args="${line#* }"
            [ "$cmd" = "$args" ] && args=""

            case "$cmd" in
                -set)
                    subcmd="${args%% *}"
                    subargs="${args#* }"
                    [ "$subcmd" = "$subargs" ] && subargs=""
                    case "$subcmd" in
                        -today) today_d=$(date +%Y-%m-%d); _lk_set_daily_summary "$today_d" "$subargs" ;;
                        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) _lk_set_daily_summary "$subcmd" "$subargs" ;;
                        -dir)
                            if [ -z "$subargs" ]; then continue; fi
                            case "$subargs" in
                                -home) ndir="$HOME/LogKlerk" ;;
                                -default) ndir="${XDG_DATA_HOME:-$HOME/.local/share}/logklerk" ;;
                                *) ndir="$subargs" ;;
                            esac
                            mkdir -p "$LK_CONFIG_DIR" "$ndir"
                            echo "LK_DIR=\"$ndir\"" > "$LK_CONFIG_FILE"
                            LK_DIR="$ndir"
                            FILENAME="$LK_DIR/$YEAR/$MONTH/$TODAY.md"
                            ;;
                        *) _lk_set_summary "$args" ;;
                    esac
                    ;;
                -search|--search|-s|lks) lks "$args" ;;
                -help|--help|-h|lkh) lkh ;;
                -exit|-q|-quit|exit|quit) 
                    printf "\033[r" 
                    clear
                    break ;;
                lkc) lkc "$args" ;;
                lkcm) lkcm "$args" ;;
                lkcd) lkcd "$args" ;;
                lkch) lkch "$args" ;;
                lkv) lkv "$args"; printf "\033[38;2;255;117;0m--- Returned to Interactive Mode ---\033[0m\n" ;;
                *)
                    # --- 2. DYNAMIC TAXONOMY PARSER ---
                    override_tag=""
                    if [ -f "$LK_TAXONOMY_FILE" ] && [ -n "$cmd" ]; then
                        # Cek apakah kata pertama (cmd) ada di dalam file taxonomy.sh
                        override_tag=$(grep "^${cmd}() {" "$LK_TAXONOMY_FILE" 2>/dev/null | sed -n 's/.*_lk_parser "\(.*\)" "\$@".*/\1/p')
                    fi

                    if [ -n "$override_tag" ]; then
                        if [ -z "$args" ]; then
                            # FITUR SWITCHER: Jika pengguna HANYA mengetik alias taksonomi, ubah prompt-nya!
                            CATEGORY_STRING="$override_tag"
                            disp_prompt=$(echo "$CATEGORY_STRING" | sed 's/ >>$//')
                            continue
                        else
                            # OVERRIDE SEKALI JALAN: Jika ada teksnya, tulis log dengan taksonomi sisipan ini
                            LAST_RAW=$(_lk_write_logic "$override_tag" "$args")
                        fi
                    else
                        # Tulis log secara normal menggunakan taksonomi mode saat ini
                        LAST_RAW=$(_lk_write_logic "$CATEGORY_STRING" "$line")
                    fi

                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    tail -n 35 "$FILENAME" | while IFS= read -r l; do
                        if [ "$l" = "$LAST_RAW" ]; then printf "\033[38;5;123m%s [NEW]\033[0m\n" "$l"; else printf "%s\n" "$l"; fi
                    done
                    printf "\033[2m------------------------------------------------------------\033[0m\n"
                    ;;
            esac
        fi
    done
    printf "\033[r"
}
