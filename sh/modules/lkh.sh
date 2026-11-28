#!/bin/sh
# Modul: lkh (LogKlerk Help Manual - v0.0.3 Experimental)

_lk_show_help() {
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

    printf "\n%s========================================================================%s\n" "$LK_ORANGE" "$LK_RESET"
    printf "%s                 LogKlerk (LK) v0.0.3 Experimental Manual               %s\n" "$LK_ORANGE" "$LK_RESET"
    printf "%s========================================================================%s\n\n" "$LK_ORANGE" "$LK_RESET"
    
    # 1. CORE LOGGING
    printf "%s[1. Core Logging & TUI]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lk [text]" "$LK_RESET" "$LK_GREY" "Catat log standar ke waktu saat ini secara instan." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lki" "$LK_RESET" "$LK_GREY" "Buka Interactive Mode (Hybrid Shell + TUI)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lk -v \"[teks]\"" "$LK_RESET" "$LK_GREY" "Catat log dengan tag versi LogKlerk otomatis." "$LK_RESET"
    printf "\n"

    # 2. TAXONOMY & CONTEXT
    printf "%s[2. Context & Taxonomy Engine]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkset <alias>=\"[[Tag]]\"" "$LK_RESET" "$LK_GREY" "Buat alias tag dinamis (Contoh: lkset wbl=\"[[Web]]\")." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkfiles <alias>=\"[[Folder]]\"" "$LK_RESET" "$LK_GREY" "Buat alias ke direktori file eksklusif (Standalone)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias> [text]" "$LK_RESET" "$LK_GREY" "Gunakan alias yang sudah dibuat untuk mencatat." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias>" "$LK_RESET" "$LK_GREY" "Ketik alias saja lalu Enter untuk masuk ke mode LKI tag." "$LK_RESET"
    printf "\n"

    # 3. SUMMARIZER
    printf "%s[3. Smart Summarizer (lksum)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 2026 \"Teks\"" "$LK_RESET" "$LK_GREY" "Perbarui Ringkasan Tahunan (Yearly Summary)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 202604 \"Teks\"" "$LK_RESET" "$LK_GREY" "Perbarui Ringkasan Bulanan (Monthly Summary)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 20260422 \"Teks\"" "$LK_RESET" "$LK_GREY" "Perbarui Ringkasan Harian (Daily Summary)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 14 \"Teks\"" "$LK_RESET" "$LK_GREY" "Perbarui Ringkasan Jam hari ini (Hourly Summary)." "$LK_RESET"
    printf "\n"

    # 4. CHRONOLOGICAL READER
    printf "%s[4. Chronological Reader (lkc)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkc" "$LK_RESET" "$LK_GREY" "Baca seluruh log hari ini." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkc 2026-04-12" "$LK_RESET" "$LK_GREY" "Baca seluruh log pada tanggal spesifik." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcd [YYYYMMDD]" "$LK_RESET" "$LK_GREY" "Tampilkan rekap Daily + Hourly Summary." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkch" "$LK_RESET" "$LK_GREY" "Tampilkan seluruh log pada jam saat ini." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcm [YYYYMM]" "$LK_RESET" "$LK_GREY" "Tampilkan rekap per hari dalam satu bulan." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcy [YYYY]" "$LK_RESET" "$LK_GREY" "Tampilkan rekap per bulan dalam satu tahun." "$LK_RESET"
    printf "\n"

    # 5. ANALYTICS & SEARCH
    printf "%s[5. Analytics & Search Engine]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lks [scope] [keyword]" "$LK_RESET" "$LK_GREY" "Cari kata kunci (Scope: -t, -[HH], YYYY-MM)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort" "$LK_RESET" "$LK_GREY" "Tampilkan Help Menu untuk Analytics Sorter." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort 202604" "$LK_RESET" "$LK_GREY" "Tampilkan tabel matriks log bulan April 2026." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort size asc" "$LK_RESET" "$LK_GREY" "Urutkan file secara global dari terkecil ke terbesar." "$LK_RESET"
    printf "\n"

    # 6. SMART EDITOR
    printf "%s[6. Smart Module Editor (lkv)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv" "$LK_RESET" "$LK_GREY" "Buka file log hari ini di \$EDITOR (Vim)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv 20260422" "$LK_RESET" "$LK_GREY" "Buka file log pada tanggal spesifik." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv <modul>" "$LK_RESET" "$LK_GREY" "Edit skrip modul langsung (Contoh: lkv lki, lkv lksum)." "$LK_RESET"
    
    printf "\n%s========================================================================%s\n" "$LK_ORANGE" "$LK_RESET"
}

# Wrapper agar modul bisa dipanggil langsung
lkh() {
    _lk_show_help
}
