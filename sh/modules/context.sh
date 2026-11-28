#!/bin/sh
# Modul: lk_context (Standalone, Custom Config Path, Tail Support, POSIX Compliant)

# =========================================================================
# Wrapper / Taxonomy Aliases Default
# (Ditulis sebaris per fungsi untuk menjaga stabilitas POSIX parser)
# =========================================================================
sog()      { lk_context "[[Searching on Google]] >>" "$@"; }
todo()     { lk_context "[[TODO]] >>" "$@"; }
ideas()    { lk_context "[[IDEAS]] >>" "$@"; }
problems() { lk_context "[[Problems/Troubleshooting]] >>" "$@"; }
pentest()  { lk_context "[[Pentesting]] >>" "$@"; }

# =========================================================================

lk_context() {
    lctx_prefix="$1"
    shift
    lctx_message="$*"

    if [ -z "$lctx_message" ]; then
        printf "\033[31mError: Pesan log tidak boleh kosong.\033[0m\n"
        return 1
    fi

    LK_STATUS="${LK_STATUS:-stable}"
    LK_VERSION="${LK_VERSION:-v1}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/taxonomy.sh"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    LK_TAIL_LINES="10"

    if [ -f "$LK_CONFIG_FILE" ]; then
        . "$LK_CONFIG_FILE"
    fi

    lctx_date=$(date +%Y-%m-%d)
    lctx_year=$(date +%Y)
    lctx_month=$(date +%Y-%m)
    lctx_hour=$(date +%H:00)
    lctx_time=$(date +%H:%M:%S)
    lctx_indent="    "

    lctx_tdir="$LK_DIR/$lctx_year/$lctx_month"
    lctx_file="$lctx_tdir/$lctx_date${LK_DEFAULT_FORMAT}"

    mkdir -p "$lctx_tdir"

    if [ ! -f "$lctx_file" ]; then
        printf -- "- [[%s]] - (Daily Summary)\n" "$lctx_date" >> "$lctx_file"
        printf "%screated: [[%s]] - %s\n" "$lctx_indent" "$lctx_date" "$lctx_time" >> "$lctx_file"
    fi

    if ! grep -q "^${lctx_indent}- ${lctx_hour} -" "$lctx_file" 2>/dev/null; then
        printf "%s- %s - (Hourly Summary)\n" "$lctx_indent" "$lctx_hour" >> "$lctx_file"
    fi

    if [ -n "$lctx_prefix" ]; then
        lctx_log="${lctx_indent}${lctx_indent}- ${lctx_time} - ${lctx_prefix} ${lctx_message}"
    else
        lctx_log="${lctx_indent}${lctx_indent}- ${lctx_time} - ${lctx_message}"
    fi

    printf "%s\n" "$lctx_log" >> "$lctx_file"

    printf "\033[38;2;0;255;255m[Tercatat]\033[0m %s %s\n" "$lctx_prefix" "$lctx_message"
    printf "\033[2m--- Last %s Lines ---\033[0m\n" "$LK_TAIL_LINES"
    tail -n "$LK_TAIL_LINES" "$lctx_file"
    printf "\033[2m---------------------\033[0m\n"
}

# Personalized Context
lkid() { lk_context "[[LK Ideas]] >>" "$@"; }
q() { lk_context "[[Questions]] >>" "$@"; }
dsh() { lk_context "[[bin/dash]] >>" "$@"; }
bgm() { lk_context "[[Brave gemini.google.com]] >>" "$@"; }
solved() { lk_context "[[Problems Solved]] >>" "$@"; }
sot() { lk_context "[[Scrolling on Tiktok]] >>" "$@"; }
qfr() { lk_context "[[Question]] >>" "$@"; }
gam() { lk_context "[[Google AI Mode]] >>" "$@"; }
lktest() { lk_context "[[Testing New LK Script]] >>" "$@"; }
resthink() { lk_context "[[ResThink Mode]] >>" "$@"; }
contemplation() { lk_context "[[Contemplation]] >>" "$@"; }
bugs() { lk_context "[[Bugs]] >>" "$@"; }
vivo() { lk_context "[[Vivo S1 Pro]] >>" "$@"; }
