# Modul: Visual Editor (lkv)
lkv() { 
    case "$1" in
        # --- System & Config Editor Flags ---
        -taxonomy|-tax|-t)
            ${EDITOR:-vim} "$LK_TAXONOMY_FILE"
            # Hot-reload taxonomy setelah diedit
            . "$LK_TAXONOMY_FILE"
            return 0 ;;
        -config|-dir)
            ${EDITOR:-vim} "$LK_CONFIG_FILE"
            return 0 ;;
        -alias|-aliases) # Mendukung pengetikan singular (-alias) maupun plural (-aliases)
            ${EDITOR:-vim} "$LK_MODULES_DIR/aliases.sh"
            return 0 ;;
        -lkc)
            ${EDITOR:-vim} "$LK_MODULES_DIR/lkc.sh"
            return 0 ;;
        -lkh)
            ${EDITOR:-vim} "$LK_MODULES_DIR/lkh.sh"
            return 0 ;;
        -lks)
            ${EDITOR:-vim} "$LK_MODULES_DIR/lks.sh"
            return 0 ;;
        -lki)
            ${EDITOR:-vim} "$LK_MODULES_DIR/lki.sh"
            return 0 ;;
        -banner)
            ${EDITOR:-vim} "$LK_CONFIG_DIR/banner.txt"
            return 0 ;;
        -lkv|-vlk) # Mendukung nama lama sebagai fallback memori otot
            ${EDITOR:-vim} "$LK_MODULES_DIR/lkv.sh"
            return 0 ;;
        -lk)
            ${EDITOR:-vim} "$LK_CONFIG_DIR/lk.sh"
            return 0 ;;
            
        # --- Data Log Editor Flags ---
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            lkv_date="$1"
            lkv_year="${lkv_date%%-*}"
            lkv_month="${lkv_date%-*}"
            lkv_dir="$LK_DIR/$lkv_year/$lkv_month"
            mkdir -p "$lkv_dir"
            ${EDITOR:-vim} "$lkv_dir/$lkv_date.md"
            return 0
            ;;
        "") 
            # Kosong = lanjut ke bawah (edit log hari ini)
            ;;
        *)
            printf "\033[31mInvalid flag or date format.\033[0m\n"
            printf "Usage: lkv [YYYY-MM-DD] | -lk | -taxonomy | -config | -alias | -lkc | -lkh | -lks | -lkv\n"
            return 1
            ;;
    esac

    # Edit log hari ini (Default fallback)
    _lk_get_time
    lkv_dir="$LK_DIR/$YEAR/$MONTH"
    mkdir -p "$lkv_dir"
    ${EDITOR:-vim} "$lkv_dir/$TODAY.md"
}
