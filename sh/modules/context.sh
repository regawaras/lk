#!/bin/sh
# Module: lk_context (Standalone, Custom Config Path, Tail Support, POSIX Compliant)

# =========================================================================
# Universal Colorizer Engine for Tail Feedback
# =========================================================================
_lctx_colorizer() {
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;204;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[90m')
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')

    awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
    $0 ~ /^- \[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/ { print amber $0 reset; next }
    $0 ~ /^[ ]{4}- \[\[[0-9]{4}-[0-9]{2}\]\]/ { print cyan $0 reset; next }
    $0 ~ /^[ ]{4}- [0-2][0-9]:00/ { print cyan $0 reset; next }
    $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
        ts_part = substr($0, 1, 21)
        rest_part = substr($0, 22)
        if (match(rest_part, /^\[\[.*\]\] >>/)) {
            tag_part = substr(rest_part, 1, RLENGTH)
            msg_part = substr(rest_part, RLENGTH + 1)
            print lime ts_part orange tag_part grey msg_part reset
        } else {
            print lime ts_part grey rest_part reset
        }
        next
    }
    { print grey $0 reset }
    '
}

# =========================================================================
# Default Wrapper / Taxonomy Aliases
# (Written one line per function to maintain POSIX parser stability)
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

    # IF MESSAGE IS EMPTY: Call LKI (Interactive Mode) with current context
    if [ -z "$lctx_message" ]; then
        # If lki command is available in environment, execute it. Otherwise, warn.
        if command -v lki >/dev/null 2>&1 || type lki >/dev/null 2>&1; then
            lki "$lctx_prefix"
            return $?
        else
            printf "\033[31m[Error]\033[0m Log message is empty and 'lki' module not found.\n"
            return 1
        fi
    fi

    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/taxonomy.sh"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    LK_TAIL_LINES="${LK_TAIL_LINES:-10}" # Added fallback

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

    # Success feedback matching the universal format of lk.sh
    printf "\033[38;2;100;255;0m✔\033[0m      - %s - \033[38;2;255;102;0m%s\033[0m \033[90m%s\033[0m\n" "$lctx_time" "$lctx_prefix" "$lctx_message"
    printf "\033[38;2;255;204;0m--- Tail: Last %s lines from %s ---\033[0m\n" "$LK_TAIL_LINES" "$(basename "$lctx_file")"
    tail -n "$LK_TAIL_LINES" "$lctx_file" | _lctx_colorizer
}

# =========================================================================
# EXCLUSIVE FILE CONTEXT ENGINE (lkfiles target)
# =========================================================================
lk_exclusive_context() {
    lexc_folder="$1"
    lexc_prefix="$2"
    shift 2
    lexc_message="$*"

    # If message is empty, call interactive LKI (with warning if missing)
    if [ -z "$lexc_message" ]; then
        if command -v lki >/dev/null 2>&1 || type lki >/dev/null 2>&1; then
            lki "$lexc_prefix"
            return $?
        else
            printf "\033[31m[Error]\033[0m Log message is empty.\n"
            return 1
        fi
    fi

    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.3}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_TAIL_LINES="${LK_TAIL_LINES:-10}"

    lexc_date=$(date +%Y-%m-%d)
    lexc_hour=$(date +%H:00)
    lexc_time=$(date +%H:%M:%S)
    lexc_indent="    "

    # --- EXCLUSIVE PATH ---
    # Instead of LK_DIR/YYYY/YYYY-MM, it goes directly to LK_DIR/Folder
    lexc_tdir="$LK_DIR/$lexc_folder"
    lexc_file="$lexc_tdir/$lexc_date${LK_DEFAULT_FORMAT}"

    mkdir -p "$lexc_tdir"

    if [ ! -f "$lexc_file" ]; then
        printf -- "- [[%s]] - (Exclusive Log: %s)\n" "$lexc_date" "$lexc_folder" >> "$lexc_file"
        printf "%screated: [[%s]] - %s\n" "$lexc_indent" "$lexc_date" "$lexc_time" >> "$lexc_file"
    fi

    if ! grep -q "^${lexc_indent}- ${lexc_hour} -" "$lexc_file" 2>/dev/null; then
        printf "%s- %s - (Hourly Summary)\n" "$lexc_indent" "$lexc_hour" >> "$lexc_file"
    fi

    lexc_log="${lexc_indent}${lexc_indent}- ${lexc_time} - ${lexc_prefix} ${lexc_message}"
    printf "%s\n" "$lexc_log" >> "$lexc_file"

    # Feedback CLI Orange (225;102;0) for Exclusive paths
    printf "\033[38;2;225;102;0m[Exclusive: /%s]\033[0m - %s - \033[38;2;255;102;0m%s\033[0m \033[90m%s\033[0m\n" "$lexc_folder" "$lexc_time" "$lexc_prefix" "$lexc_message"
    printf "\033[38;2;255;204;0m--- Tail: Last %s lines from %s ---\033[0m\n" "$LK_TAIL_LINES" "$(basename "$lexc_file")"
    tail -n "$LK_TAIL_LINES" "$lexc_file" | _lctx_colorizer
}

# Personalized Context
lkid() { lk_context "[[LK Ideas]] >>" "$@"; }
questions() { lk_context "[[Questions]] >>" "$@"; }
dsh() { lk_context "[[bin/dash]] >>" "$@"; }
bgm() { lk_context "[[Brave gemini.google.com]] >>" "$@"; }
solved() { lk_context "[[Problems Solved]] >>" "$@"; }
scrt() { lk_context "[[Scrolling on Tiktok]] >>" "$@"; }
qfr() { lk_context "[[Question for Later]] >>" "$@"; }
gam() { lk_context "[[Google AI Mode]] >>" "$@"; }
lktest() { lk_context "[[Testing New LK Script]] >>" "$@"; }
resthink() { lk_context "[[ResThink Mode]] >>" "$@"; }
contemplation() { lk_context "[[Contemplation]] >>" "$@"; }
bugs() { lk_context "[[Bugs]] >>" "$@"; }
vivo() { lk_context "[[Vivo S1 Pro]] >>" "$@"; }
sot() { lk_context "[[Searching on Tiktok]] >>" "$@"; }
wbl() { lk_context "[[Website Links]] >>" "$@"; }
lkbugs() { lk_context "[[LK Bugs]] >>" "$@"; }
dsd() { lk_exclusive_context "Dsd" "[[Dsd]] >>" "$@"; }
commentary() { lk_context "[[Commentary]] >>" "$@"; }
termux() { lk_context "[[Termux]] >>" "$@"; }
ytchannel() { lk_context "[[Youtube Channel]] >>" "$@"; }
nixos() { lk_context "[[NixOS]] >>" "$@"; }
gemini() { lk_context "[[Gemini AI]] >>" "$@"; }
sosm() { lk_context "[[Scrolling on Social Media]] >>" "$@"; }
pact() { lk_context "[[physical activities]] >>" "$@"; }
scritic() { lk_context "[[Self Critic]] >>" "$@"; }
redmi() { lk_context "[[Redmi Pad 2 Pro]] >>" "$@"; }
imagen() { lk_context "[[Gemini AI Image Generation]] >>" "$@"; }
obs() { lk_context "[[obs-studio]] >>" "$@"; }
lkkrita() { lk_context "[[Krita]] >>" "$@"; }
health() { lk_context "[[Health Concerns]] >>" "$@"; }
lkchangelog() { lk_context "[[LK Changelog.md]] >>" "$@"; }
ifr() { lk_context "[[Ideas from ResThink]] >>" "$@"; }
gaps() { lk_context "[[Gemini AI Apps]] >>" "$@"; }
rot() { lk_context "[[Researching on Tiktok]] >>" "$@"; }
roig() { lk_context "[[Researching on Instagram]] >>" "$@"; }
acer() { lk_context "[[Acer Aspire 5]] >>" "$@"; }
qrl() { lk_context "[[QRL Quantum Resistant Ledger]] >>" "$@"; }
tcommand() { lk_context "[[Terminal Commands]] >>" "$@"; }
lkxmrig() { lk_context "[[XMRig]] >>" "$@"; }
xanmod() { lk_context "[[XanMod Linux Kernel]] >>" "$@"; }
comfyui() { lk_context "[[ComfyUI]] >>" "$@"; }
riverwm() { lk_context "[[RiverWM]] >>" "$@"; }
capcut() { lk_context "[[Capcut]] >>" "$@"; }
wifi() { lk_context "[[WiFi]] >>" "$@"; }
codefix() { lk_context "[[Fixing Code]] >>" "$@"; }
fixcode() { lk_context "[[Fixing Code]] >>" "$@"; }
ccc() { lk_context "[[Changing Configuration Code]] >>" "$@"; }
cucunguk() { lk_context "[[Cucunguk Invasion]] >>" "$@"; }
syt() { lk_context "[[Searching on Youtube]] >>" "$@"; }
ryt() { lk_context "[[Researching on Youtube]] >>" "$@"; }
soig() { lk_context "[[Scrolling on Instagram]] >>" "$@"; }
scap() { lk_context "[[Searching on Capcut]] >>" "$@"; }
logklerk() { lk_context "[[LK LogKlerk]] >>" "$@"; }
bootime() { lk_context "[[Laptop BootTime Statistics]] >>" "$@"; }
kontol() { lk_context "[[Keluh Kesah]] >>" "$@"; }
sparlaverse() { lk_context "[[Sparlaverse]] >>" "$@"; }
sparlafs() { lk_context "[[Sparlafs]] >>" "$@"; }
lkcreek() { lk_context "[[Creek]] >>" "$@"; }
contoh() { lk_context "[[contoh]] >>" "$@"; }
private() { lk_exclusive_context "Private" "[[Private]] >>" "$@"; }
scrcap() { lk_context "[[Scrolling on Capcut Templates]] >>" "$@"; }
cgpt() { lk_context "[[ChatGPT.com]] >>" "$@"; }
sogi() { lk_context "[[Searching on Google Images]] >>" "$@"; }
nixpkgs() { lk_context "[[NixOS Packages]] >>" "$@"; }
lkbrave() { lk_context "[[Brave]] >>" "$@"; }
lkssh() { lk_context "[[SSH]] >>" "$@"; }
canon() { lk_context "[[DSLR Camera CANON EOS 1200D]] >>" "$@"; }
termius() { lk_context "[[Termius]] >>" "$@"; }
productivity() { lk_context "[[Productivity]] >>" "$@"; }
yantra() { lk_context "[[Yantra CLI Launcher Pro]] >>" "$@"; }
recording() { lk_context "[[Recording Screen]] >>" "$@"; }
tomorrow() { lk_context "[[Plan for Tomorrow]] >>" "$@"; }
tolol() { lk_context "[[Tolol]] >>" "$@"; }
posting() { lk_context "[[Posting]] >>" "$@"; }
dsdcomfyui() { lk_exclusive_context "Dsd ComfyUI" "[[Dsd ComfyUI]] >>" "$@"; }
watch() { lk_context "[[Watching Videos]] >>" "$@"; }
fileplus() { lk_context "[[File Manager Plus]] >>" "$@"; }
hypothesis() { lk_context "[[Hypothesis]] >>" "$@"; }
troubleshooting() { lk_context "[[TROUBLESHOOTING]] >>" "$@"; }
