#!/bin/sh
# Module: lkh (LogKlerk Help Manual - v0.0.4 Experimental)

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
    printf "%s                 LogKlerk (LK) v0.0.4 Experimental Manual               %s\n" "$LK_ORANGE" "$LK_RESET"
    printf "%s========================================================================%s\n\n" "$LK_ORANGE" "$LK_RESET"
    
    # 1. CORE LOGGING
    printf "%s[1. Core Logging & TUI]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lk [text]" "$LK_RESET" "$LK_GREY" "Log standard text to the current timestamp instantly." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lki" "$LK_RESET" "$LK_GREY" "Open Interactive Mode (Hybrid Shell + TUI)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lk -v \"[text]\"" "$LK_RESET" "$LK_GREY" "Log text with an automatic LogKlerk version tag." "$LK_RESET"
    printf "\n"

    # 2. TAXONOMY & CONTEXT
    printf "%s[2. Context & Taxonomy Engine]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkset <alias>=\"[[Tag]]\"" "$LK_RESET" "$LK_GREY" "Create a dynamic tag alias (e.g., lkset wbl=\"[[Web]]\")." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkfiles <alias>=\"[[Dir]]\"" "$LK_RESET" "$LK_GREY" "Create an alias to an exclusive directory file (Standalone)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias> [text]" "$LK_RESET" "$LK_GREY" "Use a registered alias to log text instantly." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias>" "$LK_RESET" "$LK_GREY" "Execute an alias to enter LKI mode with that tag pre-loaded." "$LK_RESET"
    printf "\n"

    # 3. QUICK NOTES & SMART ALIAS
    printf "%s[3. Quick Notes (lknote)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lknote list" "$LK_RESET" "$LK_GREY" "List all static notes stored in LK_DIR/note/." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lknote <alias>=\"<file.md>\"" "$LK_RESET" "$LK_GREY" "Register a smart alias for a new note file." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias> \"[text]\"" "$LK_RESET" "$LK_GREY" "Append text to the note file silently from CLI." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "<alias> -v" "$LK_RESET" "$LK_GREY" "View (cat) the contents of the note file." "$LK_RESET"
    printf "\n"

    # 4. SUMMARIZER
    printf "%s[4. Smart Summarizer (lksum)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 2026 \"Text\"" "$LK_RESET" "$LK_GREY" "Update the Yearly Summary." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 202604 \"Text\"" "$LK_RESET" "$LK_GREY" "Update the Monthly Summary." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 20260422 \"Text\"" "$LK_RESET" "$LK_GREY" "Update the Daily Summary." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 14 \"Text\"" "$LK_RESET" "$LK_GREY" "Update today's Hourly Summary for the specified hour." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksum 01-03 \"Text\"" "$LK_RESET" "$LK_GREY" "Update Batch Hourly Summary from HH to HH." "$LK_RESET"
    printf "\n"

    # 5. CHRONOLOGICAL READER
    printf "%s[5. Chronological Reader (lkc)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkc" "$LK_RESET" "$LK_GREY" "Read all logs generated today." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkc 2026-04-12" "$LK_RESET" "$LK_GREY" "Read all logs on a specific date." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcd [YYYYMMDD]" "$LK_RESET" "$LK_GREY" "Display a recap of Daily + Hourly Summaries." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkch" "$LK_RESET" "$LK_GREY" "Display all logs within the current hour block." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcm [YYYYMM]" "$LK_RESET" "$LK_GREY" "Display a recap of all Daily Summaries in a month." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkcy [YYYY]" "$LK_RESET" "$LK_GREY" "Display a recap of all Monthly Summaries in a year." "$LK_RESET"
    printf "\n"

    # 6. ANALYTICS & SEARCH
    printf "%s[6. Analytics & Search Engine]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lks [scope] [keyword]" "$LK_RESET" "$LK_GREY" "Chronological search (Scope: -t, -[HH], YYYY-MM)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort" "$LK_RESET" "$LK_GREY" "Show Help Menu for Analytics Sorter." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort 202604" "$LK_RESET" "$LK_GREY" "Show a log matrix table for April 2026." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lksort size asc" "$LK_RESET" "$LK_GREY" "Sort files globally from smallest to largest size." "$LK_RESET"
    printf "\n"

    # 7. SMART EDITOR
    printf "%s[7. Smart Module Editor (lkv)]%s\n" "$LK_LIME" "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv" "$LK_RESET" "$LK_GREY" "Open today's log file in \$EDITOR (e.g., Vim)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv 20260422" "$LK_RESET" "$LK_GREY" "Open the log file on a specific date." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv <module>" "$LK_RESET" "$LK_GREY" "Edit module script directly (e.g., lkv lki, lkv lksum)." "$LK_RESET"
    printf "  %s%-30s%s : %s%s%s\n" "$LK_CYAN" "lkv conf" "$LK_RESET" "$LK_GREY" "Edit the primary configuration file (lk.conf)." "$LK_RESET"
    
    printf "\n%s========================================================================%s\n" "$LK_ORANGE" "$LK_RESET"
}

# Wrapper to allow standalone module execution
lkh() {
    _lk_show_help
}
