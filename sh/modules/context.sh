#!/bin/sh
# Module: lk_context (Standalone, Custom Config Path, Tail Support, POSIX Compliant)
# Updated for LogKlerk v0.0.5 (Chronological AWK Injector)

_lctx_colorizer() {
    LK_RESET=$(printf '\033[0m')
    LK_AMBER=$(printf '\033[38;2;255;204;0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')
    LK_GREY=$(printf '\033[90m')
    LK_CYAN=$(printf '\033[38;2;0;255;255m')
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')

    awk -v reset="$LK_RESET" -v amber="$LK_AMBER" -v cyan="$LK_CYAN" -v grey="$LK_GREY" -v lime="$LK_LIME" -v orange="$LK_ORANGE" '
    $0 ~ /^-[[:space:]]*(#)?[[:space:]]*\[\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\]\]/ { print amber $0 reset; next }
    $0 ~ /^[ ]{4}- (## )?[0-2][0-9]:00/ { print cyan $0 reset; next }
    $0 ~ /^[ ]{8}- [0-2][0-9]:[0-5][0-9]:[0-5][0-9] - / {
        ts_part = substr($0, 1, 21)
        rest_part = substr($0, 22)
        if (match(rest_part, /^\[\[.*\]\] >>/)) {
            tag_part = substr(rest_part, 1, RLENGTH)
            msg_part = substr(rest_part, RLENGTH + 1)
            print lime ts_part orange tag_part grey msg_part reset
        } else if (match(rest_part, /^\[[a-zA-Z0-9._-]+\] >>/)) {
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

sog()      { lk_context "[[Searching on Google]] >>" "$@"; }
todo()     { lk_context "[[TODO]] >>" "$@"; }
ideas()    { lk_context "[[IDEAS]] >>" "$@"; }
problems() { lk_context "[[Problems/Troubleshooting]] >>" "$@"; }
pentest()  { lk_context "[[Pentesting]] >>" "$@"; }

lk_context() {
    lctx_prefix="$1"
    shift
    lctx_message="$*"

    if [ -z "$lctx_message" ]; then
        if command -v lki >/dev/null 2>&1 || type lki >/dev/null 2>&1; then
            lki "$lctx_prefix"
            return $?
        else
            printf "\033[31m[Error]\033[0m Log message is empty and 'lki' module not found.\n"
            return 1
        fi
    fi

    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.5}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_DIR="${HOME}/.local/share/logklerk"
    LK_DEFAULT_FORMAT=".md"
    LK_TAIL_LINES="${LK_TAIL_LINES:-10}"

    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

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
        printf -- "- # [[%s]] - (Daily Summary)\n" "$lctx_date" > "$lctx_file"
        printf "%screated: [[%s]] - %s\n" "$lctx_indent" "$lctx_date" "$lctx_time" >> "$lctx_file"
    fi

    if [ -n "$lctx_prefix" ]; then
        lctx_log="${lctx_indent}${lctx_indent}- ${lctx_time} - ${lctx_prefix} ${lctx_message}"
    else
        lctx_log="${lctx_indent}${lctx_indent}- ${lctx_time} - ${lctx_message}"
    fi

    lctx_tmp="${lctx_file}.tmp"
    new_hdr="    - ## $lctx_hour - (Hourly Summary)"

    awk -v t_hr="$lctx_hour" -v n_hdr="$new_hdr" -v n_log="$lctx_log" '
    BEGIN {
        inserted = 0
        in_target = 0
        t_hr_val = substr(t_hr, 1, 2) + 0
    }
    {
        if ($0 ~ /^ {4}- (## )?[0-2][0-9]:00 /) {
            match($0, /[0-2][0-9]:00/)
            curr_hr_val = substr($0, RSTART, 2) + 0
            
            if (curr_hr_val == t_hr_val) {
                in_target = 1
                print $0
                next
            } else if (curr_hr_val > t_hr_val && inserted == 0) {
                if (in_target == 1) {
                    print n_log
                } else {
                    print n_hdr
                    print n_log
                }
                inserted = 1
                in_target = 0
                print $0
                next
            } else {
                in_target = 0
                print $0
                next
            }
        }
        print $0
    }
    END {
        if (inserted == 0) {
            if (in_target == 1) {
                print n_log
            } else {
                print n_hdr
                print n_log
            }
        }
    }' "$lctx_file" > "$lctx_tmp" && mv "$lctx_tmp" "$lctx_file"

    printf "\033[38;2;100;255;0m✔\033[0m      - %s - \033[38;2;255;102;0m%s\033[0m \033[90m%s\033[0m\n" "$lctx_time" "$lctx_prefix" "$lctx_message"
    printf "\033[38;2;255;204;0m--- Tail: Last %s lines from %s ---\033[0m\n" "$LK_TAIL_LINES" "$(basename "$lctx_file")"
    tail -n "$LK_TAIL_LINES" "$lctx_file" | _lctx_colorizer
}

lk_exclusive_context() {
    lexc_folder="$1"
    lexc_prefix="$2"
    shift 2
    lexc_message="$*"

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
    LK_VERSION="${LK_VERSION:-v0.0.5}"
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

    lexc_tdir="$LK_DIR/$lexc_folder"
    lexc_file="$lexc_tdir/$lexc_date${LK_DEFAULT_FORMAT}"

    mkdir -p "$lexc_tdir"

    if [ ! -f "$lexc_file" ]; then
        printf -- "- # [[%s]] - (Exclusive Log: %s)\n" "$lexc_date" "$lexc_folder" > "$lexc_file"
        printf "%screated: [[%s]] - %s\n" "$lexc_indent" "$lexc_date" "$lexc_time" >> "$lexc_file"
    fi

    lexc_log="${lexc_indent}${lexc_indent}- ${lexc_time} - ${lexc_prefix} ${lexc_message}"
    lexc_tmp="${lexc_file}.tmp"
    new_hdr="    - ## $lexc_hour - (Hourly Summary)"

    awk -v t_hr="$lexc_hour" -v n_hdr="$new_hdr" -v n_log="$lexc_log" '
    BEGIN {
        inserted = 0
        in_target = 0
        t_hr_val = substr(t_hr, 1, 2) + 0
    }
    {
        if ($0 ~ /^ {4}- (## )?[0-2][0-9]:00 /) {
            match($0, /[0-2][0-9]:00/)
            curr_hr_val = substr($0, RSTART, 2) + 0
            
            if (curr_hr_val == t_hr_val) {
                in_target = 1
                print $0
                next
            } else if (curr_hr_val > t_hr_val && inserted == 0) {
                if (in_target == 1) {
                    print n_log
                } else {
                    print n_hdr
                    print n_log
                }
                inserted = 1
                in_target = 0
                print $0
                next
            } else {
                in_target = 0
                print $0
                next
            }
        }
        print $0
    }
    END {
        if (inserted == 0) {
            if (in_target == 1) {
                print n_log
            } else {
                print n_hdr
                print n_log
            }
        }
    }' "$lexc_file" > "$lexc_tmp" && mv "$lexc_tmp" "$lexc_file"

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
gf() { lk_context "[[Gemini AI Free]] >>" "$@"; }
lktest() { lk_context "[[Testing New LK Script]] >>" "$@"; }
resthink() { lk_context "[[ResThink]] >>" "$@"; }
contemplation() { lk_context "[[Contemplation]] >>" "$@"; }
bugs() { lk_context "[[Bugs]] >>" "$@"; }
vivo() { lk_context "[[Vivo S1 Pro]] >>" "$@"; }
sot() { lk_context "[[Searching on Tiktok]] >>" "$@"; }
wbl() { lk_context "[[Website Links]] >>" "$@"; }
lkbugs() { lk_context "[[LK Bugs]] >>" "$@"; }
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
lkrita() { lk_context "[[Krita]] >>" "$@"; }
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
logklerk() { lk_context "[[LogKlerk]] >>" "$@"; }
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
watching() { lk_context "[[Watching Videos]] >>" "$@"; }
fileplus() { lk_context "[[File Manager Plus]] >>" "$@"; }
hypothesis() { lk_context "[[Hypothesis]] >>" "$@"; }
troubleshooting() { lk_context "[[TROUBLESHOOTING]] >>" "$@"; }
konsole() { lk_context "[[KDE Plasma Konsole]] >>" "$@"; }
mimpi() { lk_context "[[Dreams Story History]] >>" "$@"; }
orgfiles() { lk_context "[[Organizing Files]] >>" "$@"; }
disnew() { lk_context "[[Discover New Things]] >>" "$@"; }
lkkate() { lk_context "[[Writing on Kate]] >>" "$@"; }
fgm() { lk_context "[[Firefox gemini.google.com]] >>" "$@"; }
quotes() { lk_context "[[Quotes]] >>" "$@"; }
lfsum() { lk_context "[[lfsum]] >>" "$@"; }
row() { lk_context "[[Reading on Website]] >>" "$@"; }
treview() { lk_context "[[Today Review]] >>" "$@"; }
offscreenlaptop() { lk_context "[[Laptop Off Screen]] >>" "$@"; }
wakeup() { lk_context "[[Wake Up]] >>" "$@"; }
formon() { lk_context "[[Forgetful Moment]] >>" "$@"; }
kdeplasma() { lk_context "[[KDE Plasma]] >>" "$@"; }
failed() { lk_context "[[Failed]] >>" "$@"; }
plan() { lk_context "![PLAN]! >>" "$@"; }
oldsum() { lk_context "[[Adding Old Summary]] >>" "$@"; }
reflection() { lk_context "[[Reflections]] >>" "$@"; }
experiment() { lk_context "[[Experimenting]] >>" "$@"; }
ggems() { lk_context "[[Gemini AI Gems]] >>" "$@"; }
hyperofset() { lk_context "[[Hyperfocus Offset]] >>" "$@"; }
compiling() { lk_context "[[Compiling Things]] >>" "$@"; }
events() { lk_context "[[Events]] >>" "$@"; }
xmr() { lk_context "[[Monero XMR]] >>" "$@"; }
migratingdata() { lk_context "[[Migrating Data]] >>" "$@"; }
scrf() { lk_context "[[Scrolling on Facebook]] >>" "$@"; }
reddit() { lk_context "[[Reddit]] >>" "$@"; }
orgroom() { lk_context "[[Organizing Room]] >>" "$@"; }
owl() { lk_context "[[Open Website Links]] >>" "$@"; }
pacton() { lk_context "[[Physical Action]] >>" "$@"; }
lkdisk() { lk_context "[[Disk]] >>" "$@"; }
soy() { lk_context "[[Searching on Youtube]] >>" "$@"; }
wytfs() { lk_context "[[Watching on Youtube from Search]] >>" "$@"; }
cot() { lk_context "[[Commenting on Tiktok]] >>" "$@"; }
ifo() { lk_context "[[Ideas from Orgroom]] >>" "$@"; }
reminder() { lk_context "[[Reminder]] >>" "$@"; }
test3() { lk_context "test3 >>" "$@"; }
test4() { lk_context "test 4 >>" "$@"; }
test5() { lk_context "[[Test 5]] >>" "$@"; }
cfr() { lk_context "[[Commentary from ResThink]] >>" "$@"; }
mtg() { lk_context "[[Meta-Cognition]] >>" "$@"; }
itg() { lk_context "[[Internal-Thought]] >>" "$@"; }
saran() { lk_context "[[Saran]] >>" "$@"; }
ifm() { lk_context "[[Ideas from Mandi]] >>" "$@"; }
govkontol() { lk_context "[[Kritik Pemerintah]] >>" "$@"; }
wyt() { lk_context "[[Watch Youtube]] >>" "$@"; }
scrig() { lk_context "[[Instagram Scrolling]] >>" "$@"; }
lkidfr() { lk_context "[[LogKlerk Ideas from ResThink]] >>" "$@"; }
scrx() { lk_context "[[Scrolling on Twitter X]] >>" "$@"; }
wytfh() { lk_context "[[Watching on Youtube from Homepage]] >>" "$@"; }
adhd() { lk_context "[[ADHD]] >>" "$@"; }
wishlist() { lk_context "[[Wishlist]] >>" "$@"; }
sparnote() { lk_context "[[Sparlaverse Note]] >>" "$@"; }
sparsug() { lk_context "[[Sparlaverse Suggestion]] >>" "$@"; }
sparwork() { lk_context "[[Working on Sparlaverse]] >>" "$@"; }
dft() { lk_context "[[Discover from Tiktok]] >>" "$@"; }
contentideas() { lk_context "[[Content Ideas]] >>" "$@"; }
lkfuzzel() { lk_context "[[Fuzzel]] >>" "$@"; }
comfymistake() { lk_context "[[ComfyUI Mistake]] >>" "$@"; }
comfygen() { lk_context "[[ComfyUI Image Generation]] >>" "$@"; }
comfydone() { lk_context "[[ComfyUI Generation Done]] >>" "$@"; }
discussion() { lk_context "[[Discussion]] >>" "$@"; }
lkgemini() { lk_context "[[LogKlerk Gemini AI]] >>" "$@"; }
orgroommax() { lk_context "[[Maximum Organizing Room]] >>" "$@"; }
ifb() { lk_context "[[Ideas from Bathroom]] >>" "$@"; }
orgroommin() { lk_context "[[Minimal Organizing Room]] >>" "$@"; }
jumatan() { lk_context "[[Jumatan]] >>" "$@"; }
sparid() { lk_context "[[Sparlaverse Ideas]] >>" "$@"; }
spargemini() { lk_context "[[Sparlaverse Research Gemini AI]] >>" "$@"; }
lkdolphin() { lk_context "[[Dolphin]] >>" "$@"; }
comfytime() { lk_context "[[ComfyUI Generation Time]] >>" "$@"; }
pinterest() { lk_context "[[Pinterest]]] >>" "$@"; }
kritaai() { lk_context "[[Krita AI]] >>" "$@"; }
spargen() { lk_context "[[Sparlaverse Gemini Image Generation]] >>" "$@"; }
morningbath() { lk_context "[[MORNING-BATH]] >>" "$@"; }
cons() { lk_context "[[Commentary from On Screen]] >>" "$@"; }
rfr() { lk_context "[[Remember from ResThink]] >>" "$@"; }
nyapu() { lk_context "[[NYAPU]] >>" "$@"; }
ifnyapu() { lk_context "[[Ideas from Nyapu]] >>" "$@"; }
veo() { lk_context "[[Gemini Veo 3]] >>" "$@"; }
gflow() { lk_context "[[Google Flow]] >>" "$@"; }
notebooklm() { lk_context "[[Google Notebook LM]] >>" "$@"; }
gems() { lk_context "[[Gemini AI Gems]] >>" "$@"; }
sparcom() { lk_context "[[Sparlaverse Commentary]] >>" "$@"; }
flow() { lk_context "[[Google Flow]] >>" "$@"; }
grok() { lk_context "[[Grok AI]] >>" "$@"; }
xpost() { lk_context "[[Posting on X]] >>" "$@"; }
note() { lk_context "[[Note]] >>" "$@"; }
gempro() { lk_context "[[Gemini AI Pro]] >>" "$@"; }
kernel() { lk_context "[[Kernel]] >>" "$@"; }
mining() { lk_context "[[Mining]] >>" "$@"; }
onion() { lk_context "[[Onion]] >>" "$@"; }
lktty() { lk_context "[[LK TTY]] >>" "$@"; }
bam() { lk_context "[[Brave AI Mode >>" "$@"; }
motoran() { lk_context "[[Motoran]] >>" "$@"; }
btc() { lk_context "[[Bitcoin]] >>" "$@"; }
btcidr() { lk_context "[[Bitcoin/IDR]] >>" "$@"; }
mexc() { lk_context "[[MEXC]] >>" "$@"; }
xtm() { lk_context "[[XTM MinoTari L1]] >>" "$@"; }
gg() { lk_context "[[Googling]] >>" "$@"; }
bal() { lk_context "[[balance]] >>" "$@"; }
github() { lk_context "[[GitHub]] >>" "$@"; }
qos() { lk_context "[[Question Off Screen]] >>" "$@"; }
lkcom() { lk_context "[[LK Commentary]] >>" "$@"; }
gn() { lk_context "[[Google News]] >>" "$@"; }
uninstall() { lk_context "[[Uninstall]] >>" "$@"; }
info() { lk_context "[[Information]] >>" "$@"; }
ncnn() { lk_context "[[QwenImage NCNN Vulkan]] >>" "$@"; }
cf() { lk_context "[[ComfyUI Prompts]] >>" "$@"; }
venice() { lk_context "[[Venice AI]] >>" "$@"; }
twitter() { lk_context "[[X Twitter]] >>" "$@"; }
civitai() { lk_context "[[CivitAI]] >>" "$@"; }
sox() { lk_context "[[Searching on X Twitter]] >>" "$@"; }
dolaai() { lk_context "[[Dola AI]] >>" "$@"; }
act() { lk_context "[[Activity]] >>" "$@"; }
kompos() { lk_context "[[Komposting]] >>" "$@"; }
lesson() { lk_context "[[Lesson]] >>" "$@"; }
tiktok() { lk_context "[[Tiktok]] >>" "$@"; }
llm() { lk_context "[[llama.cpp]] >>" "$@"; }
prompts() { lk_context "[[Prompts]] >>" "$@"; }
claude() { lk_context "[[Claude AI]] >>" "$@"; }
activity() { lk_context "[[activity]] >>" "$@"; }
shopee() { lk_context "[[Shopee]] >>" "$@"; }
kgdd() { lk_context "[[Kenapa_Gak_Dari_Dulu]] >>" "$@"; }
testing() { lk_context "[[Testing]] >>" "$@"; }

# Dsd Context
dsd() { lk_exclusive_context "Dsd" "[[Dsd]] >>" "$@"; }
dsdcomfyui() { lk_exclusive_context "Dsd ComfyUI" "[[Dsd ComfyUI]] >>" "$@"; }


lkpassage() { local tgt="/srv/als/lk/note/lkpassage.md"; mkdir -p "${tgt%/*}" 2>/dev/null; [ ! -f "$tgt" ] && touch "$tgt"; if [ $# -eq 0 ]; then ${EDITOR:-vi} "$tgt"; elif [ "$1" = "-v" ] || [ "$1" = "view" ]; then cat "$tgt"; else printf -- "- %s\\n" "$*" >> "$tgt"; printf "\\033[38;2;100;255;0m✔\\033[0m Note appended to \\033[38;2;0;255;255mlkpassage.md\\033[0m\\n"; fi; }
ref() { lk_context "[[Reference]] >>" "$@"; }
mati() { lk_context "[[Laptop Mati]] >>" "$@"; }
groom() { lk_context "[[GREAT_ORGANIZING_ROOM]! >>" "$@"; }
lora() { lk_context "[[CivitAI Lora Training]] >>" "$@"; }
restart() { lk_context "[[Restarting]] >>" "$@"; }
com() { lk_context "[[Commentary]] >>" "$@"; }
drawing() { lk_context "[[Drawing]] >>" "$@"; }
