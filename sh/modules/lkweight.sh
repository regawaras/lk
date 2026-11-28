#!/bin/sh
# Module: lkweight (Axiological Tracker & Karmic Judgment Engine)
# Version: v0.0.6 (Dynamic Axis Shifting Chart & Full Spectrum Grading)
# POSIX Strict Version (Dash & TTY TrueColor Compatible)

lkweight() {
    # --- 1. Environment & Configuration ---
    LK_STATUS="${LK_STATUS:-experimental}"
    LK_VERSION="${LK_VERSION:-v0.0.6}"
    LK_CONFIG_DIR="${HOME}/.config/lk/${LK_STATUS}/${LK_VERSION}"
    LK_CONFIG_FILE="${LK_CONFIG_DIR}/lk.conf"
    LK_WEIGHT_FILE="${LK_CONFIG_DIR}/weights.list"
    
    LK_DIR="${HOME}/.local/share/logklerk"
    [ -f "$LK_CONFIG_FILE" ] && . "$LK_CONFIG_FILE"
    LK_DIR="${LK_DIR%/}"

    mkdir -p "$LK_CONFIG_DIR" 2>/dev/null
    touch "$LK_WEIGHT_FILE" 2>/dev/null

    # =========================================================================
    # TRUECOLOR FULL SPECTRUM GRADIENT
    # =========================================================================
    LK_RESET='\033[0m'
    LK_MERAHTUA='\033[38;2;170;0;0m'    # <= -5000 (Catastrophic)
    LK_MERAH='\033[38;2;255;50;50m'     # > -5000 (Void Exposure)
    LK_KUNING='\033[38;2;255;200;0m'    # > -1000 (Friction)
    LK_GREY='\033[38;5;245m'            # 0 (Neutral)
    LK_HIJAU='\033[38;2;100;255;0m'     # > 0 (Net Positive)
    LK_BIRU='\033[38;2;0;200;255m'      # >= 1000 (Highly Productive)
    LK_BIRUTUA='\033[38;2;100;100;255m' # >= 5000 (Ascended / God-Tier)
    
    LK_WHITE='\033[37m'
    LK_CYAN='\033[36m'
    LK_MAGENTA='\033[35m'
    LK_AMBER='\033[38;2;255;200;0m'
    LK_ORANGE='\033[38;2;225;102;0m'
    LK_DIM='\033[2m'
    # =========================================================================

    # --- INTERNAL ENGINE ---
    _lkweight_calc() {
        find "$LK_DIR" -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" 2>/dev/null | \
        LC_ALL=C awk -v w_file="$LK_WEIGHT_FILE" '
        BEGIN {
            w_count = 0
            while ((getline line < w_file) > 0) {
                if (line ~ /\|/) {
                    split(line, a, "|")
                    weights[++w_count] = a[1] + 0
                    patterns[w_count] = tolower(a[2])
                }
            }
            close(w_file)
        }
        {
            file = $0
            n = split(file, parts, "/")
            date_str = substr(parts[n], 1, 10)
            score = 0
            summary = ""
            
            while ((getline l < file) > 0) {
                if (summary == "" && l ~ /^-[[:space:]]*#?[[:space:]]*\[\[[0-9]{4}(-[0-9]{2}){0,2}\]\]/) {
                    summary = l
                    sub(/^[[:space:]]*-[[:space:]]*#?[[:space:]]*\[\[[^\]]+\]\][[:space:]]*[-:]?[[:space:]]*/, "", summary)
                }

                l_low = tolower(l)
                for(i=1; i<=w_count; i++) {
                    pat = patterns[i]
                    pat_len = length(pat)
                    tmp_l = l_low
                    count = 0
                    while ((idx = index(tmp_l, pat)) > 0) {
                        count++
                        tmp_l = substr(tmp_l, idx + pat_len)
                    }
                    if (count > 0) {
                        score += (weights[i] * count)
                    }
                }
            }
            close(file)
            if (summary == "") summary = "[Summary Not Found/Not Yet Summarized]"
            sub(/[[:space:]]+$/, "", summary)
            
            print score "|" date_str "|" summary
        }'
    }

    cmd="$1"
    shift

    case "$cmd" in
        add)
            if echo "$1" | grep -q "="; then
                weight="${1%%=*}"
                pattern="${1#*=}"
            else
                weight="$1"
                pattern="$2"
            fi
            
            pattern=$(echo "$pattern" | sed 's/^"//;s/"$//')

            if ! echo "$weight" | grep -Eq '^-?[0-9]+$'; then
                printf "%b[Error]%b Weight must be an integer.\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi
            if [ -z "$pattern" ]; then
                printf "%b[Error]%b Pattern cannot be empty.\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi

            echo "${weight}|${pattern}" >> "$LK_WEIGHT_FILE"
            col="$LK_HIJAU"; [ "$weight" -lt 0 ] && col="$LK_MERAH"
            printf "%b[Added]%b %s%s%b -> %b%s%b\n" "$LK_BIRU" "$LK_RESET" "$col" "$weight" "$LK_RESET" "$LK_KUNING" "$pattern" "$LK_RESET"
            printf "%bSaved to: %s%b\n" "$LK_GREY" "$LK_WEIGHT_FILE" "$LK_RESET"
            ;;
            
        list)
            printf "%b--- Karmic Rules (Weight Contexts) ---%b\n" "$LK_BIRUTUA" "$LK_RESET"
            if [ ! -s "$LK_WEIGHT_FILE" ]; then
                printf "  %bNo rules defined.%b\n" "$LK_WHITE" "$LK_RESET"
            else
                cat -n "$LK_WEIGHT_FILE" | awk -F'|' -v c_hijau="$LK_HIJAU" -v c_merah="$LK_MERAH" '{
                    split($1, num_weight, " ")
                    idx = num_weight[1]; weight = num_weight[2]
                    pattern = $2
                    col = (weight < 0) ? c_merah : c_hijau
                    printf "  \033[36m[%s]\033[0m %s%6s\033[0m -> \033[33m%s\033[0m\n", idx, col, weight, pattern
                }'
            fi
            printf "%bConfig Path: %s%b\n" "$LK_GREY" "$LK_WEIGHT_FILE" "$LK_RESET"
            ;;
            
        rm|remove)
            if [ -z "$1" ]; then
                printf "%b[Error]%b Provide line number to remove.\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi
            sed "${1}d" "$LK_WEIGHT_FILE" > "${LK_WEIGHT_FILE}.tmp" && mv "${LK_WEIGHT_FILE}.tmp" "$LK_WEIGHT_FILE"
            printf "%b[Removed]%b Rule at line %s deleted.\n" "$LK_KUNING" "$LK_RESET" "$1"
            ;;

        why)
            target_date="$1"
            if [ -z "$target_date" ]; then
                printf "%b[Error]%b Provide a date (e.g., 'lkweight why 2026-05-14' or 'today').\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi
            if [ "$target_date" = "today" ]; then target_date=$(date +%Y-%m-%d); fi

            y="${target_date%%-*}"
            m="${target_date%-*}"
            target_file="$LK_DIR/$y/$m/${target_date}.md"

            if [ ! -f "$target_file" ]; then
                printf "%b[LK Axiom]%b Log for [[%s]] not found in Vault.\n" "$LK_KUNING" "$LK_RESET" "$target_date"
                return 0
            fi

            printf "%b--- Performing Karmic Autopsy for [[%s]]... ---%b\r" "$LK_BIRU" "$target_date" "$LK_RESET"

            LC_ALL=C awk -v w_file="$LK_WEIGHT_FILE" -v date_str="$target_date" \
                -v r="$LK_RESET" -v mt="$LK_MERAHTUA" -v me="$LK_MERAH" -v k="$LK_KUNING" \
                -v h="$LK_HIJAU" -v b="$LK_BIRU" -v bt="$LK_BIRUTUA" -v g="$LK_GREY" '
            BEGIN {
                w_count = 0
                while ((getline line < w_file) > 0) {
                    if (line ~ /\|/) {
                        split(line, a, "|")
                        weights[++w_count] = a[1] + 0
                        patterns[w_count] = tolower(a[2])
                        orig_patterns[w_count] = a[2]
                    }
                }
                close(w_file)
                total_score = 0
            }
            {
                l_low = tolower($0)
                for(i=1; i<=w_count; i++) {
                    pat = patterns[i]; pat_len = length(pat); tmp_l = l_low; count = 0
                    while ((idx = index(tmp_l, pat)) > 0) {
                        count++; tmp_l = substr(tmp_l, idx + pat_len)
                    }
                    if (count > 0) hits[i] += count
                }
            }
            END {
                pos_count = 0; neg_count = 0
                for(i=1; i<=w_count; i++) {
                    if (hits[i] > 0) {
                        subtotal = hits[i] * weights[i]
                        total_score += subtotal
                        if (weights[i] > 0) {
                            pos_count++
                            pos_vals[pos_count] = subtotal
                            pos_lines[pos_count] = sprintf("  %s+%s %4dx %s%-30s%s %s(@ +%-4d)%s -> %s+%d%s", h, r, hits[i], b, "\"" orig_patterns[i] "\"", r, g, weights[i], r, h, subtotal, r)
                        } else {
                            neg_count++
                            neg_vals[neg_count] = subtotal
                            neg_lines[neg_count] = sprintf("  %s-%s %4dx %s%-30s%s %s(@ %-5d)%s -> %s%d%s", me, r, hits[i], k, "\"" orig_patterns[i] "\"", r, g, weights[i], r, me, subtotal, r)
                        }
                    }
                }

                for (i=1; i<=pos_count; i++) {
                    for (j=i+1; j<=pos_count; j++) {
                        if (pos_vals[i] > pos_vals[j]) {
                            tmp_val = pos_vals[i]; pos_vals[i] = pos_vals[j]; pos_vals[j] = tmp_val
                            tmp_str = pos_lines[i]; pos_lines[i] = pos_lines[j]; pos_lines[j] = tmp_str
                        }
                    }
                }

                for (i=1; i<=neg_count; i++) {
                    for (j=i+1; j<=neg_count; j++) {
                        abs_i = (neg_vals[i] < 0) ? -neg_vals[i] : neg_vals[i]
                        abs_j = (neg_vals[j] < 0) ? -neg_vals[j] : neg_vals[j]
                        if (abs_i > abs_j) {
                            tmp_val = neg_vals[i]; neg_vals[i] = neg_vals[j]; neg_vals[j] = tmp_val
                            tmp_str = neg_lines[i]; neg_lines[i] = neg_lines[j]; neg_lines[j] = tmp_str
                        }
                    }
                }

                printf "\033[2K\r"
                print bt "| LK (LogKlerk) --- Karmic Autopsy : [[" date_str "]] ---" r

                if (pos_count > 0) {
                    print "\n  " b "[ Ascending Catalysts (Positives) ]" r
                    for(i=1; i<=pos_count; i++) print pos_lines[i]
                }
                if (neg_count > 0) {
                    print "\n  " me "[ Void Pullers (Negatives) ]" r
                    for(i=1; i<=neg_count; i++) print neg_lines[i]
                }
                if (pos_count == 0 && neg_count == 0) print "\n  " g "(No karmic weights detected. Absolute Neutral Day.)" r

                if (total_score >= 5000) { tier="Ascended / God-Tier"; col=bt; sign="+" }
                else if (total_score >= 1000) { tier="Highly Productive"; col=b; sign="+" }
                else if (total_score > 0) { tier="Net Positive"; col=h; sign="+" }
                else if (total_score == 0) { tier="Absolute Neutral"; col=g; sign="" }
                else if (total_score > -1000) { tier="Friction / Distracted"; col=k; sign="" }
                else if (total_score > -5000) { tier="Void Exposure"; col=me; sign="" }
                else { tier="Catastrophic Hijack"; col=mt; sign="" }

                print "\n" g "----------------------------------------------------------------" r
                printf "  Net Karmic Resonance: %s%s%d%s %s(%s)%s\n", col, sign, total_score, r, g, tier, r
                print g "----------------------------------------------------------------" r
            }' "$target_file"
            ;;
            
        judge)
            if [ ! -s "$LK_WEIGHT_FILE" ]; then
                printf "%b[Error]%b Weight list is empty.\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi

            sub_cmd="$1"

            if [ "$sub_cmd" = "today" ]; then
                TODAY=$(date +%Y-%m-%d)
                printf "%b--- Scanning Karmic Resonance for Today (%s)... ---%b\r" "$LK_BIRU" "$TODAY" "$LK_RESET"
                
                result=$(_lkweight_calc | grep "|$TODAY|")
                if [ -z "$result" ]; then
                    printf "\033[2K\r%b[LK Axiom]%b No log found for today yet.\n" "$LK_KUNING" "$LK_RESET"
                    return 0
                fi
                
                score=$(echo "$result" | cut -d'|' -f1)
                summary=$(echo "$result" | cut -d'|' -f3-)
                
                if [ "$score" -ge 5000 ]; then tier="Ascended / God-Tier"; col="$LK_BIRUTUA"; sign="+"
                elif [ "$score" -ge 1000 ]; then tier="Highly Productive"; col="$LK_BIRU"; sign="+"
                elif [ "$score" -gt 0 ]; then tier="Net Positive"; col="$LK_HIJAU"; sign="+"
                elif [ "$score" -eq 0 ]; then tier="Absolute Neutral"; col="$LK_GREY"; sign=""
                elif [ "$score" -gt -1000 ]; then tier="Friction / Distracted"; col="$LK_KUNING"; sign=""
                elif [ "$score" -gt -5000 ]; then tier="Void Exposure"; col="$LK_MERAH"; sign=""
                else tier="Catastrophic Hijack"; col="$LK_MERAHTUA"; sign=""; fi

                summary_tag=$(echo "$summary" | grep -o '^!\[[^]]*\]!')
                if [ -n "$summary_tag" ]; then
                    summary_rest=$(echo "$summary" | sed "s/^$summary_tag[[:space:]]*//")
                    summary_colored="${LK_ORANGE}${summary_tag}${LK_RESET} ${LK_GREY}${summary_rest}${LK_RESET}"
                else
                    summary_colored="${LK_GREY}${summary}${LK_RESET}"
                fi

                printf "\033[2K\r"
                printf "%b| LK (LogKlerk) --- Today's Axiological Audit ---%b\n" "$LK_BIRU" "$LK_RESET"
                printf "  Date     : %b[[%s]]%b\n" "$LK_AMBER" "$TODAY" "$LK_RESET"
                printf "  Summary  : %s\n" "$summary_colored"
                printf "  Karmic   : %s%s%s%b (%s)%b\n" "$col" "$sign" "$score" "$LK_RESET" "$tier" "$LK_RESET"
                printf "%b---------------------------------------------------%b\n" "$LK_GREY" "$LK_RESET"
                return 0

            elif [ "$sub_cmd" = "date" ]; then
                printf "%b--- Rendering Axiological Chronology Matrix... ---%b\r" "$LK_BIRU" "$LK_RESET"
                
                _lkweight_calc | sort -t'|' -k2 | awk -F'|' \
                -v r="$LK_RESET" -v mt="$LK_MERAHTUA" -v me="$LK_MERAH" -v k="$LK_KUNING" \
                -v h="$LK_HIJAU" -v b="$LK_BIRU" -v bt="$LK_BIRUTUA" -v g="$LK_GREY" -v o="$LK_ORANGE" -v a="$LK_AMBER" '
                BEGIN {
                    printf "\033[2K\r"
                    print bt "| LK (LogKlerk) --- Axiological Chronology Matrix ---" r
                    max_pos = 0
                    min_neg = 0
                }
                {
                    scores[NR] = $1 + 0
                    dates[NR] = $2
                    
                    sm = $3
                    for (x=4; x<=NF; x++) sm = sm "|" $x
                    summaries[NR] = sm
                    
                    if (scores[NR] > max_pos) max_pos = scores[NR]
                    if (scores[NR] < min_neg) min_neg = scores[NR]
                }
                END {
                    # --- DYNAMIC AXIS SHIFTING MATH ---
                    abs_neg = (min_neg < 0) ? -min_neg : 0
                    total_range = abs_neg + max_pos
                    TOTAL_BARS = 20
                    
                    if (total_range == 0) {
                        left_space = 10; right_space = 10
                    } else {
                        left_space = int((abs_neg / total_range) * TOTAL_BARS + 0.5)
                        right_space = TOTAL_BARS - left_space
                        
                        # Fix Edge Cases (Mencegah kolom hilang sepenuhnya jika masih ada nilai terkecil)
                        if (abs_neg > 0 && left_space == 0) { left_space = 1; right_space = TOTAL_BARS - 1 }
                        if (max_pos > 0 && right_space == 0) { right_space = 1; left_space = TOTAL_BARS - 1 }
                    }
                    
                    for (i=1; i<=NR; i++) {
                        sc = scores[i]
                        dt = dates[i]
                        summary = summaries[i]
                        
                        # --- FULL SPECTRUM GRADING ---
                        if (sc >= 5000) col = bt
                        else if (sc >= 1000) col = b
                        else if (sc > 0) col = h
                        else if (sc == 0) col = g
                        else if (sc > -1000) col = k
                        else if (sc > -5000) col = me
                        else col = mt
                        
                        left_side = ""
                        right_side = ""
                        
                        if (sc < 0) {
                            abs_sc = -sc
                            bar_len = int((abs_sc / abs_neg) * left_space + 0.5)
                            if (bar_len == 0 && abs_sc > 0) bar_len = 1
                            
                            for(x=1; x<=left_space; x++) {
                                if (x <= (left_space - bar_len)) left_side = left_side "·"
                                else left_side = left_side "■"
                            }
                            left_side = col left_side r
                            for(x=1; x<=right_space; x++) right_side = right_side "·"
                            right_side = g right_side r
                            sign = ""
                        } else if (sc > 0) {
                            for(x=1; x<=left_space; x++) left_side = left_side "·"
                            left_side = g left_side r
                            
                            bar_len = int((sc / max_pos) * right_space + 0.5)
                            if (bar_len == 0 && sc > 0) bar_len = 1
                            
                            for(x=1; x<=right_space; x++) {
                                if (x <= bar_len) right_side = right_side "■"
                                else right_side = right_side "·"
                            }
                            right_side = col right_side r
                            sign = "+"
                        } else {
                            for(x=1; x<=left_space; x++) left_side = left_side "·"
                            left_side = g left_side r
                            for(x=1; x<=right_space; x++) right_side = right_side "·"
                            right_side = g right_side r
                            sign = " "
                        }
                        
                        max_len = 38; txt_color = g; tag_str = ""; tag_color = o; rest_str = summary; colored_sum = ""

                        if (summary ~ /^\[Anomaly/ || summary ~ /^\[Empty/ || summary ~ /^\(Empty/ || summary ~ /^\[Summary Not Found/) {
                            txt_color = me; colored_sum = txt_color summary r; raw_len = length(summary)
                        } else {
                            if (match(summary, /^!\[[^\]]+\]!/)) {
                                tag_str = substr(summary, RSTART, RLENGTH); rest_str = substr(summary, RLENGTH + 1)
                                sub(/^[[:space:]]+/, "", rest_str)
                                if (tag_str == "![PLAN]!") tag_color = bt
                            }

                            raw_len = length(tag_str) + (tag_str != "" ? 1 : 0) + length(rest_str)
                            if (tag_str == "") raw_len = length(rest_str)

                            if (raw_len > max_len) {
                                avail_len = max_len - length(tag_str) - (tag_str != "" ? 1 : 0)
                                if (avail_len < 3) {
                                    raw_txt = substr((tag_str != "" ? tag_str " " rest_str : rest_str), 1, max_len - 3) "..."
                                    tag_str = ""; rest_str = raw_txt; colored_sum = txt_color raw_txt r; raw_len = length(raw_txt)
                                } else { rest_str = substr(rest_str, 1, avail_len - 3) "..."; raw_len = max_len }
                            }
                            if (tag_str != "") colored_sum = tag_color tag_str r " " txt_color rest_str r
                            else if (colored_sum == "") colored_sum = txt_color rest_str r
                        }

                        pad_spaces = ""
                        if (raw_len < max_len) { for (p = 0; p < (max_len - raw_len); p++) pad_spaces = pad_spaces " " }
                        
                        printf "%s%s%s %s%s │ %s│%s │ %s%s%-6d%s\n", a, dt, r, colored_sum, pad_spaces, left_side, right_side, col, sign, sc, r
                    }
                }'
                return 0
            fi

            # --- Default Juxtaposition Logic ---
            if [ "$sub_cmd" = "all" ]; then limit=999999
            else limit="${1:-15}"; fi

            printf "%b--- Rendering Axiological Juxtaposition... ---%b\r" "$LK_BIRU" "$LK_RESET"

            raw_scores=$(_lkweight_calc)
            best_days=$(echo "$raw_scores" | LC_ALL=C awk -F'|' '$1 > 0' | sort -t'|' -k1 -nr | head -n "$limit")
            worst_days=$(echo "$raw_scores" | LC_ALL=C awk -F'|' '$1 < 0' | sort -t'|' -k1 -n | head -n "$limit")

            LC_ALL=C awk -v best="$best_days" -v worst="$worst_days" -v lim="$limit" \
                -v r="$LK_RESET" -v mt="$LK_MERAHTUA" -v me="$LK_MERAH" -v k="$LK_KUNING" \
                -v h="$LK_HIJAU" -v b="$LK_BIRU" -v bt="$LK_BIRUTUA" -v g="$LK_GREY" '
            BEGIN {
                bn = split(best, b_arr, "\n")
                for (i=1; i<=bn; i++) {
                    if (b_arr[i] != "") {
                        split(b_arr[i], temp, "|")
                        b_scores[i] = temp[1]; b_dates[i] = temp[2]
                    }
                }
                
                wn = split(worst, w_arr, "\n")
                for (i=1; i<=wn; i++) {
                    if (w_arr[i] != "") {
                        split(w_arr[i], temp, "|")
                        w_scores[i] = temp[1]; w_dates[i] = temp[2]
                    }
                }

                header_lbl = (lim >= 999999) ? "(ALL RECORDED DAYS)" : "(TOP " lim " DAYS)"
                printf "\033[2K\r"
                print bt "  [ ASCENDED DAYS " header_lbl " ]  " g "||" mt "  [ CATASTROPHIC DAYS " header_lbl " ]" r
                print g "--------------------------------------------------------------------------------------" r
                
                max_lines = (bn > wn) ? bn : wn
                if (lim < max_lines) max_lines = lim
                
                for (i=1; i<=max_lines; i++) {
                    if (b_dates[i] != "") {
                        sc = b_scores[i] + 0; dt = b_dates[i]
                        left_sign = (sc > 0) ? "+" : ""
                        left_col = (sc >= 5000) ? bt : ((sc >= 1000) ? b : h)
                        left_str = sprintf("%s%4d.%s [[%s]] %s%s%-6d%s", g, i, r, dt, left_col, left_sign, sc, r)
                    } else { left_str = sprintf("%44s", "") }
                    
                    if (w_dates[i] != "") {
                        sc = w_scores[i] + 0; dt = w_dates[i]
                        right_col = (sc <= -5000) ? mt : ((sc <= -1000) ? me : k)
                        right_str = sprintf("%s%4d.%s [[%s]] %s%-6d%s", g, i, r, dt, right_col, sc, r)
                    } else { right_str = "" }
                    
                    printf "%-57s %s||%s %s\n", left_str, g, r, right_str
                }
                print g "--------------------------------------------------------------------------------------" r
            }'
            ;;

        unjudged)
            if [ ! -s "$LK_WEIGHT_FILE" ]; then
                printf "%b[Error]%b Weight list is empty.\n" "$LK_MERAH" "$LK_RESET"
                return 1
            fi
            printf "%b--- Scanning for Unjudged (Neutral/Void) Days... ---%b\r" "$LK_BIRU" "$LK_RESET"
            _lkweight_calc | LC_ALL=C awk -F'|' '$1 == 0 {print $2}' | sort | LC_ALL=C awk -v r="$LK_RESET" -v b="$LK_BIRU" -v g="$LK_GREY" '
            BEGIN { printf "\033[2K\r"; print b "| LK (LogKlerk) --- Unjudged / Karmic Neutral Days ---" r; print ""; count=0 }
            { if ($1 != "") { printf "  %s[%4d]%s [[%s]] %s(No karmic weight detected)%s\n", g, ++count, r, $1, g, r } }
            END { print "\n  Total Unjudged Days: " b count r; print "\n" g "------------------------------------------------------------" r }'
            ;;
            
        *)
            printf "%bUsage:%b lkweight {add|list|rm|judge|why|unjudged} [args]\n" "$LK_KUNING" "$LK_RESET"
            printf "  lkweight add 5000 \"Sparlaverse\"\n"
            printf "  lkweight judge       %b(Shows Juxtaposition of Top/Bottom 15 days)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkweight judge 30    %b(Shows Juxtaposition of Top/Bottom 30 days)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkweight judge date  %b(Renders Dynamic Axis Shifting Chart)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkweight why <date>  %b(Executes a Karmic Autopsy sorted by weight total)%b\n" "$LK_DIM" "$LK_RESET"
            printf "  lkweight unjudged    %b(Lists all days with a score of exactly 0)%b\n" "$LK_DIM" "$LK_RESET"
            ;;
    esac
}
