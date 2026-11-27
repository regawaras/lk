# Modul: LogKlerk Help Manual (lkh)
lkh() {
    printf "\033[38;2;255;117;0m=== LogKlerk (LK) System Manual ===\033[0m\n"
    
    printf "\033[38;2;0;255;255mCore Write & Config Commands:\033[0m\n"
    printf "  \033[1mlk [text]\033[0m               : Append a new log. If empty, enters Interactive Mode.\n"
    printf "  \033[1mlk -set -alias <x>=\"<y>\"\033[0m : Create dynamic tag (e.g., lk -set alias soy=\"[[Searching on Youtube]]\").\n"
    printf "  \033[1mlk -set -dir <path>\033[0m       : Change data directory (Options: -home, -default, or /custom/path).\n"
    printf "  \033[1mlk -set -today [text]\033[0m   : Set/update the Daily Summary at the top of today's file.\n"
    printf "  \033[1mlk -set YYYY-MM-DD [txt]\033[0m: Set/update the Daily Summary for a specific historical date.\n"
    printf "  \033[1mlk -set [HH] | [HH-HH]\033[0m  : Set an Hourly Summary (e.g., 'lk -set 08-10 \"Deep Work\"').\n"
    printf "  \033[1mlk -search | -s\033[0m         : Unified search engine. Same as using 'lks' command.\n"
    printf "  \033[1mlk -help | -h\033[0m           : Show this manual.\n"
    
    printf "\n\033[38;2;0;255;255mReading, Editing & Display (lkc & vlk):\033[0m\n"
    printf "  \033[1mlkc\033[0m                   : Read all logs for today (Fallback Alias: clk).\n"
    printf "  \033[1mlkc -a | -all\033[0m         : Display ALL daily summaries across all time.\n"
    printf "  \033[1mlkc -y | -year\033[0m        : Display daily summaries for the CURRENT year.\n"
    printf "  \033[1mlkc -m | -month\033[0m       : Display daily summaries for the CURRENT month (Alias: clkm).\n"
    printf "  \033[1mlkc YYYY-MM-DD\033[0m        : Display full logs for a specific date.\n"
    printf "  \033[1mlkc [HH] | [HH-HH]\033[0m    : Display logs for a specific hour/range today.\n"
    printf "  \033[1mlkcs\033[0m                  : Display today's main Daily Summary & all Hourly Summaries (Alias: clks).\n"
    printf "  \033[1mlkch\033[0m                  : Display all logs for the CURRENT hour (Alias: clkh).\n"
    printf "  \033[1mvlk [YYYY-MM-DD]\033[0m      : Open TODAY's or a specific date's markdown file in \$EDITOR.\n"
    printf "  \033[1mvlkc\033[0m                  : Edit the core LogKlerk script directly.\n"
    
    printf "\n\033[38;2;0;255;255mAdvanced Search Engine (lks):\033[0m\n"
    printf "  \033[1mlks [keyword]\033[0m         : Recursive search across ALL files and time.\n"
    printf "  \033[1mlks -t [keyword]\033[0m      : Search only in TODAY's file.\n"
    printf "  \033[1mlks -[HH] [keyword]\033[0m   : Search across all days, but ONLY at a specific hour.\n"
    printf "  \033[1mlks YYYY-MM [keyword]\033[0m : Search within a specific month.\n"
    printf "  \033[1mlks YYYY-MM-DD [key]\033[0m  : Search only on a specific historical date.\n"
    
    printf "\n\033[38;2;0;255;255mDynamic Tags Usage:\033[0m\n"
    printf "  Simply type your mapped alias followed by your note.\n"
    printf "  Example: \033[1msoy \"Watching a tutorial on POSIX compliance\"\033[0m\n"
    printf "\033[38;2;255;117;0m=========================================\033[0m\n"
}
