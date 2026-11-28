# LK Core Writer Module (lkw)
_lk_write_logic() {
    CATEGORY="$1"
    TEXT="$2"
    _lk_get_time
    
    TARGET_DIR="$LK_DIR/$YEAR/$MONTH"
    FILENAME="$TARGET_DIR/$TODAY.md"
    LOCKFILE="$LK_CONFIG_DIR/.lk_write.lock"
    INDENT_4="    "
    INDENT_8="        "
    
    mkdir -p "$TARGET_DIR"

(
        flock -x 9
        if [ ! -f "$FILENAME" ]; then
            printf -- "- [[%s]] - (Daily Summary)\n" "$TODAY" >> "$FILENAME"
            printf "%screated: [[%s]] - %s\n" "$INDENT_4" "$TODAY" "$FULL_TIMESTAMP" >> "$FILENAME"
        fi
        if ! grep -q "^${INDENT_4}- $CURRENT_HOUR" "$FILENAME"; then
            printf "%s- %s - (Hourly Summary)\n" "$INDENT_4" "$CURRENT_HOUR" >> "$FILENAME"
        fi

        NEW_ENTRY="${INDENT_8}- $FULL_TIMESTAMP - $CATEGORY $TEXT"
        printf "%s\n" "$NEW_ENTRY" >> "$FILENAME"
        
        printf "%s\n" "$NEW_ENTRY"
    ) 9> "$LOCKFILE"
}
