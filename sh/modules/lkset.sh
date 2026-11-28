#!/bin/sh
# Modul: lkset (LogKlerk Taxonomy Generator - Standalone & Safe I/O)

lkset() {
    # --- 1. Resolusi Konfigurasi & Path ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.2}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # --- 2. Validasi Input ---
    if [ -z "$1" ] || [ "${1#*=}" = "$1" ]; then
        printf "\033[31mError: Gunakan format alias=\"[[Tag]]\"\033[0m\n"
        printf "Contoh: lkset wbl=\"[[Website Links]]\"\n"
        return 1
    fi

    # --- 3. Manajemen Direktori & I/O Protection ---
    lks_dir="${LK_TAXONOMY_FILE%/*}"
    mkdir -p "$lks_dir" 2>/dev/null
    [ ! -f "$LK_TAXONOMY_FILE" ] && touch "$LK_TAXONOMY_FILE" 2>/dev/null

    if [ ! -w "$LK_TAXONOMY_FILE" ]; then
        printf "\033[31mError: Permission denied pada file context.sh.\033[0m\n"
        printf "Jalankan di luar LKI: \033[38;2;255;255;0msudo chown \$USER:\$USER %s\033[0m\n" "$LK_TAXONOMY_FILE"
        return 1
    fi

    # --- 4. Parsing Alias & Tag ---
    lks_alias="${1%%=*}"
    lks_tag_raw="${1#*=}"
    
    # Menghapus tanda kutip (single/double)
    lks_tag=$(echo "$lks_tag_raw" | sed "s/^['\"]//; s/['\"]$//")

    # --- 5. Proteksi Duplikasi ---
    if grep -q "^${lks_alias}[[:space:]]*()[[:space:]]*{" "$LK_TAXONOMY_FILE" 2>/dev/null; then
        printf "\033[33mWarning: Alias '%s' sudah terdaftar di context.sh. Batalkan.\033[0m\n" "$lks_alias"
        return 0
    fi

    # --- 6. Penulisan Atomik ke context.sh (Added ' >>' separator) ---
    lks_new_func="${lks_alias}() { lk_context \"${lks_tag} >>\" \"\$@\"; }"
    
    printf "%s\n" "$lks_new_func" >> "$LK_TAXONOMY_FILE"

    # --- 7. Feedback Visual ---
    printf "\033[32m[Konteks Berhasil Ditambahkan]\033[0m\n"
    printf "Alias : \033[38;2;255;255;0m%s\033[0m\n" "$lks_alias"
    printf "Tag   : \033[38;2;0;255;255m%s >>\033[0m\n" "$lks_tag"
    printf "\033[2mLokasi: %s\033[0m\n" "$LK_TAXONOMY_FILE"
}
