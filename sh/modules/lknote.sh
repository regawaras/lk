#!/bin/sh
# Module: lknote (LogKlerk Quick Notes - Standalone Manager & Smart Alias Generator)

lknote() {
    # --- 1. Environment & Configuration Resolution ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.4}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_TAXONOMY_FILE="${LK_CONFIG_DIR}/modules/context.sh"
    
    # Fallback jika lk.conf tidak menyediakan LK_DIR
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"

    # Sanitasi trailing slash agar tidak terjadi // (misal: .../lk//note)
    LK_DIR="${LK_DIR%/}"
    LK_NOTE_DIR="$LK_DIR/note"
    LKSET_TAIL_LINES="${LKSET_TAIL_LINES:-5}"

    # =========================================================================
    # COLOR PALETTE CONFIGURATION
    # =========================================================================
    LK_RESET=$(printf '\033[0m')
    LK_LIME=$(printf '\033[38;2;100;255;0m')        # Success Checkmark
    LK_PURPLE=$(printf '\033[38;2;170;100;255m')    # Alias Color
    LK_ORANGE=$(printf '\033[38;2;255;102;0m')      # Tag Color & Warnings
    LK_CYAN=$(printf '\033[38;2;0;255;255m')        # Target Path Color
    LK_GREY=$(printf '\033[38;2;150;150;150m')      # True Color Grey
    LK_AMBER=$(printf '\033[38;2;255;204;0m')       # Tail Header
    LK_HEADER_ORG=$(printf '\033[38;2;255;117;0m')  # Header Separator
    LK_RED=$(printf '\033[31m')                     # Strict Syntax Error Red
    # =========================================================================

    _lknote_tail_colorizer() {
        awk -v reset="$LK_RESET" -v purp="$LK_PURPLE" -v org="$LK_ORANGE" -v grey="$LK_GREY" -v cyan="$LK_CYAN" '
        {
            if (match($0, /^[a-zA-Z0-9_]+/)) {
                alias_name = substr($0, RSTART, RLENGTH)
                rest_of_line = substr($0, RLENGTH + 1)
                
                # Highlight Alias dan Path target di dalam fungsinya
                if (match(rest_of_line, /local tgt="[^"]+"/)) {
                    path_part = substr(rest_of_line, RSTART + 11, RLENGTH - 12)
                    pre_path = substr(rest_of_line, 1, RSTART + 10)
                    post_path = substr(rest_of_line, RSTART + RLENGTH)
                    print "    " purp alias_name grey pre_path cyan path_part grey post_path reset
                    next
                }
            }
            print "    " cyan $0 reset
        }'
    }

    mkdir -p "$LK_NOTE_DIR" 2>/dev/null

    # --- 2. Action Router ---
    case "$1" in
        "")
            printf "\n%s| LK (LogKlerk) --- Quick Notes Manager (lknote) Help ---%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            printf "  \033[38;2;170;100;255mlknote\033[0m \033[38;2;100;255;0mlist\033[0m                         \033[90mList all notes in LK_DIR/note/\033[0m\n"
            printf "  \033[38;2;170;100;255mlknote\033[0m \033[38;2;100;255;0mfind <keyword>\033[0m               \033[90mFilter/Search for specific notes\033[0m\n"
            printf "  \033[38;2;170;100;255mlknote\033[0m \033[38;2;0;255;255m<alias>=\"<file.md>\"\033[0m          \033[90mRegister a smart alias to a file\033[0m\n"
            printf "  \033[38;2;170;100;255mlknote\033[0m \033[38;2;0;255;255m<alias>=\"<Dir/file.md>\"\033[0m      \033[90mRegister with specific sub-directory\033[0m\n"
            printf "  \033[38;2;170;100;255mlknote\033[0m \033[38;2;170;100;255m<alias>\033[0m                      \033[90mExecute the alias directly\033[0m\n"
            printf "%s-------------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            printf "%s[Smart Alias Features after creation]:%s\n" "$LK_AMBER" "$LK_RESET"
            printf "  %s<alias>%s                              \033[90mOpen file in \$EDITOR\033[0m\n" "$LK_PURPLE" "$LK_RESET"
            printf "  %s<alias>%s \033[38;2;100;255;0m\"Your quick idea\"%s            \033[90mAppend text to file silently\033[0m\n" "$LK_PURPLE" "$LK_RESET" "$LK_RESET"
            printf "  %s<alias>%s \033[38;2;225;102;0m-v%s                           \033[90mView (cat) file contents\033[0m\n" "$LK_PURPLE" "$LK_RESET" "$LK_RESET"
            printf "\n"
            return 0
            ;;

        list|ls|-ls|--list)
            printf "\n%s| LK (LogKlerk) --- Notes Directory List ---%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            lkn_files=$(find "$LK_NOTE_DIR" -type f 2>/dev/null | sort)
            if [ -n "$lkn_files" ]; then
                echo "$lkn_files" | sed "s|^$LK_NOTE_DIR/||" | while read -r f; do
                    printf "  %s- %s%s\n" "$LK_CYAN" "$f" "$LK_RESET"
                done
            else
                printf "  %s(Empty / No notes created yet)%s\n" "$LK_GREY" "$LK_RESET"
            fi
            printf "%s--------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            return 0
            ;;

        # Penambahan Filter/Find Mode (Case-Insensitive)
        filter|find|f|-f)
            lkn_search="$2"
            if [ -z "$lkn_search" ]; then
                printf "%s[Error]%s Please provide a keyword to find. (e.g., lknote f projects)\n" "$LK_RED" "$LK_RESET"
                return 1
            fi
            
            printf "\n%s| LK (LogKlerk) --- Filtering Notes for: '%s' ---%s\n" "$LK_HEADER_ORG" "$lkn_search" "$LK_RESET"
            # Pencarian Case-Insensitive menggunakan grep -i
            lkn_files=$(find "$LK_NOTE_DIR" -type f 2>/dev/null | sort | grep -i "$lkn_search")
            if [ -n "$lkn_files" ]; then
                echo "$lkn_files" | sed "s|^$LK_NOTE_DIR/||" | while read -r f; do
                    printf "  %s- %s%s\n" "$LK_CYAN" "$f" "$LK_RESET"
                done
            else
                printf "  %s(No notes found matching '%s')%s\n" "$LK_GREY" "$lkn_search" "$LK_RESET"
            fi
            printf "%s---------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            return 0
            ;;

        *=*)
            # Validasi format dan ekstraksi (Creation Mode)
            lkn_alias="${1%%=*}"
            lkn_target_raw="${1#*=}"
            
            if echo "$lkn_alias" | grep -q '[^a-zA-Z0-9_]'; then
                printf "%s[Error]%s Invalid alias name: '%s'. Use alphanumeric and underscores only.\n" "$LK_RED" "$LK_RESET" "$lkn_alias"
                return 1
            fi

            lkn_target=$(echo "$lkn_target_raw" | sed "s/^['\"]//; s/['\"]$//")
            
            if [ -z "$lkn_target" ]; then
                printf "%s[Error]%s Target file cannot be empty.\n" "$LK_RED" "$LK_RESET"
                return 1
            fi

            if [ ! -w "$LK_TAXONOMY_FILE" ]; then
                printf "%s[Error]%s Permission denied on context.sh.\n" "$LK_RED" "$LK_RESET"
                return 1
            fi

            # Proteksi Duplikasi
            if grep -q "^${lkn_alias}[[:space:]]*()[[:space:]]*{" "$LK_TAXONOMY_FILE" 2>/dev/null; then
                printf "%s[Warning]%s %sAlias '%s' is already registered in context.sh. Aborting.%s\n" "$LK_ORANGE" "$LK_RESET" "$LK_RED" "$lkn_alias" "$LK_RESET"
                return 0
            fi

            # Generator Smart Function
            lkn_func="${lkn_alias}() { local tgt=\"${LK_NOTE_DIR}/${lkn_target}\"; mkdir -p \"\${tgt%/*}\" 2>/dev/null; [ ! -f \"\$tgt\" ] && touch \"\$tgt\"; if [ \$# -eq 0 ]; then \${EDITOR:-vi} \"\$tgt\"; elif [ \"\$1\" = \"-v\" ] || [ \"\$1\" = \"view\" ]; then cat \"\$tgt\"; else printf -- \"- %s\\\\n\" \"\$*\" >> \"\$tgt\"; printf \"\\\\033[38;2;100;255;0m✔\\\\033[0m Note appended to \\\\033[38;2;0;255;255m${lkn_target}\\\\033[0m\\\\n\"; fi; }"

            printf "%s\n" "$lkn_func" >> "$LK_TAXONOMY_FILE"

            printf "%s✔%s Smart Note Alias Created\n" "$LK_LIME" "$LK_RESET"
            printf "    Alias    : %s%s%s\n" "$LK_PURPLE" "$lkn_alias" "$LK_RESET"
            printf "    Target   : %s%s%s\n" "$LK_CYAN" "$lkn_target" "$LK_RESET"
            printf "    Location : %s%s%s\n" "$LK_GREY" "$LK_NOTE_DIR/$lkn_target" "$LK_RESET"
            
            printf "\n%s--- Tail: Last %s lines from context.sh ---%s\n" "$LK_AMBER" "$LKSET_TAIL_LINES" "$LK_RESET"
            tail -n "$LKSET_TAIL_LINES" "$LK_TAXONOMY_FILE" | _lknote_tail_colorizer
            printf "%s------------------------------------------------%s\n" "$LK_HEADER_ORG" "$LK_RESET"
            return 0
            ;;

        *)
            # Smart Execution / Fallback Mode
            lkn_try_alias="$1"
            shift
            
            # Cek apakah alias sudah terdaftar sebagai fungsi di memori shell
            if command -v "$lkn_try_alias" >/dev/null 2>&1 || type "$lkn_try_alias" >/dev/null 2>&1; then
                # Eksekusi fungsi tersebut dengan argumen sisanya
                eval "$lkn_try_alias" "$@"
                return $?
            fi
            
            # Jika belum ada
            printf "%s[Context Not Found]%s The alias '%s' does not exist.\n" "$LK_ORANGE" "$LK_RESET" "$lkn_try_alias"
            printf "%s[Tutorial]%s Make it by typing:\n" "$LK_LIME" "$LK_RESET"
            printf "  \033[38;2;170;100;255mlknote\033[0m %s=\"%s.md\"\n" "$lkn_try_alias" "$lkn_try_alias"
            printf "  \033[90m(or with specific directory)\033[0m\n"
            printf "  \033[38;2;170;100;255mlknote\033[0m %s=\"dir/subdir/%s.md\"\n" "$lkn_try_alias" "$lkn_try_alias"
            return 1
            ;;
    esac
}
