# =====================================================================
#  LogKlerk Assembly CSV Version  v0.0.3
#  x86-64 Linux | GNU as (Intel syntax) | no libc, pure syscalls
#
#  Layout
#    src/main.asm          core: config, logging, shell, lkset, REPL
#    src/modules/lkc.asm   lkc log reader (pulled in with .include)
#
#  Build (from the repository root)
#           as --64 -g -I src src/main.asm -o lk.o
#           ld -z noexecstack -z relro -z now -o lk lk.o
#
#  Changes from v0.0.2
#    - main.s -> main.asm; lkc moved out of main into src/modules/lkc.asm
#    - All code comments are now in English
#    - Timestamps are fully ISO 8601 basic format YYYYMMDDThhmmss (LOCAL time);
#      the unusable .SSS milliseconds suffix was removed
#    - context and activity are always written as quoted CSV strings:
#          YYYYMMDDThhmmss,lktags,"lkcontext","log activity"
#    - Times are LOCAL time (zone from $TZ or /etc/localtime, TZif parsed
#      without libc; falls back to UTC if no zone file is readable)
#    - Default grey is a lighter grey (256-color 250)
#    - lkc defaults to the current (local) day; "lkc all" lists every file
#    - Default colors: orange date, yellow tags, purple context, grey activity
#    - LK_NAME_FORMAT also accepts "hh" as the hour token (ISO notation)
#    - Fix: entering/leaving taxonomy mode is logged as  lk,"lktags"
#      (was  lktags,"")
#    - Fix: the first word is optional as a command. A line whose first word
#      is not a command is only logged as a note (tags "none", empty context)
#      and is never run, so no more "command not found" noise
#    - Fix: Linux commands, aliases and functions from ~/.bashrc and
#      ~/.profile work in basic mode AND in taxonomy (context) mode
#
#  INTERNAL REGISTER CONVENTION (same as System V AMD64)
#    arguments    : rdi, rsi, rdx, rcx, r8, r9
#    return       : rax
#    callee-saved : rbx, rbp, r12-r15  (a function that uses them MUST push/pop)
#    caller-saved : rax, rcx, rdx, rsi, rdi, r8-r11 (a function may clobber them)
#    `syscall` clobbers: rax (return), rcx, r11. The kernel preserves the rest.
#    Every function lists its "CLOBBER" = caller-saved registers it destroys.
#
#  Stack: no recursion, no arrays on the stack. All buffers live in .bss with
#  fixed sizes, and every write is checked against its limit.
# =====================================================================
        .intel_syntax noprefix

# ---------- Linux x86-64 syscall numbers ----------
        .equ SYS_read,          0
        .equ SYS_write,         1
        .equ SYS_open,          2
        .equ SYS_close,         3
        .equ SYS_lseek,         8
        .equ SYS_ioctl,         16
        .equ SYS_fork,          57
        .equ SYS_execve,        59
        .equ SYS_exit,          60
        .equ SYS_wait4,         61
        .equ SYS_chdir,         80
        .equ SYS_rename,        82
        .equ SYS_mkdir,         83
        .equ SYS_unlink,        87
        .equ SYS_getdents64,    217
        .equ SYS_clock_gettime, 228
        .equ SYS_dup2,          33
        .equ SYS_pipe2,         293

# ---------- open() flags ----------
        .equ O_RDONLY,    0x0
        .equ O_WRONLY,    0x1
        .equ O_CREAT,     0x40
        .equ O_EXCL,      0x80
        .equ O_APPEND,    0x400
        .equ O_DIRECTORY, 0x10000
        .equ O_NOFOLLOW,  0x20000
        .equ O_CLOEXEC,   0x80000
        .equ EEXIST_NEG,  -17
        .equ EINTR_NEG,   -4

# ---------- buffer limits ----------
        .equ LINEMAX,   2047        # one interactive input line
        .equ ACTMAX,    2047        # activity from argv
        .equ ENTRYMAX,  8192        # one CSV line
        .equ PATHMAX,   4096
        .equ PATH_RESERVE, 160      # room left for the file name after DIR
        .equ CONFMAX,   16383
        .equ NEWMAX,    17408       # new config (CONFMAX + room for one entry)
        .equ INBUF_SZ,  4096
        .equ OUTSZ,     65536
        .equ TAILWIN,   65536
        .equ TZMAX,     16384       # max size of a TZif zone file
        .equ TAX_MAX,   32

# =====================================================================
        .section .rodata
default_conf:
        .ascii "[settings]\n"
        .ascii "LK_DIR=\"$HOME/.local/share/logklerk/\"\n"
        .ascii "LK_NAME_FORMAT=\"YYYYMMDD\"\n"
        .ascii "LK_DEFAULT_FORMAT=\".csv\"\n"
        .ascii "LK_TAIL_LINES=\"3\"\n"
        .ascii "LKSET_TAIL_LINES=\"3\"\n"
        .ascii "[taxonomy]\n"
        .ascii "gg=\"Googling\"\n"
        .ascii "gam=\"Google AI Mode\"\n"
        .ascii "claude=\"Claude\"\n"
        .ascii "soy=\"Search on Youtube\"\n"
        .ascii "diary=\"Diary\"\n"
        .asciz "com=\"Commentary\"\n"

s_home_eq:      .asciz "HOME="
s_nocolor_eq:   .asciz "NO_COLOR="
s_homevar:      .asciz "$HOME"
s_conf_suffix:  .asciz "/.config/logklerk/lk.conf"
s_tmp_ext:      .asciz ".tmp"
s_default_dir:  .asciz "$HOME/.local/share/logklerk/"
s_def_namefmt:  .asciz "YYYYMMDD"
s_def_ext:      .asciz ".csv"
s_sec_settings: .asciz "[settings]"
s_sec_taxonomy: .asciz "[taxonomy]"
s_taxhdr_nl:    .ascii "[taxonomy]\n"
        .equ s_taxhdr_nl_len, . - s_taxhdr_nl
s_nl:           .ascii "\n"

s_k_dir:        .asciz "LK_DIR"
s_k_namefmt:    .asciz "LK_NAME_FORMAT"
s_k_defext:     .asciz "LK_DEFAULT_FORMAT"
s_k_tail:       .asciz "LK_TAIL_LINES"
s_k_lksettail:  .asciz "LKSET_TAIL_LINES"
s_k_cdate:      .asciz "LK_COLOR_DATE"
s_k_ctags:      .asciz "LK_COLOR_TAGS"
s_k_cctx:       .asciz "LK_COLOR_CONTEXT"
s_k_cact:       .asciz "LK_COLOR_ACTIVITY"

s_lk:           .asciz "lk"
s_lkc:          .asciz "lkc"
s_lkset:        .asciz "lkset"
s_cd:           .asciz "cd"
s_exit:         .asciz "exit"
s_quit:         .asciz "quit"
s_taxonomy:     .asciz "taxonomy"
s_commands:     .asciz "commands"
s_lktags:       .asciz "lktags"
s_none:         .asciz "none"
s_bash:         .asciz "bash"
s_empty:        .asciz ""
s_opt_h:        .asciz "-h"
s_opt_help:     .asciz "--help"
s_bin_sh:       .asciz "/bin/sh"
s_sh_name:      .asciz "sh"
s_dash_c:       .asciz "-c"
s_exec_arg:     .asciz "exec \"$@\""
s_tz_eq:        .asciz "TZ="
s_zoneinfo:     .asciz "/usr/share/zoneinfo/"
s_localtime:    .asciz "/etc/localtime"
s_bash_path:    .asciz "/bin/bash"
s_bash_name:    .asciz "bash"
s_dash_i:       .asciz "-i"
# Probe script run as:  bash [-i] -c <script> lk <line>   (fd 3 = pipe to lk)
# It reports on fd 3 whether the FIRST WORD of the line is a command, alias,
# function, builtin or keyword ("1") or plain text ("0"). Only for "1" does it
# then run the whole line, so plain text never produces "command not found".
s_probe_script:
        .ascii "[ -r \"$HOME/.profile\" ] && . \"$HOME/.profile\" >/dev/null 2>&1\n"
        .ascii "unset HISTFILE\n"
        .ascii "w=${1%%[[:space:]|&;<>()]*}\n"
        .ascii "case $w in\n"
        .ascii "\"\") ok=1;;\n"
        .ascii "*=*) ok=1;;\n"
        .ascii "\"~\"/*) type -- \"$HOME${w#\\~}\" >/dev/null 2>&1 && ok=1 || ok=0;;\n"
        .ascii "*) type -- \"$w\" >/dev/null 2>&1 && ok=1 || ok=0;;\n"
        .ascii "esac\n"
        .ascii "echo $ok >&3\n"
        .ascii "exec 3>&-\n"
        .asciz "[ \"$ok\" = 1 ] && eval \"$1\"\n"
# words that may not be used as taxonomy keys (cstr list, ends with an empty string)
s_reserved:     .asciz "lk"
                .asciz "lkc"
                .asciz "lkset"
                .asciz "cd"
                .asciz "exit"
                .asciz "quit"
                .asciz ""

s_header:       .ascii "date,tags,context,activity\n"
        .equ s_header_len, . - s_header
s_prompt:       .asciz "lk> "
s_pm1:          .asciz "lk [["
s_pm2:          .asciz "]] > "
s_pfx_new:      .asciz "[>] "
s_pfx_old:      .asciz "    "
s_loggedinto:   .asciz "[>] logged into "
s_taxblock:     .asciz "[!] [taxonomy]\n"
s_eqq:          .ascii "=\""
s_qnl:          .ascii "\"\n"
s_reset:        .asciz "\033[0m"

# ---- color name -> SGR code ----
cn_grey:        .asciz "grey"
cn_red:         .asciz "red"
cn_green:       .asciz "green"
cn_yellow:      .asciz "yellow"
cn_blue:        .asciz "blue"
cn_magenta:     .asciz "magenta"
cn_cyan:        .asciz "cyan"
cn_white:       .asciz "white"
sg_grey:        .asciz "\033[38;5;250m"       # light grey (not white)
sg_red:         .asciz "\033[31m"
sg_green:       .asciz "\033[32m"
sg_yellow:      .asciz "\033[33m"
sg_blue:        .asciz "\033[34m"
sg_magenta:     .asciz "\033[35m"
sg_cyan:        .asciz "\033[36m"
sg_white:       .asciz "\033[37m"
cn_orange:      .asciz "orange"
cn_purple:      .asciz "purple"
sg_orange:      .asciz "\033[38;5;208m"
sg_purple:      .asciz "\033[38;5;135m"

# ---- LK_NAME_FORMAT token table: 4-byte token, len, offset in tsbuf, copy count, pad ----
fn_tab:
        .ascii "YYYY"
        .byte 4,0,4,0
        .ascii "MM\0\0"
        .byte 2,4,2,0
        .ascii "DD\0\0"
        .byte 2,6,2,0
        .ascii "HH\0\0"
        .byte 2,9,2,0
        .ascii "mm\0\0"
        .byte 2,11,2,0
        .ascii "ss\0\0"
        .byte 2,13,2,0
        .ascii "hh\0\0"
        .byte 2,9,2,0

m_usage:
        .ascii "LogKlerk asm v0.0.3\n"
        .ascii "  lk                      mode interaktif (exit/quit/Ctrl-D keluar)\n"
        .ascii "  lk <key> <teks...>      catat dgn konteks dari [taxonomy]\n"
        .ascii "  lk lkc [all|filter] [asc|desc]   baca log (default: hari ini (waktu lokal); YYYY, YYYYMM, YYYYMMDD, YYYYMMDDThh, a-b)\n"
        .ascii "  lk lkset taxonomy k=\"V\"      tambah/ubah taxonomy di lk.conf\n"
        .ascii "  lk <perintah...>        jalankan perintah/alias Linux dan catat sbg \"bash\"\n"
        .ascii "  <teks biasa>            kata pertama bukan perintah => hanya dicatat sbg catatan\n"
        .ascii "config: ~/.config/logklerk/lk.conf   (semua waktu = waktu lokal)\n"
        .equ m_usage_len, . - m_usage
m_nohome:   .ascii "lk: variabel HOME tidak ada\n"
        .equ m_nohome_len, . - m_nohome
m_noact:    .ascii "lk: key dikenal tapi teks kosong. Pakai: lk <key> <teks>\n"
        .equ m_noact_len, . - m_noact
m_dirlong:  .ascii "lk: path terlalu panjang\n"
        .equ m_dirlong_len, . - m_dirlong
m_dirrel:   .ascii "lk: LK_DIR harus path absolut (boleh diawali $HOME atau ~)\n"
        .equ m_dirrel_len, . - m_dirrel
m_open:     .ascii "lk: gagal membuka/membuat file log (cek LK_DIR, LK_NAME_FORMAT & izin)\n"
        .equ m_open_len, . - m_open
m_big:      .ascii "lk: baris CSV melebihi buffer, tidak ditulis\n"
        .equ m_big_len, . - m_big
m_write:    .ascii "lk: gagal menulis ke file log\n"
        .equ m_write_len, . - m_write
m_trunc:    .ascii "lk: baris terlalu panjang (>2047), dicatat terpotong dan TIDAK dijalankan\n"
        .equ m_trunc_len, . - m_trunc
m_cd:       .ascii "lk: cd: gagal pindah direktori\n"
        .equ m_cd_len, . - m_cd
m_fork:     .ascii "lk: fork/wait gagal\n"
        .equ m_fork_len, . - m_fork
m_toomany:  .ascii "lk: terlalu banyak argumen (maks 64)\n"
        .equ m_toomany_len, . - m_toomany
m_lkset_usage:
        .ascii "[!] pakai: lkset taxonomy key=\"Value\"  (key: huruf/angka/_/-, maks 32; value maks 128, tanpa tanda kutip)\n"
        .equ m_lkset_usage_len, . - m_lkset_usage
m_reserved: .ascii "[!] lkset: key itu dicadangkan (lk, lkc, lkset, cd, exit, quit)\n"
        .equ m_reserved_len, . - m_reserved
m_conf_big: .ascii "[!] lkset: lk.conf terlalu besar\n"
        .equ m_conf_big_len, . - m_conf_big
m_conf_wr:  .ascii "[!] lkset: gagal menulis lk.conf\n"
        .equ m_conf_wr_len, . - m_conf_wr

# =====================================================================
        .section .data
        .balign 8
fd:         .quad -1                # log file fd, -1 = not opened yet
tail_lines: .quad 3
lkset_tail: .quad 3
cli_flag:   .quad 0                 # 1 = invoked as `lk <args>`
exit_code:  .quad 0
color_on:   .quad 0

# settings table: {name, kind (0=string ptr, 1=integer), target address}
setting_tab:
        .quad s_k_dir,      0, dir_ptr
        .quad s_k_namefmt,  0, name_fmt_ptr
        .quad s_k_defext,   0, ext_ptr
        .quad s_k_tail,     1, tail_lines
        .quad s_k_lksettail,1, lkset_tail
        .quad s_k_cdate,    0, col_ptr
        .quad s_k_ctags,    0, col_ptr+8
        .quad s_k_cctx,     0, col_ptr+16
        .quad s_k_cact,     0, col_ptr+24
        .quad 0

color_tab:
        .quad cn_grey,    sg_grey
        .quad cn_red,     sg_red
        .quad cn_green,   sg_green
        .quad cn_yellow,  sg_yellow
        .quad cn_blue,    sg_blue
        .quad cn_magenta, sg_magenta
        .quad cn_cyan,    sg_cyan
        .quad cn_white,   sg_white
        .quad cn_orange,  sg_orange
        .quad cn_purple,  sg_purple
        .quad 0, 0
col_defaults:
        .quad cn_orange, cn_yellow, cn_purple, cn_grey   # date, tags, context, activity

# =====================================================================
        .section .bss
        .balign 16
argc:       .skip 8
argv_ptr:   .skip 8
envp_ptr:   .skip 8
home_ptr:   .skip 8
dir_ptr:    .skip 8                 # raw LK_DIR value (points into confbuf)
dir_len:    .skip 8                 # expanded LK_DIR length (ends with '/')
name_fmt_ptr: .skip 8
ext_ptr:    .skip 8
col_ptr:    .skip 32
color_sgr:  .skip 32
tax_count:  .skip 8
in_pos:     .skip 8
in_len:     .skip 8
out_pos:    .skip 8
wstatus:    .skip 8
last_status:.skip 8
line_trunc: .skip 8                 # 1 = last input line was truncated
h_toklen:   .skip 8
h_savech:   .skip 8
h_ctx:      .skip 8
pr_fend:    .skip 8
tz_loaded:  .skip 8                 # 1 = zone file load attempted
tz_ok:      .skip 8                 # 1 = zone data usable
tz_timecnt: .skip 8
tz_typecnt: .skip 8
tz_tsz:     .skip 8                 # transition time size: 4 or 8 bytes
tz_times:   .skip 8                 # -> transition times (big endian)
tz_idx:     .skip 8                 # -> transition type indexes
tz_tt:      .skip 8                 # -> ttinfo records (6 bytes each)
tzbuf:      .skip TZMAX+16
probe_pid:  .skip 8                 # pid of the bash probe child (0 = none)
probe_res:  .skip 8                 # byte read from the probe pipe
pipefds:    .skip 8                 # int[2] of pipe2()
is_tty:     .skip 8                 # 1 = stdin is a TTY (interactive bash allowed)
chbuf:      .skip 8
ks_elen:    .skip 8
ks_rawlen:  .skip 8
ks_repls:   .skip 8
ks_reple:   .skip 8
ks_inspos:  .skip 8
ks_keyfound:.skip 8
ks_taxfound:.skip 8
tax_keys:   .skip 8*TAX_MAX         # pointer to key   (inside confbuf)
tax_vals:   .skip 8*TAX_MAX         # pointer to value (inside confbuf)
tl_s:       .skip 8*32
tl_e:       .skip 8*32
exec_argv:  .skip 8*72
mode_key:   .skip 64
curname:    .skip 128
tsbuf:      .skip 32
termios:    .skip 64
linebuf:    .skip LINEMAX+1
actbuf:     .skip ACTMAX+1
inbuf:      .skip INBUF_SZ
entrybuf:   .skip ENTRYMAX
pathbuf:    .skip PATHMAX
pbuf2:      .skip PATHMAX
confpath:   .skip PATHMAX
tmppath:    .skip PATHMAX
confbuf:    .skip CONFMAX+1
rawbuf:     .skip CONFMAX+2
newbuf:     .skip NEWMAX+16
outbuf:     .skip OUTSZ
tailbuf:    .skip TAILWIN

# =====================================================================
        .text
        .globl _start

.macro ERR msg, len
        mov     edi, 2
        lea     rsi, [rip+\msg]
        mov     edx, \len
        call    write_all
.endm

.macro DIE msg, len, code
        ERR     \msg, \len
        mov     edi, \code
        mov     eax, SYS_exit
        syscall
.endm

# ---------------------------------------------------------------------
# write_all(edi=fd, rsi=buf, rdx=len) -> rax = 0 ok, -1 failed
# Handles short writes & EINTR; write()==0 is treated as an error (no endless loop).
# CLOBBER: rax, rcx, rdx, rsi, rdi, r11
# ---------------------------------------------------------------------
write_all:
        push    rbx
        push    r12
        push    r13
        mov     ebx, edi
        mov     r12, rsi
        mov     r13, rdx
.Lwa_loop:
        test    r13, r13
        jz      .Lwa_ok
        mov     eax, SYS_write
        mov     edi, ebx
        mov     rsi, r12
        mov     rdx, r13
        syscall
        cmp     rax, EINTR_NEG
        je      .Lwa_loop
        test    rax, rax
        jle     .Lwa_err
        add     r12, rax
        sub     r13, rax
        jmp     .Lwa_loop
.Lwa_ok:
        xor     eax, eax
        jmp     .Lwa_out
.Lwa_err:
        mov     rax, -1
.Lwa_out:
        pop     r13
        pop     r12
        pop     rbx
        ret

# strlen(rdi=cstr) -> rax.  Only for trusted NUL-terminated strings.  CLOBBER: rax
strlen:
        xor     eax, eax
.Lsl_l:
        cmp     byte ptr [rdi+rax], 0
        je      .Lsl_d
        inc     rax
        jmp     .Lsl_l
.Lsl_d:
        ret

# ---------------------------------------------------------------------
# bcopy_z(rdi=dst, rsi=src, rdx=limit) -> rax = new dst, 0 on overflow
# Copies up to the NUL (NUL not included). Writes only to addresses < limit.
# CLOBBER: rax, rcx, rdi, rsi
# ---------------------------------------------------------------------
bcopy_z:
.Lbz_l:
        mov     cl, [rsi]
        test    cl, cl
        jz      .Lbz_d
        cmp     rdi, rdx
        jae     .Lbz_ovf
        mov     [rdi], cl
        inc     rdi
        inc     rsi
        jmp     .Lbz_l
.Lbz_d:
        mov     rax, rdi
        ret
.Lbz_ovf:
        xor     eax, eax
        ret

# bcopy_n(rdi=dst, rsi=src, rcx=n) -> rax = new dst, 0 if it would pass the end of newbuf
# CLOBBER: rax, rcx, rdi, rsi
bcopy_n:
        lea     rax, [rip+newbuf+NEWMAX]
        sub     rax, rdi
        cmp     rcx, rax
        ja      .Lbn_ovf
        rep movsb
        mov     rax, rdi
        ret
.Lbn_ovf:
        xor     eax, eax
        ret

# getenv(rdi="NAME=", rsi=envp) -> rax = value ptr / 0.  CLOBBER: rax, rcx, rsi, r8
getenv:
.Lge_next:
        mov     r8, [rsi]
        test    r8, r8
        jz      .Lge_none
        add     rsi, 8
        xor     ecx, ecx
.Lge_cmp:
        mov     al, [rdi+rcx]
        test    al, al
        jz      .Lge_found
        cmp     al, [r8+rcx]
        jne     .Lge_next
        inc     rcx
        jmp     .Lge_cmp
.Lge_found:
        lea     rax, [r8+rcx]
        ret
.Lge_none:
        xor     eax, eax
        ret

# streq(rdi, rsi) -> eax=1 equal / 0 different.  CLOBBER: rax, rcx  (rdi,rsi preserved)
streq:
        xor     ecx, ecx
.Lse_l:
        mov     al, [rdi+rcx]
        cmp     al, [rsi+rcx]
        jne     .Lse_no
        test    al, al
        jz      .Lse_yes
        inc     rcx
        jmp     .Lse_l
.Lse_yes:
        mov     eax, 1
        ret
.Lse_no:
        xor     eax, eax
        ret

# strcmp(rdi, rsi) -> eax (<0, 0, >0).  CLOBBER: rax, rcx, rdx
strcmp:
        xor     ecx, ecx
.Lsc_l:
        movzx   eax, byte ptr [rdi+rcx]
        movzx   edx, byte ptr [rsi+rcx]
        cmp     eax, edx
        jne     .Lsc_d
        test    eax, eax
        jz      .Lsc_d
        inc     rcx
        jmp     .Lsc_l
.Lsc_d:
        sub     eax, edx
        ret

# starts_with(rdi=str, rsi=prefix) -> eax=1/0, rcx = prefix length.  CLOBBER: rax, rcx
starts_with:
        xor     ecx, ecx
.Lsw_l:
        mov     al, [rsi+rcx]
        test    al, al
        jz      .Lsw_yes
        cmp     al, [rdi+rcx]
        jne     .Lsw_no
        inc     rcx
        jmp     .Lsw_l
.Lsw_yes:
        mov     eax, 1
        ret
.Lsw_no:
        xor     eax, eax
        ret

# skip_ws(rdi) -> rdi advanced past spaces/tabs.  CLOBBER: rdi, al
skip_ws:
.Lsk_l:
        mov     al, [rdi]
        cmp     al, ' '
        je      .Lsk_n
        cmp     al, 9
        jne     .Lsk_d
.Lsk_n:
        inc     rdi
        jmp     .Lsk_l
.Lsk_d:
        ret

# tax_lookup(rdi=key cstr) -> rax = context ptr / 0.  CLOBBER: rax, rcx, rsi, r8
tax_lookup:
        push    rbx
        xor     ebx, ebx
.Ltl_loop:
        cmp     rbx, [rip+tax_count]
        jae     .Ltl_none
        lea     r8, [rip+tax_keys]
        mov     rsi, [r8+rbx*8]
        call    streq
        test    eax, eax
        jnz     .Ltl_hit
        inc     rbx
        jmp     .Ltl_loop
.Ltl_hit:
        lea     r8, [rip+tax_vals]
        mov     rax, [r8+rbx*8]
        pop     rbx
        ret
.Ltl_none:
        xor     eax, eax
        pop     rbx
        ret

# parse_int(rdi=cstr) -> rax (signed), max 10 digits.  CLOBBER: rax, rcx, rdx, rdi, r8
parse_int:
        xor     eax, eax
        xor     ecx, ecx
        xor     edx, edx
        cmp     byte ptr [rdi], '-'
        jne     .Lpi_plus
        inc     ecx
        inc     rdi
        jmp     .Lpi_d
.Lpi_plus:
        cmp     byte ptr [rdi], '+'
        jne     .Lpi_d
        inc     rdi
.Lpi_d:
        movzx   r8d, byte ptr [rdi]
        sub     r8d, '0'
        cmp     r8d, 9
        ja      .Lpi_end
        cmp     edx, 10
        jae     .Lpi_end
        imul    rax, rax, 10
        add     rax, r8
        inc     edx
        inc     rdi
        jmp     .Lpi_d
.Lpi_end:
        test    ecx, ecx
        jz      .Lpi_ret
        neg     rax
.Lpi_ret:
        ret

# write_dec(rdi=dst, rax=value, ecx=digits) -> rdi = dst+digits (zero-padded)
# CLOBBER: rax, rcx, rdx, r8, r10
write_dec:
        add     rdi, rcx
        mov     r8, rdi
        mov     r10d, 10
.Lwd_l:
        xor     edx, edx
        div     r10
        add     dl, '0'
        dec     r8
        mov     [r8], dl
        dec     rcx
        jnz     .Lwd_l
        ret

# ---------------------------------------------------------------------
# tz_load(): read the zone file ONCE into tzbuf and locate its tables.
# Path: $TZ (":" prefix ignored; relative names live in /usr/share/zoneinfo/)
# or /etc/localtime. Uses the v2+ (64-bit) block when present, else v1.
# On any problem tz_ok stays 0 and times simply stay UTC.
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11 (pbuf2 is used as scratch)
# ---------------------------------------------------------------------
tz_load:
        push    rbx
        mov     qword ptr [rip+tz_loaded], 1
        mov     qword ptr [rip+tz_ok], 0
        lea     rdi, [rip+s_tz_eq]
        mov     rsi, [rip+envp_ptr]
        call    getenv
        test    rax, rax
        jz      .Ltz_def
        cmp     byte ptr [rax], ':'
        jne     .Ltz_n1
        inc     rax
.Ltz_n1:
        cmp     byte ptr [rax], 0
        je      .Ltz_def
        mov     rbx, rax
        lea     rdi, [rip+pbuf2]
        cmp     byte ptr [rax], '/'
        je      .Ltz_cat
        lea     rsi, [rip+s_zoneinfo]
        lea     rdx, [rip+pbuf2+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Ltz_out
        mov     rdi, rax
.Ltz_cat:
        mov     rsi, rbx
        lea     rdx, [rip+pbuf2+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Ltz_out
        mov     byte ptr [rax], 0
        lea     rdi, [rip+pbuf2]
        jmp     .Ltz_open
.Ltz_def:
        lea     rdi, [rip+s_localtime]
.Ltz_open:
        mov     eax, SYS_open
        mov     esi, O_RDONLY|O_CLOEXEC
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Ltz_out
        mov     rbx, rax
        xor     r8d, r8d
.Ltz_rd:
        mov     rdx, TZMAX
        sub     rdx, r8
        jz      .Ltz_cl
        lea     rsi, [rip+tzbuf]
        add     rsi, r8
        xor     eax, eax
        mov     rdi, rbx
        syscall
        cmp     rax, EINTR_NEG
        je      .Ltz_rd
        test    rax, rax
        jle     .Ltz_cl
        add     r8, rax
        jmp     .Ltz_rd
.Ltz_cl:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
        cmp     r8, 44
        jb      .Ltz_out
        lea     rsi, [rip+tzbuf]
        lea     rbx, [rsi+r8]                       # rbx = end of data
        cmp     dword ptr [rsi], 0x66695a54         # "TZif"
        jne     .Ltz_out
        mov     r9d, 4                              # time size (v1)
        cmp     byte ptr [rsi+4], 0
        je      .Ltz_hdr
        mov     eax, [rsi+32]                       # skip the v1 block
        bswap   eax
        lea     rdx, [rax+rax*4]                    # timecnt*5
        mov     eax, [rsi+36]
        bswap   eax
        lea     rax, [rax+rax*2]
        lea     rdx, [rdx+rax*2]                    # + typecnt*6
        mov     eax, [rsi+40]
        bswap   eax
        add     rdx, rax                            # + charcnt
        mov     eax, [rsi+28]
        bswap   eax
        lea     rdx, [rdx+rax*8]                    # + leapcnt*8
        mov     eax, [rsi+24]
        bswap   eax
        add     rdx, rax                            # + isstdcnt
        mov     eax, [rsi+20]
        bswap   eax
        add     rdx, rax                            # + isutcnt
        lea     rsi, [rsi+rdx+44]                   # v2 header
        mov     r9d, 8
        lea     rax, [rsi+44]
        cmp     rax, rbx
        ja      .Ltz_out
.Ltz_hdr:
        mov     eax, [rsi+32]
        bswap   eax
        mov     r10, rax                            # timecnt
        mov     eax, [rsi+36]
        bswap   eax
        mov     r11, rax                            # typecnt
        test    r11, r11
        jz      .Ltz_out
        lea     rdi, [rsi+44]                       # transition times
        mov     rax, r10
        imul    rax, r9
        add     rax, rdi                            # -> type indexes
        mov     rcx, rax
        add     rcx, r10                            # -> ttinfo records
        lea     rdx, [r11+r11*2]
        lea     rdx, [rcx+rdx*2]                    # end of the tables
        cmp     rdx, rbx
        ja      .Ltz_out
        mov     [rip+tz_timecnt], r10
        mov     [rip+tz_typecnt], r11
        mov     [rip+tz_tsz], r9
        mov     [rip+tz_times], rdi
        mov     [rip+tz_idx], rax
        mov     [rip+tz_tt], rcx
        mov     qword ptr [rip+tz_ok], 1
.Ltz_out:
        pop     rbx
        ret

# ---------------------------------------------------------------------
# tz_offset(rdi=epoch seconds) -> rax = local UTC offset in seconds
# (0 when no zone data). Uses the last transition <= epoch; DST zones are
# covered by the transitions stored in the file (fat tzdata, up to 2037).
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
# ---------------------------------------------------------------------
tz_offset:
        cmp     qword ptr [rip+tz_loaded], 0
        jne     .Lto_l
        push    rdi
        call    tz_load
        pop     rdi
.Lto_l:
        cmp     qword ptr [rip+tz_ok], 0
        je      .Lto_zero
        mov     rsi, [rip+tz_times]
        mov     rcx, [rip+tz_timecnt]
        xor     edx, edx
        xor     r8d, r8d                            # type before the first transition = 0
.Lto_scan:
        cmp     rdx, rcx
        jae     .Lto_pick
        cmp     qword ptr [rip+tz_tsz], 8
        jne     .Lto_t4
        mov     rax, [rsi+rdx*8]
        bswap   rax
        jmp     .Lto_cmp
.Lto_t4:
        mov     eax, [rsi+rdx*4]
        bswap   eax
        movsxd  rax, eax
.Lto_cmp:
        cmp     rax, rdi
        jg      .Lto_pick
        mov     r9, [rip+tz_idx]
        movzx   r8d, byte ptr [r9+rdx]
        inc     rdx
        jmp     .Lto_scan
.Lto_pick:
        cmp     r8, [rip+tz_typecnt]
        jae     .Lto_zero
        mov     r9, [rip+tz_tt]
        lea     r8, [r8+r8*2]
        mov     eax, [r9+r8*2]
        bswap   eax
        movsxd  rax, eax
        ret
.Lto_zero:
        xor     eax, eax
        ret

# ---------------------------------------------------------------------
# fmt_time(rdi=dst[>=15 bytes]) -> "YYYYMMDDThhmmss" (ISO 8601 basic, LOCAL time), rdi=dst+15
# Algorithm civil_from_days (H. Hinnant).  CLOBBER: rax, rcx, rdx, rsi, r8-r11
# ---------------------------------------------------------------------
fmt_time:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 16
        mov     r12, rdi
        mov     eax, SYS_clock_gettime
        xor     edi, edi
        mov     rsi, rsp
        syscall
        test    rax, rax
        jz      .Lft_have
        mov     qword ptr [rsp], 0
        mov     qword ptr [rsp+8], 0
.Lft_have:
        mov     rbx, [rsp]                  # epoch seconds (UTC), then shifted to local time
        mov     rdi, rbx
        call    tz_offset
        add     rbx, rax
        mov     rax, rbx
        xor     edx, edx
        mov     rcx, 86400
        div     rcx
        mov     r15, rdx                    # seconds within the day
        add     rax, 719468
        xor     edx, edx
        mov     rcx, 146097
        div     rcx
        mov     r8, rax                     # era
        mov     r9, rdx                     # doe
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 1460
        div     rcx
        mov     r10, rax
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 36524
        div     rcx
        mov     r11, rax
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 146096
        div     rcx
        mov     rcx, r9
        sub     rcx, r10
        add     rcx, r11
        sub     rcx, rax
        mov     rax, rcx
        xor     edx, edx
        mov     rcx, 365
        div     rcx
        mov     r10, rax                    # yoe
        imul    r8, r8, 400
        add     r8, r10
        mov     rax, r10
        shr     rax, 2
        mov     rcx, r10
        imul    rcx, rcx, 365
        add     rcx, rax
        mov     rax, r10
        xor     edx, edx
        mov     r11, 100
        div     r11
        sub     rcx, rax
        mov     rax, r9
        sub     rax, rcx                    # doy
        mov     r9, rax
        lea     rax, [rax+rax*4+2]
        xor     edx, edx
        mov     rcx, 153
        div     rcx                         # mp
        mov     r10, rax
        imul    rax, rax, 153
        add     rax, 2
        xor     edx, edx
        mov     rcx, 5
        div     rcx
        sub     r9, rax
        inc     r9                          # d
        cmp     r10, 10
        jb      .Lft_lt
        sub     r10, 9
        jmp     .Lft_m
.Lft_lt:
        add     r10, 3
.Lft_m:
        cmp     r10, 2
        ja      .Lft_noadj
        inc     r8
.Lft_noadj:
        mov     rbx, r8                     # y
        mov     r13, r10                    # m
        mov     [rsp], r9                   # d
        mov     rdi, r12
        mov     rax, rbx
        mov     ecx, 4
        call    write_dec
        mov     rax, r13
        mov     ecx, 2
        call    write_dec
        mov     rax, [rsp]
        mov     ecx, 2
        call    write_dec
        mov     byte ptr [rdi], 'T'
        inc     rdi
        mov     rax, r15
        xor     edx, edx
        mov     rcx, 3600
        div     rcx
        mov     r15, rdx
        mov     ecx, 2
        call    write_dec
        mov     rax, r15
        xor     edx, edx
        mov     rcx, 60
        div     rcx
        mov     r15, rdx
        mov     ecx, 2
        call    write_dec
        mov     rax, r15
        mov     ecx, 2
        call    write_dec
        add     rsp, 16
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# stdout buffer (OUTSZ). All output goes through here, flushed manually.
# ---------------------------------------------------------------------
# out_flush()   CLOBBER: rax, rcx, rdx, rsi, rdi, r11
out_flush:
        mov     rdx, [rip+out_pos]
        test    rdx, rdx
        jz      .Lof_d
        mov     qword ptr [rip+out_pos], 0
        mov     edi, 1
        lea     rsi, [rip+outbuf]
        call    write_all
.Lof_d:
        ret

# out_bytes(rsi=src, rdx=len)   CLOBBER: rax, rcx, rdx, rsi, rdi, r11
out_bytes:
        push    rbx
        push    r12
        mov     rbx, rsi
        mov     r12, rdx
.Lob_l:
        test    r12, r12
        jz      .Lob_d
        mov     rax, [rip+out_pos]
        mov     rcx, OUTSZ
        sub     rcx, rax
        jnz     .Lob_room
        call    out_flush
        jmp     .Lob_l
.Lob_room:
        cmp     rcx, r12
        jbe     .Lob_n
        mov     rcx, r12
.Lob_n:
        lea     rdi, [rip+outbuf]
        add     rdi, rax
        mov     rsi, rbx
        add     rax, rcx
        mov     [rip+out_pos], rax
        sub     r12, rcx
        add     rbx, rcx
        rep movsb
        jmp     .Lob_l
.Lob_d:
        pop     r12
        pop     rbx
        ret

# out_cstr(rdi=cstr)   CLOBBER: same as out_bytes
out_cstr:
        mov     rsi, rdi
        call    strlen
        mov     rdx, rax
        jmp     out_bytes

# out_ch(dil=char)
out_ch:
        mov     [rip+chbuf], dil
        lea     rsi, [rip+chbuf]
        mov     edx, 1
        jmp     out_bytes

# out_colored(rsi=ptr, rdx=len, ecx=column index 0..3)
out_colored:
        push    rbx
        push    r12
        push    r13
        mov     rbx, rsi
        mov     r12, rdx
        lea     rax, [rip+color_sgr]
        mov     r13, [rax+rcx*8]
        test    r12, r12                    # empty field: no color codes
        jnz     .Loc_nz
        xor     r13d, r13d
.Loc_nz:
        test    r13, r13
        jz      .Loc_plain
        mov     rdi, r13
        call    out_cstr
.Loc_plain:
        mov     rsi, rbx
        mov     rdx, r12
        call    out_bytes
        test    r13, r13
        jz      .Loc_done
        lea     rdi, [rip+s_reset]
        call    out_cstr
.Loc_done:
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# print_row(rsi=row, rdx=len): print a CSV row + '\n'. When color is on,
# the first 3 columns (date,tags,context) and the rest (activity) are colored
# separately; a comma inside double quotes does not split a column.
# ---------------------------------------------------------------------
print_row:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     rbx, rsi
        mov     r12, rdx
        cmp     qword ptr [rip+color_on], 0
        je      .Lpr_plain
        mov     r14, rbx
        xor     r13d, r13d
        lea     r15, [rbx+r12]
.Lpr_seg:
        cmp     r13, 3
        jae     .Lpr_last
        mov     rsi, r14
        xor     edx, edx
.Lpr_scan:
        cmp     rsi, r15
        jae     .Lpr_fend
        mov     al, [rsi]
        cmp     al, '"'
        jne     .Lpr_nq
        xor     edx, 1
        jmp     .Lpr_nx
.Lpr_nq:
        cmp     al, ','
        jne     .Lpr_nx
        test    edx, edx
        jz      .Lpr_fend
.Lpr_nx:
        inc     rsi
        jmp     .Lpr_scan
.Lpr_fend:
        mov     [rip+pr_fend], rsi
        mov     rdx, rsi
        mov     rsi, r14
        sub     rdx, rsi
        mov     ecx, r13d
        call    out_colored
        mov     rsi, [rip+pr_fend]
        cmp     rsi, r15
        jae     .Lpr_nl
        mov     edi, ','
        call    out_ch
        mov     r14, [rip+pr_fend]
        inc     r14
        inc     r13
        jmp     .Lpr_seg
.Lpr_last:
        mov     rsi, r14
        mov     rdx, r15
        sub     rdx, rsi
        mov     ecx, 3
        call    out_colored
        jmp     .Lpr_nl
.Lpr_plain:
        mov     rsi, rbx
        mov     rdx, r12
        call    out_bytes
.Lpr_nl:
        mov     edi, 10
        call    out_ch
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# csv_field(rdi=dst, rsi=src, rdx=limit, rcx=len) -> rax = new dst / 0
# RFC 4180: quoted only if it contains , or "; " is doubled; CR/LF -> space.
# Margin: before every source byte there must be >= 3 free bytes.
# CLOBBER: rax, rcx, rdi, rsi, r8-r11
# ---------------------------------------------------------------------
csv_field:
        lea     r9, [rsi+rcx]
        mov     r8, rsi
        xor     r11d, r11d
.Lcf_scan:
        cmp     r8, r9
        jae     .Lcf_go
        mov     r10b, [r8]
        inc     r8
        cmp     r10b, ','
        je      .Lcf_q
        cmp     r10b, '"'
        jne     .Lcf_scan
.Lcf_q:
        mov     r11d, 1
.Lcf_go:
        test    r11d, r11d
        jz      .Lcf_copy
        lea     rax, [rdi+1]
        cmp     rax, rdx
        jae     .Lcf_ovf
        mov     byte ptr [rdi], '"'
        inc     rdi
.Lcf_copy:
        cmp     rsi, r9
        jae     .Lcf_end
        lea     rax, [rdi+3]
        cmp     rax, rdx
        ja      .Lcf_ovf
        mov     r10b, [rsi]
        inc     rsi
        cmp     r10b, 10
        je      .Lcf_sp
        cmp     r10b, 13
        je      .Lcf_sp
        cmp     r10b, '"'
        jne     .Lcf_put
        mov     byte ptr [rdi], '"'
        inc     rdi
        jmp     .Lcf_put
.Lcf_sp:
        mov     r10b, ' '
.Lcf_put:
        mov     [rdi], r10b
        inc     rdi
        jmp     .Lcf_copy
.Lcf_end:
        test    r11d, r11d
        jz      .Lcf_done
        cmp     rdi, rdx
        jae     .Lcf_ovf
        mov     byte ptr [rdi], '"'
        inc     rdi
.Lcf_done:
        mov     rax, rdi
        ret
.Lcf_ovf:
        xor     eax, eax
        ret

# csv_qfield(rdi=dst, rsi=src, rdx=limit, rcx=len) -> rax = new dst / 0
# Same as csv_field but ALWAYS wraps the field in double quotes (string format),
# even when it is empty ("").  CLOBBER: rax, rcx, rdi, rsi, r8-r11
csv_qfield:
        lea     r9, [rsi+rcx]
        mov     r11d, 1
        jmp     .Lcf_go

# ---------------------------------------------------------------------
# format_name(rdi=dst) -> rax = ptr to the final NUL / 0 on overflow
# Expands LK_NAME_FORMAT from tsbuf (local time) + LK_DEFAULT_FORMAT.
# Tokens: YYYY MM DD HH hh mm ss. "MM" right after "HH"/"hh" counts as minutes
# (allows writing "HHMMss"). '/' becomes '_'. Anything else is literal.
# ---------------------------------------------------------------------
format_name:
        push    rbx
        push    r12
        lea     rdx, [rip+pathbuf+PATHMAX-1]
        mov     rsi, [rip+name_fmt_ptr]
        xor     r12d, r12d                  # flag: previous token was HH/hh
.Lfn_loop:
        mov     al, [rsi]
        test    al, al
        jz      .Lfn_ext
        lea     r8, [rip+fn_tab]
        xor     r9d, r9d
.Lfn_try:
        cmp     r9d, 7
        jae     .Lfn_lit
        xor     ecx, ecx
        movzx   r10d, byte ptr [r8+4]
.Lfn_cmp:
        cmp     ecx, r10d
        jae     .Lfn_match
        mov     al, [r8+rcx]
        cmp     al, [rsi+rcx]
        jne     .Lfn_next
        inc     ecx
        jmp     .Lfn_cmp
.Lfn_next:
        add     r8, 8
        inc     r9d
        jmp     .Lfn_try
.Lfn_match:
        movzx   r10d, byte ptr [r8+5]
        movzx   r11d, byte ptr [r8+6]
        cmp     r9d, 1
        jne     .Lfn_nomm
        test    r12d, r12d
        jz      .Lfn_nomm
        mov     r10d, 11
.Lfn_nomm:
        xor     r12d, r12d
        cmp     r9d, 3
        je      .Lfn_hh
        cmp     r9d, 6                      # "hh" alias
        jne     .Lfn_adv
.Lfn_hh:
        mov     r12d, 1
.Lfn_adv:
        movzx   ecx, byte ptr [r8+4]
        add     rsi, rcx
        lea     rbx, [rip+tsbuf]
        add     rbx, r10
.Lfn_cp:
        test    r11d, r11d
        jz      .Lfn_loop
        cmp     rdi, rdx
        jae     .Lfn_ovf
        mov     al, [rbx]
        mov     [rdi], al
        inc     rdi
        inc     rbx
        dec     r11d
        jmp     .Lfn_cp
.Lfn_lit:
        xor     r12d, r12d
        mov     al, [rsi]
        inc     rsi
        cmp     al, '/'
        jne     .Lfn_lit2
        mov     al, '_'
.Lfn_lit2:
        cmp     rdi, rdx
        jae     .Lfn_ovf
        mov     [rdi], al
        inc     rdi
        jmp     .Lfn_loop
.Lfn_ext:
        mov     rsi, [rip+ext_ptr]
.Lfn_e:
        mov     al, [rsi]
        test    al, al
        jz      .Lfn_done
        cmp     rdi, rdx
        jae     .Lfn_ovf
        mov     [rdi], al
        inc     rdi
        inc     rsi
        jmp     .Lfn_e
.Lfn_done:
        cmp     rdi, rdx
        jae     .Lfn_ovf
        mov     byte ptr [rdi], 0
        mov     rax, rdi
        pop     r12
        pop     rbx
        ret
.Lfn_ovf:
        xor     eax, eax
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# ensure_open() -> rax 0 ok / -1.  The file name is computed PER ENTRY from
# LK_NAME_FORMAT; if it changed (e.g. across local midnight) the old fd is
# closed and the new file is opened. O_EXCL => only the creator writes the header.
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
# ---------------------------------------------------------------------
ensure_open:
        lea     rdi, [rip+pathbuf]
        add     rdi, [rip+dir_len]
        call    format_name
        test    rax, rax
        jz      .Leo_fail
        cmp     qword ptr [rip+fd], 0
        jl      .Leo_open
        lea     rdi, [rip+pathbuf]
        add     rdi, [rip+dir_len]
        lea     rsi, [rip+curname]
        call    streq
        test    eax, eax
        jnz     .Leo_ok
        mov     eax, SYS_close
        mov     rdi, [rip+fd]
        syscall
        mov     qword ptr [rip+fd], -1
.Leo_open:
        mov     eax, SYS_open
        lea     rdi, [rip+pathbuf]
        mov     esi, O_WRONLY|O_CREAT|O_EXCL|O_APPEND|O_CLOEXEC|O_NOFOLLOW
        mov     edx, 0600
        syscall
        cmp     rax, EEXIST_NEG
        je      .Leo_exists
        test    rax, rax
        js      .Leo_fail
        mov     [rip+fd], rax
        mov     edi, eax
        lea     rsi, [rip+s_header]
        mov     edx, s_header_len
        call    write_all
        test    rax, rax
        jnz     .Leo_fail
        jmp     .Leo_setname
.Leo_exists:
        mov     eax, SYS_open
        lea     rdi, [rip+pathbuf]
        mov     esi, O_WRONLY|O_APPEND|O_CLOEXEC|O_NOFOLLOW
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Leo_fail
        mov     [rip+fd], rax
.Leo_setname:
        lea     rdi, [rip+curname]
        lea     rsi, [rip+pathbuf]
        add     rsi, [rip+dir_len]
        lea     rdx, [rip+curname+127]
        call    bcopy_z
        test    rax, rax
        jz      .Leo_fail
        mov     byte ptr [rax], 0
.Leo_ok:
        xor     eax, eax
        ret
.Leo_fail:
        mov     rax, -1
        ret

# ---------------------------------------------------------------------
# emit_entry(rdi=tags cstr, rsi=context cstr, rdx=activity ptr, rcx=len)
#   -> rax 0 ok / -1 (error message already printed)
# One CSV line is built in entrybuf and written with ONE write() on the
# O_APPEND fd => lines never interleave even when many shells write at once.
# Line format:  YYYYMMDDThhmmss,lktags,"lkcontext","log activity"
# ---------------------------------------------------------------------
emit_entry:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12, rdi
        mov     r13, rsi
        mov     r14, rdx
        mov     r15, rcx
        lea     rdi, [rip+tsbuf]
        call    fmt_time
        call    ensure_open
        test    rax, rax
        jnz     .Lee_eopen
        lea     rdi, [rip+entrybuf]
        lea     rsi, [rip+tsbuf]
        mov     ecx, 15                     # YYYYMMDDThhmmss
        rep movsb
        mov     byte ptr [rdi], ','
        inc     rdi
        mov     rbx, rdi
        mov     rdi, r12                    # --- tags (quoted only if needed)
        call    strlen
        mov     rcx, rax
        mov     rdi, rbx
        mov     rsi, r12
        lea     rdx, [rip+entrybuf+ENTRYMAX-2]
        call    csv_field
        test    rax, rax
        jz      .Lee_ebig
        mov     rdi, rax
        mov     byte ptr [rdi], ','
        inc     rdi
        mov     rbx, rdi
        mov     rdi, r13                    # --- context (always a quoted string)
        call    strlen
        mov     rcx, rax
        mov     rdi, rbx
        mov     rsi, r13
        lea     rdx, [rip+entrybuf+ENTRYMAX-2]
        call    csv_qfield
        test    rax, rax
        jz      .Lee_ebig
        mov     rdi, rax
        mov     byte ptr [rdi], ','
        inc     rdi
        mov     rsi, r14                    # --- activity (always a quoted string)
        mov     rcx, r15
        lea     rdx, [rip+entrybuf+ENTRYMAX-2]
        call    csv_qfield
        test    rax, rax
        jz      .Lee_ebig
        mov     byte ptr [rax], 10
        inc     rax
        lea     rsi, [rip+entrybuf]
        mov     rdx, rax
        sub     rdx, rsi
        mov     rdi, [rip+fd]
        call    write_all
        test    rax, rax
        jnz     .Lee_ewrite
        xor     eax, eax
        jmp     .Lee_out
.Lee_eopen:
        ERR     m_open, m_open_len
        jmp     .Lee_fail
.Lee_ebig:
        ERR     m_big, m_big_len
        jmp     .Lee_fail
.Lee_ewrite:
        ERR     m_write, m_write_len
.Lee_fail:
        mov     rax, -1
.Lee_out:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# parse_config(): parse confbuf (NUL-terminated) IN-PLACE (key/value = pointers
# into confbuf, no copying). [section], key="value", comments # ;, CRLF.
# ---------------------------------------------------------------------
parse_config:
        push    rbx
        push    r12
        push    r13
        push    r14
        lea     rbx, [rip+confbuf]
        xor     r12d, r12d
.Lpc_line:
        cmp     byte ptr [rbx], 0
        je      .Lpc_done
        mov     r13, rbx
.Lpc_fe:
        mov     al, [r13]
        test    al, al
        jz      .Lpc_fe_done
        cmp     al, 10
        je      .Lpc_fe_done
        inc     r13
        jmp     .Lpc_fe
.Lpc_fe_done:
        mov     r14, r13
        cmp     byte ptr [r13], 0
        je      .Lpc_noadv
        mov     byte ptr [r13], 0
        inc     r14
.Lpc_noadv:
.Lpc_trim_r:
        cmp     r13, rbx
        jbe     .Lpc_trim_l
        mov     al, [r13-1]
        cmp     al, ' '
        je      .Lpc_tr
        cmp     al, 9
        je      .Lpc_tr
        cmp     al, 13
        jne     .Lpc_trim_l
.Lpc_tr:
        dec     r13
        mov     byte ptr [r13], 0
        jmp     .Lpc_trim_r
.Lpc_trim_l:
        mov     al, [rbx]
        cmp     al, ' '
        je      .Lpc_tl
        cmp     al, 9
        jne     .Lpc_class
.Lpc_tl:
        inc     rbx
        jmp     .Lpc_trim_l
.Lpc_class:
        mov     al, [rbx]
        test    al, al
        jz      .Lpc_next
        cmp     al, '#'
        je      .Lpc_next
        cmp     al, ';'
        je      .Lpc_next
        cmp     al, '['
        je      .Lpc_section
        mov     rsi, rbx
.Lpc_feq:
        mov     al, [rsi]
        test    al, al
        jz      .Lpc_next
        cmp     al, '='
        je      .Lpc_haveeq
        inc     rsi
        jmp     .Lpc_feq
.Lpc_haveeq:
        mov     rdi, rsi
        mov     byte ptr [rsi], 0
        inc     rsi
.Lpc_kt:
        cmp     rdi, rbx
        jbe     .Lpc_kdone
        mov     al, [rdi-1]
        cmp     al, ' '
        je      .Lpc_ktz
        cmp     al, 9
        jne     .Lpc_kdone
.Lpc_ktz:
        dec     rdi
        mov     byte ptr [rdi], 0
        jmp     .Lpc_kt
.Lpc_kdone:
.Lpc_vl:
        mov     al, [rsi]
        cmp     al, ' '
        je      .Lpc_vlz
        cmp     al, 9
        jne     .Lpc_vq
.Lpc_vlz:
        inc     rsi
        jmp     .Lpc_vl
.Lpc_vq:
        cmp     byte ptr [rsi], '"'
        jne     .Lpc_vdone
        inc     rsi
        cmp     r13, rsi
        jbe     .Lpc_vdone
        cmp     byte ptr [r13-1], '"'
        jne     .Lpc_vdone
        mov     byte ptr [r13-1], 0
.Lpc_vdone:
        cmp     byte ptr [rbx], 0
        je      .Lpc_next
        cmp     r12, 1
        je      .Lpc_setting
        cmp     r12, 2
        je      .Lpc_tax
        jmp     .Lpc_next
.Lpc_tax:
        mov     rax, [rip+tax_count]
        cmp     rax, TAX_MAX
        jae     .Lpc_next
        lea     r8, [rip+tax_keys]
        mov     [r8+rax*8], rbx
        lea     r8, [rip+tax_vals]
        mov     [r8+rax*8], rsi
        inc     rax
        mov     [rip+tax_count], rax
        jmp     .Lpc_next
.Lpc_setting:
        mov     r9, rsi                     # value
        lea     r10, [rip+setting_tab]
.Lpc_sl:
        mov     rsi, [r10]
        test    rsi, rsi
        jz      .Lpc_next
        mov     rdi, rbx
        call    streq
        test    eax, eax
        jnz     .Lpc_sset
        add     r10, 24
        jmp     .Lpc_sl
.Lpc_sset:
        mov     rdx, [r10+16]
        cmp     qword ptr [r10+8], 0
        jne     .Lpc_sint
        mov     [rdx], r9
        jmp     .Lpc_next
.Lpc_sint:
        mov     r10, rdx
        mov     rdi, r9
        call    parse_int
        mov     [r10], rax
        jmp     .Lpc_next
.Lpc_section:
        mov     rdi, rbx
        lea     rsi, [rip+s_sec_settings]
        call    streq
        test    eax, eax
        jz      .Lpc_s2
        mov     r12d, 1
        jmp     .Lpc_next
.Lpc_s2:
        mov     rdi, rbx
        lea     rsi, [rip+s_sec_taxonomy]
        call    streq
        mov     r12d, 2
        test    eax, eax
        jnz     .Lpc_next
        xor     r12d, r12d
.Lpc_next:
        mov     rbx, r14
        jmp     .Lpc_line
.Lpc_done:
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# lookup_color(rdi=name) -> rax = SGR string / 0.  CLOBBER: rax, rcx, rsi, r8
lookup_color:
        lea     r8, [rip+color_tab]
.Llc_l:
        mov     rsi, [r8]
        test    rsi, rsi
        jz      .Llc_none
        call    streq
        test    eax, eax
        jnz     .Llc_hit
        add     r8, 16
        jmp     .Llc_l
.Llc_hit:
        mov     rax, [r8+8]
        ret
.Llc_none:
        xor     eax, eax
        ret

# ---------------------------------------------------------------------
# validate_settings(): fill in defaults for missing/invalid keys.
# ---------------------------------------------------------------------
validate_settings:
        mov     rdi, [rip+name_fmt_ptr]
        test    rdi, rdi
        jz      .Lv_def1
        call    strlen
        test    rax, rax
        jz      .Lv_def1
        cmp     rax, 64
        jbe     .Lv_ext
.Lv_def1:
        lea     rax, [rip+s_def_namefmt]
        mov     [rip+name_fmt_ptr], rax
.Lv_ext:
        mov     rdi, [rip+ext_ptr]
        test    rdi, rdi
        jz      .Lv_def2
        cmp     byte ptr [rdi], '.'
        jne     .Lv_def2
        call    strlen
        cmp     rax, 2
        jb      .Lv_def2
        cmp     rax, 16
        ja      .Lv_def2
        xor     ecx, ecx
.Lv_slash:
        mov     al, [rdi+rcx]
        test    al, al
        jz      .Lv_tail
        cmp     al, '/'
        je      .Lv_def2
        inc     rcx
        jmp     .Lv_slash
.Lv_def2:
        lea     rax, [rip+s_def_ext]
        mov     [rip+ext_ptr], rax
.Lv_tail:
        mov     rax, [rip+tail_lines]
        test    rax, rax
        jns     .Lv_t1
        xor     eax, eax
.Lv_t1:
        cmp     rax, 16
        jbe     .Lv_t2
        mov     eax, 16
.Lv_t2:
        mov     [rip+tail_lines], rax
        mov     rax, [rip+lkset_tail]
        test    rax, rax
        jns     .Lv_t3
        xor     eax, eax
.Lv_t3:
        cmp     rax, 32
        jbe     .Lv_t4
        mov     eax, 32
.Lv_t4:
        mov     [rip+lkset_tail], rax
        xor     r9d, r9d
.Lv_c:
        cmp     r9, 4
        jae     .Lv_done
        lea     rax, [rip+col_ptr]
        mov     rdi, [rax+r9*8]
        test    rdi, rdi
        jnz     .Lv_c2
        lea     rax, [rip+col_defaults]
        mov     rdi, [rax+r9*8]
.Lv_c2:
        xor     eax, eax
        test    rdi, rdi
        jz      .Lv_cs
        call    lookup_color
.Lv_cs:
        lea     rcx, [rip+color_sgr]
        mov     [rcx+r9*8], rax
        inc     r9
        jmp     .Lv_c
.Lv_done:
        ret

# ---------------------------------------------------------------------
# read_conf_raw(rdi=dst[CONFMAX+1]) -> rax = length (NUL-terminated) / -1
# ---------------------------------------------------------------------
read_conf_raw:
        push    rbx
        push    r12
        push    r13
        mov     r13, rdi
        mov     eax, SYS_open
        lea     rdi, [rip+confpath]
        mov     esi, O_RDONLY|O_CLOEXEC
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Lrc_fail
        mov     rbx, rax
        xor     r12d, r12d
.Lrc_rd:
        mov     rdx, CONFMAX
        sub     rdx, r12
        jz      .Lrc_close
        mov     rsi, r13
        add     rsi, r12
        xor     eax, eax
        mov     rdi, rbx
        syscall
        cmp     rax, EINTR_NEG
        je      .Lrc_rd
        test    rax, rax
        jle     .Lrc_close
        add     r12, rax
        jmp     .Lrc_rd
.Lrc_close:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
        mov     byte ptr [r13+r12], 0
        mov     rax, r12
        jmp     .Lrc_out
.Lrc_fail:
        mov     rax, -1
.Lrc_out:
        pop     r13
        pop     r12
        pop     rbx
        ret

# load_config(): read lk.conf into confbuf; empty/missing => default_conf
load_config:
        lea     rdi, [rip+confbuf]
        call    read_conf_raw
        test    rax, rax
        jg      .Lld_out
        lea     rdi, [rip+confbuf]
        lea     rsi, [rip+default_conf]
        lea     rdx, [rip+confbuf+CONFMAX]
        call    bcopy_z
        mov     byte ptr [rax], 0
.Lld_out:
        ret

# build_conf_path(): confpath = $HOME/.config/logklerk/lk.conf ; tmppath = +".tmp"
build_conf_path:
        lea     rdi, [rip+confpath]
        mov     rsi, [rip+home_ptr]
        lea     rdx, [rip+confpath+PATHMAX-16]
        call    bcopy_z
        test    rax, rax
        jz      .Lbc_err
        mov     rdi, rax
        lea     rsi, [rip+s_conf_suffix]
        lea     rdx, [rip+confpath+PATHMAX-16]
        call    bcopy_z
        test    rax, rax
        jz      .Lbc_err
        mov     byte ptr [rax], 0
        lea     rdi, [rip+tmppath]
        lea     rsi, [rip+confpath]
        lea     rdx, [rip+tmppath+PATHMAX-8]
        call    bcopy_z
        test    rax, rax
        jz      .Lbc_err
        mov     rdi, rax
        lea     rsi, [rip+s_tmp_ext]
        lea     rdx, [rip+tmppath+PATHMAX-1]
        call    bcopy_z
        mov     byte ptr [rax], 0
        ret
.Lbc_err:
        DIE     m_dirlong, m_dirlong_len, 1

# ---------------------------------------------------------------------
# build_dir(): expand LK_DIR (leading "$HOME"/"~") into pathbuf, make sure it is
# absolute & ends with '/', store its length in dir_len.
# ---------------------------------------------------------------------
build_dir:
        push    rbx
        push    r12
        mov     rbx, [rip+dir_ptr]
        test    rbx, rbx
        jz      .Lbd_usedef
        cmp     byte ptr [rbx], 0
        jne     .Lbd_have
.Lbd_usedef:
        lea     rbx, [rip+s_default_dir]
.Lbd_have:
        mov     r12, rbx
        mov     rdi, rbx
        lea     rsi, [rip+s_homevar]
        call    starts_with
        test    eax, eax
        jz      .Lbd_tilde
        add     rbx, rcx
        jmp     .Lbd_chkrest
.Lbd_tilde:
        cmp     byte ptr [rbx], '~'
        jne     .Lbd_literal
        inc     rbx
.Lbd_chkrest:
        mov     al, [rbx]
        test    al, al
        jz      .Lbd_home
        cmp     al, '/'
        je      .Lbd_home
        mov     rbx, r12
        jmp     .Lbd_literal
.Lbd_home:
        mov     rsi, [rip+home_ptr]
        lea     rdi, [rip+pathbuf]
        lea     rdx, [rip+pathbuf+PATHMAX-PATH_RESERVE]
        call    bcopy_z
        test    rax, rax
        jz      .Lbd_err
        mov     rdi, rax
        mov     rsi, rbx
        lea     rdx, [rip+pathbuf+PATHMAX-PATH_RESERVE]
        call    bcopy_z
        jmp     .Lbd_tail
.Lbd_literal:
        lea     rdi, [rip+pathbuf]
        mov     rsi, rbx
        lea     rdx, [rip+pathbuf+PATHMAX-PATH_RESERVE]
        call    bcopy_z
.Lbd_tail:
        test    rax, rax
        jz      .Lbd_err
        mov     rdi, rax
        lea     rcx, [rip+pathbuf]
        cmp     rdi, rcx
        je      .Lbd_err
        cmp     byte ptr [rcx], '/'
        jne     .Lbd_rel
        cmp     byte ptr [rdi-1], '/'
        je      .Lbd_term
        mov     byte ptr [rdi], '/'
        inc     rdi
.Lbd_term:
        mov     byte ptr [rdi], 0
        sub     rdi, rcx
        mov     [rip+dir_len], rdi
        pop     r12
        pop     rbx
        ret
.Lbd_err:
        DIE     m_dirlong, m_dirlong_len, 1
.Lbd_rel:
        DIE     m_dirrel, m_dirrel_len, 1

# mkdir_p(rdi=buf, rsi=len): mkdir -p (mode 0700) for every '/' at index 1..len-1.
# Errors are ignored (real failures show up in open()).  CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
mkdir_p:
        mov     r10, rdi
        mov     r9, rsi
        mov     r8d, 1
.Lmk_l:
        cmp     r8, r9
        jae     .Lmk_d
        cmp     byte ptr [r10+r8], '/'
        jne     .Lmk_n
        mov     byte ptr [r10+r8], 0
        mov     eax, SYS_mkdir
        mov     rdi, r10
        mov     esi, 0700
        syscall
        mov     byte ptr [r10+r8], '/'
.Lmk_n:
        inc     r8
        jmp     .Lmk_l
.Lmk_d:
        ret

# init_config(): (re)load the whole configuration. Safe to call again on reload.
init_config:
        mov     qword ptr [rip+tax_count], 0
        mov     qword ptr [rip+dir_ptr], 0
        mov     qword ptr [rip+name_fmt_ptr], 0
        mov     qword ptr [rip+ext_ptr], 0
        lea     rax, [rip+col_ptr]
        mov     qword ptr [rax], 0
        mov     qword ptr [rax+8], 0
        mov     qword ptr [rax+16], 0
        mov     qword ptr [rax+24], 0
        mov     qword ptr [rip+tail_lines], 3
        mov     qword ptr [rip+lkset_tail], 3
        call    load_config
        call    parse_config
        call    validate_settings
        call    build_dir
        lea     rdi, [rip+pathbuf]
        mov     rsi, [rip+dir_len]
        call    mkdir_p
        ret

# ---------------------------------------------------------------------
# show_tail(edi=1 => print "logged into <file>" first)
# Show the last LK_TAIL_LINES lines of the active log file (read window
# TAILWIN from the end of the file). The newest line is prefixed with "[>] ".
# ---------------------------------------------------------------------
show_tail:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r15d, edi
        cmp     qword ptr [rip+tail_lines], 0
        je      .Lst_ret
        cmp     byte ptr [rip+curname], 0
        je      .Lst_ret
        lea     rdi, [rip+pathbuf]
        add     rdi, [rip+dir_len]
        lea     rsi, [rip+curname]
        lea     rdx, [rip+pathbuf+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lst_ret
        mov     byte ptr [rax], 0
        test    r15d, r15d
        jz      .Lst_open
        lea     rdi, [rip+s_loggedinto]
        call    out_cstr
        lea     rdi, [rip+pathbuf]
        call    out_cstr
        mov     edi, 10
        call    out_ch
.Lst_open:
        mov     eax, SYS_open
        lea     rdi, [rip+pathbuf]
        mov     esi, O_RDONLY|O_CLOEXEC|O_NOFOLLOW
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Lst_flush
        mov     rbx, rax
        mov     eax, SYS_lseek
        mov     rdi, rbx
        xor     esi, esi
        mov     edx, 2
        syscall
        test    rax, rax
        js      .Lst_closeflush
        mov     r12, rax
        xor     r13d, r13d
        cmp     r12, TAILWIN
        jbe     .Lst_seek
        mov     r13, r12
        sub     r13, TAILWIN
.Lst_seek:
        mov     eax, SYS_lseek
        mov     rdi, rbx
        mov     rsi, r13
        xor     edx, edx
        syscall
        xor     r14d, r14d
.Lst_rd:
        mov     rdx, TAILWIN
        sub     rdx, r14
        jz      .Lst_rdd
        lea     rsi, [rip+tailbuf]
        add     rsi, r14
        xor     eax, eax
        mov     rdi, rbx
        syscall
        cmp     rax, EINTR_NEG
        je      .Lst_rd
        test    rax, rax
        jle     .Lst_rdd
        add     r14, rax
        jmp     .Lst_rd
.Lst_rdd:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
        xor     r10d, r10d                  # p0 = start of the first complete line
        lea     rsi, [rip+tailbuf]
        test    r13, r13
        jz      .Lst_p0ok
        xor     ecx, ecx
.Lst_fnl:
        cmp     rcx, r14
        jae     .Lst_flush
        cmp     byte ptr [rsi+rcx], 10
        je      .Lst_fnl2
        inc     rcx
        jmp     .Lst_fnl
.Lst_fnl2:
        lea     r10, [rcx+1]
.Lst_p0ok:
        mov     r8, r14
        cmp     r8, r10
        jbe     .Lst_flush
        cmp     byte ptr [rsi+r8-1], 10
        jne     .Lst_col0
        dec     r8
.Lst_col0:
        xor     r11d, r11d
.Lst_cl:
        cmp     r11, [rip+tail_lines]
        jae     .Lst_print
        cmp     r8, r10
        jbe     .Lst_print
        mov     r9, r8
.Lst_sb:
        cmp     r9, r10
        jbe     .Lst_sbd
        cmp     byte ptr [rsi+r9-1], 10
        je      .Lst_sbd
        dec     r9
        jmp     .Lst_sb
.Lst_sbd:
        cmp     r9, r8
        jae     .Lst_skipe
        lea     rax, [rip+tl_s]
        mov     [rax+r11*8], r9
        lea     rax, [rip+tl_e]
        mov     [rax+r11*8], r8
        inc     r11
.Lst_skipe:
        cmp     r9, r10
        jbe     .Lst_print
        lea     r8, [r9-1]
        jmp     .Lst_cl
.Lst_print:
        mov     r12, r11
.Lst_pl:
        test    r12, r12
        jz      .Lst_flush
        dec     r12
        lea     rax, [rip+tl_s]
        mov     rsi, [rax+r12*8]
        lea     rax, [rip+tl_e]
        mov     rdx, [rax+r12*8]
        sub     rdx, rsi
        lea     rcx, [rip+tailbuf]
        add     rsi, rcx
        movzx   eax, byte ptr [rsi]
        sub     eax, '0'
        cmp     eax, 9
        ja      .Lst_pl
        mov     rbx, rsi
        mov     r13, rdx
        test    r12, r12
        jnz     .Lst_old
        lea     rdi, [rip+s_pfx_new]
        jmp     .Lst_pp
.Lst_old:
        lea     rdi, [rip+s_pfx_old]
.Lst_pp:
        call    out_cstr
        mov     rsi, rbx
        mov     rdx, r13
        call    print_row
        jmp     .Lst_pl
.Lst_closeflush:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
.Lst_flush:
        call    out_flush
.Lst_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# spawn_wait(): fork + execve("/bin/sh", exec_argv) + wait4.
# Result in last_status (exit code, or 128+signal). stdout is flushed first.
# ---------------------------------------------------------------------
spawn_wait:
        call    out_flush
        mov     eax, SYS_fork
        syscall
        test    rax, rax
        js      .Lsw2_err
        jz      .Lsw2_child
        mov     rdi, rax
.Lsw2_w:
        mov     eax, SYS_wait4
        lea     rsi, [rip+wstatus]
        xor     edx, edx
        xor     r10d, r10d
        syscall
        cmp     rax, EINTR_NEG
        je      .Lsw2_w
        test    rax, rax
        js      .Lsw2_err
        mov     eax, [rip+wstatus]
        mov     ecx, eax
        and     ecx, 0x7f
        jz      .Lsw2_exit
        add     ecx, 128
        mov     [rip+last_status], rcx
        ret
.Lsw2_exit:
        shr     eax, 8
        and     eax, 0xff
        mov     [rip+last_status], rax
        ret
.Lsw2_child:
        lea     rdi, [rip+s_bin_sh]
        lea     rsi, [rip+exec_argv]
        mov     rdx, [rip+envp_ptr]
        mov     eax, SYS_execve
        syscall
        mov     edi, 127
        mov     eax, SYS_exit
        syscall
.Lsw2_err:
        ERR     m_fork, m_fork_len
        mov     qword ptr [rip+last_status], 1
        ret

# run_shell_line(rdi=line cstr): sh -c "<line>"  (fallback when bash is unavailable)
run_shell_line:
        lea     rax, [rip+exec_argv]
        lea     rcx, [rip+s_sh_name]
        mov     [rax], rcx
        lea     rcx, [rip+s_dash_c]
        mov     [rax+8], rcx
        mov     [rax+16], rdi
        mov     qword ptr [rax+24], 0
        jmp     spawn_wait

# run_cli(): sh -c 'exec "$@"' lk <argv[1..]>  (original argument quoting stays intact)
run_cli:
        mov     rcx, [rip+argc]
        cmp     rcx, 65
        ja      .Lrc2_many
        lea     rdx, [rip+exec_argv]
        lea     rax, [rip+s_sh_name]
        mov     [rdx], rax
        lea     rax, [rip+s_dash_c]
        mov     [rdx+8], rax
        lea     rax, [rip+s_exec_arg]
        mov     [rdx+16], rax
        lea     rax, [rip+s_lk]
        mov     [rdx+24], rax
        mov     r8, [rip+argv_ptr]
        mov     r9d, 1
.Lrc2_l:
        cmp     r9, rcx
        jae     .Lrc2_end
        mov     rax, [r8+r9*8]
        mov     [rdx+r9*8+24], rax
        inc     r9
        jmp     .Lrc2_l
.Lrc2_end:
        mov     qword ptr [rdx+r9*8+24], 0
        jmp     spawn_wait
.Lrc2_many:
        ERR     m_toomany, m_toomany_len
        mov     qword ptr [rip+last_status], 2
        ret

# ---------------------------------------------------------------------
# probe_start(rdi=line cstr) -> rax = 1 the first word is a command/alias/
#   builtin/function (the line is NOW running), 0 plain text (nothing runs),
#   2 bash unavailable or fork/pipe failed (nothing runs).
# Starts  bash [-i] -c <s_probe_script> lk <line>  with a pipe on fd 3 and
# blocks until the script reports. The caller logs the entry right after
# this returns (while the command already runs) and then MUST call
# probe_finish() to reap the child.  "-i" (so ~/.bashrc aliases load) is
# only used when stdin is a TTY.
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
# ---------------------------------------------------------------------
probe_start:
        push    rbx
        push    r12
        mov     r12, rdi
        call    out_flush
        mov     eax, SYS_pipe2
        lea     rdi, [rip+pipefds]
        mov     esi, O_CLOEXEC
        syscall
        test    rax, rax
        js      .Lpb_fail
        lea     rdx, [rip+exec_argv]                # argv = bash [-i] -c script lk line
        lea     rax, [rip+s_bash_name]
        mov     [rdx], rax
        mov     ecx, 1
        cmp     qword ptr [rip+is_tty], 0
        je      .Lpb_noi
        lea     rax, [rip+s_dash_i]
        mov     [rdx+rcx*8], rax
        inc     ecx
.Lpb_noi:
        lea     rax, [rip+s_dash_c]
        mov     [rdx+rcx*8], rax
        inc     ecx
        lea     rax, [rip+s_probe_script]
        mov     [rdx+rcx*8], rax
        inc     ecx
        lea     rax, [rip+s_lk]
        mov     [rdx+rcx*8], rax
        inc     ecx
        mov     [rdx+rcx*8], r12
        inc     ecx
        mov     qword ptr [rdx+rcx*8], 0
        mov     eax, SYS_fork
        syscall
        test    rax, rax
        js      .Lpb_ferr
        jz      .Lpb_child
        mov     [rip+probe_pid], rax
        mov     eax, SYS_close                      # parent: drop the write end
        mov     edi, [rip+pipefds+4]
        syscall
        mov     qword ptr [rip+probe_res], 0
.Lpb_rd:
        xor     eax, eax                            # read 1 byte of the verdict
        mov     edi, [rip+pipefds]
        lea     rsi, [rip+probe_res]
        mov     edx, 1
        syscall
        cmp     rax, EINTR_NEG
        je      .Lpb_rd
        mov     ebx, 2                              # default: no verdict (EOF/error)
        cmp     rax, 1
        jne     .Lpb_closer
        movzx   eax, byte ptr [rip+probe_res]
        cmp     al, '1'
        jne     .Lpb_n1
        mov     ebx, 1
        jmp     .Lpb_closer
.Lpb_n1:
        cmp     al, '0'
        jne     .Lpb_closer
        xor     ebx, ebx
.Lpb_closer:
        mov     eax, SYS_close
        mov     edi, [rip+pipefds]
        syscall
        mov     rax, rbx
        pop     r12
        pop     rbx
        ret
.Lpb_child:
        mov     eax, SYS_dup2                       # pipe write end -> fd 3
        mov     edi, [rip+pipefds+4]
        mov     esi, 3
        syscall
        lea     rdi, [rip+s_bash_path]
        lea     rsi, [rip+exec_argv]
        mov     rdx, [rip+envp_ptr]
        mov     eax, SYS_execve
        syscall
        mov     edi, 127
        mov     eax, SYS_exit
        syscall
.Lpb_ferr:
        mov     eax, SYS_close
        mov     edi, [rip+pipefds]
        syscall
        mov     eax, SYS_close
        mov     edi, [rip+pipefds+4]
        syscall
.Lpb_fail:
        mov     qword ptr [rip+probe_pid], 0
        mov     eax, 2
        pop     r12
        pop     rbx
        ret

# probe_finish(): wait4 on the probe child -> last_status (same encoding as
# spawn_wait). No-op when there is no child.  CLOBBER: rax, rcx, rdx, rsi, rdi, r10, r11
probe_finish:
        mov     rdi, [rip+probe_pid]
        test    rdi, rdi
        jz      .Lpf_ret
        mov     qword ptr [rip+probe_pid], 0
        jmp     .Lsw2_w                             # reuse spawn_wait's wait loop
.Lpf_ret:
        ret

# do_cd(rdi=argument cstr): builtin cd. empty/"~" => $HOME, "~/x" => $HOME/x
do_cd:
        push    rbx
        mov     rbx, rdi
        cmp     byte ptr [rbx], 0
        je      .Lcd_home
        cmp     byte ptr [rbx], '~'
        jne     .Lcd_lit
        cmp     byte ptr [rbx+1], 0
        je      .Lcd_home
        cmp     byte ptr [rbx+1], '/'
        jne     .Lcd_lit
        lea     rdi, [rip+pbuf2]
        mov     rsi, [rip+home_ptr]
        lea     rdx, [rip+pbuf2+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lcd_err
        mov     rdi, rax
        lea     rsi, [rbx+1]
        lea     rdx, [rip+pbuf2+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lcd_err
        mov     byte ptr [rax], 0
        lea     rdi, [rip+pbuf2]
        jmp     .Lcd_go
.Lcd_home:
        mov     rdi, [rip+home_ptr]
        jmp     .Lcd_go
.Lcd_lit:
        mov     rdi, rbx
.Lcd_go:
        mov     eax, SYS_chdir
        syscall
        test    rax, rax
        jns     .Lcd_ok
.Lcd_err:
        ERR     m_cd, m_cd_len
.Lcd_ok:
        pop     rbx
        ret

# ---------------------------------------------------------------------
# lkc (log reader) lives in its own module: src/modules/lkc.asm
# ---------------------------------------------------------------------
        .include "modules/lkc.asm"

# ---------------------------------------------------------------------
# is_tax_hdr(rdi=start (after spaces), rsi=end of line) -> eax 1 if "[taxonomy]"
# CLOBBER: rax, rdx, rdi
# ---------------------------------------------------------------------
is_tax_hdr:
        lea     rdx, [rip+s_sec_taxonomy]
.Lth_l:
        mov     al, [rdx]
        test    al, al
        jz      .Lth_tail
        cmp     rdi, rsi
        jae     .Lth_no
        cmp     al, [rdi]
        jne     .Lth_no
        inc     rdi
        inc     rdx
        jmp     .Lth_l
.Lth_tail:
        cmp     rdi, rsi
        jae     .Lth_yes
        mov     al, [rdi]
        cmp     al, ' '
        je      .Lth_t
        cmp     al, 9
        je      .Lth_t
        cmp     al, 13
        jne     .Lth_no
.Lth_t:
        inc     rdi
        jmp     .Lth_tail
.Lth_yes:
        mov     eax, 1
        ret
.Lth_no:
        xor     eax, eax
        ret

# line_key_match(rdi=start, rsi=end of line, rdx=key cstr) -> eax: "key[ws]=" at line start
# CLOBBER: rax, rdx, rdi
line_key_match:
.Lkm_l:
        mov     al, [rdx]
        test    al, al
        jz      .Lkm_after
        cmp     rdi, rsi
        jae     .Lkm_no
        cmp     al, [rdi]
        jne     .Lkm_no
        inc     rdi
        inc     rdx
        jmp     .Lkm_l
.Lkm_after:
        cmp     rdi, rsi
        jae     .Lkm_no
        mov     al, [rdi]
        cmp     al, '='
        je      .Lkm_yes
        cmp     al, ' '
        je      .Lkm_w
        cmp     al, 9
        jne     .Lkm_no
.Lkm_w:
        inc     rdi
        jmp     .Lkm_after
.Lkm_yes:
        mov     eax, 1
        ret
.Lkm_no:
        xor     eax, eax
        ret

# keychar_ok(dil) -> eax 1 if [A-Za-z0-9_-].  CLOBBER: eax
keychar_ok:
        movzx   eax, dil
        cmp     al, '-'
        je      .Lkc2_yes
        cmp     al, '_'
        je      .Lkc2_yes
        cmp     al, '0'
        jb      .Lkc2_no
        cmp     al, '9'
        jbe     .Lkc2_yes
        cmp     al, 'A'
        jb      .Lkc2_no
        cmp     al, 'Z'
        jbe     .Lkc2_yes
        cmp     al, 'a'
        jb      .Lkc2_no
        cmp     al, 'z'
        jbe     .Lkc2_yes
.Lkc2_no:
        xor     eax, eax
        ret
.Lkc2_yes:
        mov     eax, 1
        ret

# ---------------------------------------------------------------------
# cmd_lkset(rdi=argumen cstr, boleh ditulis): "taxonomy key="Value""
# Rewrite lk.conf (temp file + atomic rename), then RELOAD the config.
# ---------------------------------------------------------------------
cmd_lkset:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        call    skip_ws
        mov     rbx, rdi
        lea     rsi, [rip+s_taxonomy]
        call    starts_with
        test    eax, eax
        jz      .Lls_usage
        add     rbx, rcx
        mov     al, [rbx]
        cmp     al, ' '
        je      .Lls_a
        cmp     al, 9
        jne     .Lls_usage
.Lls_a:
        mov     rdi, rbx
        call    skip_ws
        mov     rbx, rdi
        mov     r12, rbx                    # start of key
.Lls_k:
        mov     al, [rbx]
        test    al, al
        jz      .Lls_usage
        cmp     al, '='
        je      .Lls_keq
        movzx   edi, al
        call    keychar_ok
        test    eax, eax
        jz      .Lls_usage
        inc     rbx
        jmp     .Lls_k
.Lls_keq:
        mov     r13, rbx
        sub     r13, r12
        jz      .Lls_usage
        cmp     r13, 32
        ja      .Lls_usage
        mov     byte ptr [rbx], 0
        inc     rbx
        mov     rdi, rbx
        call    skip_ws
        mov     rbx, rdi
        cmp     byte ptr [rbx], '"'
        jne     .Lls_v1
        inc     rbx
.Lls_v1:
        mov     r14, rbx                    # start of value
        mov     rdi, rbx
        call    strlen
        lea     r15, [rbx+rax]
.Lls_vt:
        cmp     r15, r14
        jbe     .Lls_vd
        mov     al, [r15-1]
        cmp     al, ' '
        je      .Lls_vtz
        cmp     al, 9
        jne     .Lls_vq
.Lls_vtz:
        dec     r15
        jmp     .Lls_vt
.Lls_vq:
        cmp     byte ptr [r15-1], '"'
        jne     .Lls_vd
        dec     r15
.Lls_vd:
        mov     byte ptr [r15], 0
        mov     rax, r15
        sub     rax, r14
        jz      .Lls_usage
        cmp     rax, 128
        ja      .Lls_usage
        mov     rsi, r14
.Lls_vc:
        mov     al, [rsi]
        test    al, al
        jz      .Lls_vok
        cmp     al, 0x20
        jb      .Lls_usage
        cmp     al, '"'
        je      .Lls_usage
        inc     rsi
        jmp     .Lls_vc
.Lls_vok:
        lea     rsi, [rip+s_reserved]
.Lls_rs:
        cmp     byte ptr [rsi], 0
        je      .Lls_build
        mov     rdi, r12
        call    streq
        test    eax, eax
        jnz     .Lls_resv
.Lls_rs2:
        cmp     byte ptr [rsi], 0
        je      .Lls_rs3
        inc     rsi
        jmp     .Lls_rs2
.Lls_rs3:
        inc     rsi
        jmp     .Lls_rs
.Lls_build:
        # new entry:  key="value"\n  in entrybuf
        lea     rdi, [rip+entrybuf]
        mov     rsi, r12
        lea     rdx, [rip+entrybuf+ENTRYMAX-8]
        call    bcopy_z
        mov     rdi, rax
        mov     word ptr [rdi], 0x223d      # ="
        add     rdi, 2
        mov     rsi, r14
        lea     rdx, [rip+entrybuf+ENTRYMAX-8]
        call    bcopy_z
        mov     rdi, rax
        mov     byte ptr [rdi], '"'
        mov     byte ptr [rdi+1], 10
        add     rdi, 2
        lea     rax, [rip+entrybuf]
        sub     rdi, rax
        mov     [rip+ks_elen], rdi
        # read the raw config (or the default)
        lea     rdi, [rip+rawbuf]
        call    read_conf_raw
        test    rax, rax
        jg      .Lls_have
        lea     rdi, [rip+rawbuf]
        lea     rsi, [rip+default_conf]
        lea     rdx, [rip+rawbuf+CONFMAX]
        call    bcopy_z
        mov     byte ptr [rax], 0
        lea     rcx, [rip+rawbuf]
        sub     rax, rcx
.Lls_have:
        mov     [rip+ks_rawlen], rax
        lea     r13, [rip+rawbuf]
        add     r13, rax                    # end of raw
        lea     rbx, [rip+rawbuf]
        xor     r14d, r14d                  # in_tax
        mov     qword ptr [rip+ks_keyfound], 0
        mov     qword ptr [rip+ks_taxfound], 0
        mov     qword ptr [rip+ks_inspos], 0
.Lls_sc:
        cmp     rbx, r13
        jae     .Lls_sc_done
        mov     r8, rbx                     # start of line
        mov     rsi, rbx
.Lls_se:
        cmp     rsi, r13
        jae     .Lls_see
        cmp     byte ptr [rsi], 10
        je      .Lls_see
        inc     rsi
        jmp     .Lls_se
.Lls_see:
        mov     r9, rsi                     # end of line
        lea     r10, [rsi+1]
        cmp     rsi, r13
        jb      .Lls_sn
        mov     r10, rsi
.Lls_sn:
        mov     rbx, r10                    # next line
        mov     rsi, r8
.Lls_ts:
        cmp     rsi, r9
        jae     .Lls_sc
        mov     al, [rsi]
        cmp     al, ' '
        je      .Lls_tsn
        cmp     al, 9
        je      .Lls_tsn
        cmp     al, 13
        jne     .Lls_have2
.Lls_tsn:
        inc     rsi
        jmp     .Lls_ts
.Lls_have2:
        cmp     al, '['
        jne     .Lls_body
        mov     rdi, rsi
        mov     rsi, r9
        call    is_tax_hdr
        xor     r14d, r14d
        test    eax, eax
        jz      .Lls_sc
        mov     r14d, 1
        mov     qword ptr [rip+ks_taxfound], 1
        mov     [rip+ks_inspos], rbx
        jmp     .Lls_sc
.Lls_body:
        test    r14d, r14d
        jz      .Lls_sc
        mov     [rip+ks_inspos], rbx
        cmp     qword ptr [rip+ks_keyfound], 0
        jne     .Lls_sc
        cmp     al, '#'
        je      .Lls_sc
        cmp     al, ';'
        je      .Lls_sc
        mov     rdi, rsi
        mov     rsi, r9
        mov     rdx, r12
        call    line_key_match
        test    eax, eax
        jz      .Lls_sc
        mov     [rip+ks_repls], r8
        mov     [rip+ks_reple], rbx
        mov     qword ptr [rip+ks_keyfound], 1
        jmp     .Lls_sc
.Lls_sc_done:
        lea     rdi, [rip+newbuf]
        cmp     qword ptr [rip+ks_keyfound], 0
        jne     .Lls_caseA
        cmp     qword ptr [rip+ks_taxfound], 0
        jne     .Lls_caseB
        # --- C: no [taxonomy] section
        lea     rsi, [rip+rawbuf]
        mov     rcx, [rip+ks_rawlen]
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        cmp     qword ptr [rip+ks_rawlen], 0
        je      .Lls_c2
        cmp     byte ptr [rdi-1], 10
        je      .Lls_c2
        lea     rsi, [rip+s_nl]
        mov     ecx, 1
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
.Lls_c2:
        lea     rsi, [rip+s_taxhdr_nl]
        mov     ecx, s_taxhdr_nl_len
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        lea     rsi, [rip+entrybuf]
        mov     rcx, [rip+ks_elen]
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        jmp     .Lls_write
.Lls_caseA:
        lea     rsi, [rip+rawbuf]
        mov     rcx, [rip+ks_repls]
        sub     rcx, rsi
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        lea     rsi, [rip+entrybuf]
        mov     rcx, [rip+ks_elen]
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        mov     rsi, [rip+ks_reple]
        lea     rcx, [rip+rawbuf]
        add     rcx, [rip+ks_rawlen]
        sub     rcx, rsi
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        jmp     .Lls_write
.Lls_caseB:
        lea     rsi, [rip+rawbuf]
        mov     rcx, [rip+ks_inspos]
        sub     rcx, rsi
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        mov     rax, [rip+ks_inspos]
        cmp     byte ptr [rax-1], 10
        je      .Lls_b2
        lea     rsi, [rip+s_nl]
        mov     ecx, 1
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
.Lls_b2:
        lea     rsi, [rip+entrybuf]
        mov     rcx, [rip+ks_elen]
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
        mov     rsi, [rip+ks_inspos]
        lea     rcx, [rip+rawbuf]
        add     rcx, [rip+ks_rawlen]
        sub     rcx, rsi
        call    bcopy_n
        test    rax, rax
        jz      .Lls_big
        mov     rdi, rax
.Lls_write:
        lea     rax, [rip+newbuf]
        sub     rdi, rax
        mov     r13, rdi                    # length of the new config
        cmp     r13, CONFMAX
        ja      .Lls_big
        lea     rdi, [rip+confpath]
        call    strlen
        lea     rdi, [rip+confpath]
        mov     rsi, rax
        call    mkdir_p
        mov     eax, SYS_unlink
        lea     rdi, [rip+tmppath]
        syscall
        mov     eax, SYS_open
        lea     rdi, [rip+tmppath]
        mov     esi, O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW
        mov     edx, 0600
        syscall
        test    rax, rax
        js      .Lls_wfail
        mov     r12, rax
        mov     rdi, r12
        lea     rsi, [rip+newbuf]
        mov     rdx, r13
        call    write_all
        mov     r14, rax
        mov     eax, SYS_close
        mov     rdi, r12
        syscall
        test    r14, r14
        jnz     .Lls_wfail_unl
        mov     eax, SYS_rename
        lea     rdi, [rip+tmppath]
        lea     rsi, [rip+confpath]
        syscall
        test    rax, rax
        js      .Lls_wfail_unl
        call    init_config                 # RELOAD
        lea     rdi, [rip+s_taxblock]
        call    out_cstr
        mov     r12, [rip+tax_count]
        mov     rbx, r12
        sub     rbx, [rip+lkset_tail]
        jns     .Lls_pb
        xor     ebx, ebx
.Lls_pb:
        cmp     rbx, r12
        jae     .Lls_pdone
        lea     rax, [rip+tax_keys]
        mov     rdi, [rax+rbx*8]
        call    out_cstr
        lea     rsi, [rip+s_eqq]
        mov     edx, 2
        call    out_bytes
        lea     rax, [rip+tax_vals]
        mov     rdi, [rax+rbx*8]
        call    out_cstr
        lea     rsi, [rip+s_qnl]
        mov     edx, 2
        call    out_bytes
        inc     rbx
        jmp     .Lls_pb
.Lls_pdone:
        call    out_flush
        jmp     .Lls_ret
.Lls_wfail_unl:
        mov     eax, SYS_unlink
        lea     rdi, [rip+tmppath]
        syscall
.Lls_wfail:
        ERR     m_conf_wr, m_conf_wr_len
        jmp     .Lls_ret
.Lls_big:
        ERR     m_conf_big, m_conf_big_len
        jmp     .Lls_ret
.Lls_resv:
        ERR     m_reserved, m_reserved_len
        jmp     .Lls_ret
.Lls_usage:
        ERR     m_lkset_usage, m_lkset_usage_len
.Lls_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# getc() -> eax = byte (0..255) / -1 (EOF).  Buffered read(0).
# ---------------------------------------------------------------------
getc:
        mov     rax, [rip+in_pos]
        cmp     rax, [rip+in_len]
        jb      .Lgc_have
        xor     eax, eax
        xor     edi, edi
        lea     rsi, [rip+inbuf]
        mov     edx, INBUF_SZ
        syscall
        cmp     rax, EINTR_NEG
        je      getc
        test    rax, rax
        jle     .Lgc_eof
        mov     [rip+in_len], rax
        xor     eax, eax
.Lgc_have:
        lea     rdx, [rip+inbuf]
        movzx   edx, byte ptr [rdx+rax]
        inc     rax
        mov     [rip+in_pos], rax
        mov     eax, edx
        ret
.Lgc_eof:
        mov     qword ptr [rip+in_len], 0
        mov     qword ptr [rip+in_pos], 0
        mov     eax, -1
        ret

# read_line() -> rax = length (linebuf NUL-terminated) / -1 EOF.
# Lines > LINEMAX: the excess is dropped, nothing is ever written outside linebuf.
read_line:
        push    rbx
        xor     ebx, ebx
        mov     qword ptr [rip+line_trunc], 0
.Lrl_c:
        call    getc
        cmp     eax, -1
        je      .Lrl_eof
        cmp     eax, 10
        je      .Lrl_done
        cmp     ebx, LINEMAX
        jae     .Lrl_drop
        lea     rdx, [rip+linebuf]
        mov     [rdx+rbx], al
        inc     ebx
        jmp     .Lrl_c
.Lrl_drop:
        mov     qword ptr [rip+line_trunc], 1
        jmp     .Lrl_c
.Lrl_eof:
        test    ebx, ebx
        jnz     .Lrl_done
        mov     rax, -1
        pop     rbx
        ret
.Lrl_done:
        lea     rdx, [rip+linebuf]
        test    ebx, ebx
        jz      .Lrl_term
        cmp     byte ptr [rdx+rbx-1], 13
        jne     .Lrl_term
        dec     ebx
.Lrl_term:
        mov     byte ptr [rdx+rbx], 0
        mov     eax, ebx
        pop     rbx
        ret

# ---------------------------------------------------------------------
# handle_line(rdi=line NUL-terminated & trimmed, rsi=len>0) -> eax=1 when the
# interactive loop must stop.  Also used by CLI mode (cli_flag=1).
#
# Classification of the first token (kind):
#   1 exit/quit   2 "lk" itself   3 lkc   4 lkset   6 cd (builtin)
#   5 taxonomy key   7 text in taxonomy mode   0 shell command / plain text
# Always LOG while/before the line runs => lkc sees its own line.
# ---------------------------------------------------------------------
.macro EMITL tag, ctx
        lea     rdi, [rip+\tag]
        lea     rsi, [rip+\ctx]
        mov     rdx, r14
        mov     rcx, r15
        call    emit_entry
        test    rax, rax
        jnz     .Lhl_fatal
.endm

handle_line:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r14, rdi
        mov     r15, rsi
.Lhl_top:
        xor     ecx, ecx
.Lhl_t1:
        cmp     rcx, r15
        jae     .Lhl_t2
        mov     al, [r14+rcx]
        cmp     al, ' '
        je      .Lhl_t2
        cmp     al, 9
        je      .Lhl_t2
        inc     rcx
        jmp     .Lhl_t1
.Lhl_t2:
        mov     [rip+h_toklen], rcx
        lea     r12, [r14+rcx]
        mov     r13, r15
        sub     r13, rcx
.Lhl_t3:
        test    r13, r13
        jz      .Lhl_t4
        mov     al, [r12]
        cmp     al, ' '
        je      .Lhl_t3s
        cmp     al, 9
        jne     .Lhl_t4
.Lhl_t3s:
        inc     r12
        dec     r13
        jmp     .Lhl_t3
.Lhl_t4:
        mov     rcx, [rip+h_toklen]
        mov     al, [r14+rcx]
        mov     [rip+h_savech], al
        mov     byte ptr [r14+rcx], 0       # first token becomes a temporary cstr
        xor     ebx, ebx
        cmp     qword ptr [rip+cli_flag], 0
        jne     .Lhl_nolk
        mov     rdi, r14
        lea     rsi, [rip+s_lk]
        call    streq
        test    eax, eax
        jz      .Lhl_nolk
        test    r13, r13
        jnz     .Lhl_strip
        mov     ebx, 2
        jmp     .Lhl_cls_done
.Lhl_strip:                                 # "lk gg x" => process "gg x" (no recursion)
        mov     r14, r12
        mov     r15, r13
        jmp     .Lhl_top
.Lhl_nolk:
        cmp     qword ptr [rip+cli_flag], 0
        jne     .Lhl_cmds
        test    r13, r13
        jnz     .Lhl_cmds
        mov     rdi, r14
        lea     rsi, [rip+s_exit]
        call    streq
        test    eax, eax
        jnz     .Lhl_k1
        mov     rdi, r14
        lea     rsi, [rip+s_quit]
        call    streq
        test    eax, eax
        jz      .Lhl_cmds
.Lhl_k1:
        mov     ebx, 1
        jmp     .Lhl_cls_done
.Lhl_cmds:
        mov     rdi, r14
        lea     rsi, [rip+s_lkc]
        call    streq
        test    eax, eax
        jz      .Lhl_c2
        mov     ebx, 3
        jmp     .Lhl_cls_done
.Lhl_c2:
        mov     rdi, r14
        lea     rsi, [rip+s_lkset]
        call    streq
        test    eax, eax
        jz      .Lhl_c3
        mov     ebx, 4
        jmp     .Lhl_cls_done
.Lhl_c3:
        cmp     qword ptr [rip+cli_flag], 0
        jne     .Lhl_c4
        mov     rdi, r14
        lea     rsi, [rip+s_cd]
        call    streq
        test    eax, eax
        jz      .Lhl_c4
        mov     ebx, 6
        jmp     .Lhl_cls_done
.Lhl_c4:
        mov     rdi, r14
        call    tax_lookup
        test    rax, rax
        jz      .Lhl_c5
        mov     [rip+h_ctx], rax
        mov     ebx, 5
        jmp     .Lhl_cls_done
.Lhl_c5:
        cmp     qword ptr [rip+cli_flag], 0
        jne     .Lhl_cls_done
        cmp     byte ptr [rip+mode_key], 0
        je      .Lhl_cls_done
        mov     ebx, 7
.Lhl_cls_done:
        cmp     ebx, 5                      # kind 5 needs the token to stay a cstr
        je      .Lhl_dispatch
        mov     rcx, [rip+h_toklen]
        mov     al, [rip+h_savech]
        mov     [r14+rcx], al
.Lhl_dispatch:
        cmp     ebx, 1
        je      .Lhl_exit
        cmp     ebx, 2
        je      .Lhl_lk
        cmp     ebx, 3
        je      .Lhl_lkc
        cmp     ebx, 4
        je      .Lhl_lkset
        cmp     ebx, 5
        je      .Lhl_tax
        cmp     ebx, 6
        je      .Lhl_cd
        cmp     ebx, 7
        je      .Lhl_mode
        jmp     .Lhl_plain
.Lhl_exit:
        EMITL   s_lk, s_commands
        xor     edi, edi
        call    show_tail
        mov     eax, 1
        jmp     .Lhl_ret
.Lhl_lk:
        cmp     byte ptr [rip+mode_key], 0
        je      .Lhl_lk2
        EMITL   s_lk, s_lktags
        mov     byte ptr [rip+mode_key], 0
        jmp     .Lhl_tail0
.Lhl_lk2:
        EMITL   s_lk, s_commands
        jmp     .Lhl_tail0
.Lhl_lkc:
        EMITL   s_lk, s_commands
        mov     rdi, r12
        call    cmd_lkc
        jmp     .Lhl_tail0
.Lhl_lkset:
        EMITL   s_lkset, s_taxonomy
        mov     rdi, r12
        call    cmd_lkset
        jmp     .Lhl_done0
.Lhl_tax:
        test    r13, r13
        jnz     .Lhl_oneshot
        cmp     qword ptr [rip+cli_flag], 0
        je      .Lhl_sw
        ERR     m_noact, m_noact_len
        mov     qword ptr [rip+exit_code], 2
        jmp     .Lhl_done0
.Lhl_sw:                                    # enter taxonomy mode
        EMITL   s_lk, s_lktags
        lea     rdi, [rip+mode_key]
        mov     rsi, r14
        lea     rdx, [rip+mode_key+63]
        call    bcopy_z
        test    rax, rax
        jnz     .Lhl_sw2
        lea     rax, [rip+mode_key+63]
.Lhl_sw2:
        mov     byte ptr [rax], 0
        mov     edi, 1
        call    show_tail
        jmp     .Lhl_done0
.Lhl_oneshot:                               # "gg what is linux"
        mov     rdi, r14
        mov     rsi, [rip+h_ctx]
        mov     rdx, r12
        mov     rcx, r13
        call    emit_entry
        test    rax, rax
        jnz     .Lhl_fatal
        mov     rcx, [rip+h_toklen]
        mov     al, [rip+h_savech]
        mov     [r14+rcx], al
        jmp     .Lhl_tail0
.Lhl_cd:
        EMITL   s_none, s_bash
        cmp     qword ptr [rip+line_trunc], 0
        jne     .Lhl_skiprun
        mov     rdi, r12
        call    do_cd
        jmp     .Lhl_tail0
.Lhl_mode:
        lea     rdi, [rip+mode_key]
        call    tax_lookup
        test    rax, rax
        jnz     .Lhl_mode2
        mov     byte ptr [rip+mode_key], 0
        jmp     .Lhl_plain
.Lhl_mode2:
        mov     [rip+h_ctx], rax                    # context of the active taxonomy key
        xor     ebx, ebx                            # ebx = probe verdict (default: plain text)
        cmp     qword ptr [rip+line_trunc], 0
        jne     .Lhl_mlog                           # truncated line: log only, never run
        mov     rdi, r14
        call    probe_start                         # runs the line if its 1st word is a command
        mov     ebx, eax
.Lhl_mlog:
        lea     rdi, [rip+mode_key]
        mov     rsi, [rip+h_ctx]
        mov     rdx, r14
        mov     rcx, r15
        call    emit_entry
        test    rax, rax
        jnz     .Lhl_fatal_reap
        call    probe_finish
        jmp     .Lhl_tail0
.Lhl_plain:
        cmp     qword ptr [rip+cli_flag], 0
        jne     .Lhl_cliplain
        cmp     qword ptr [rip+line_trunc], 0
        jne     .Lhl_trunclog
        mov     rdi, r14
        call    probe_start                         # runs the line if its 1st word is a command
        mov     ebx, eax
        lea     rdi, [rip+s_none]
        lea     rsi, [rip+s_bash]
        test    ebx, ebx
        jnz     .Lhl_pl_log
        lea     rsi, [rip+s_empty]                  # plain text => note: tags "none", empty context
.Lhl_pl_log:
        mov     rdx, r14
        mov     rcx, r15
        call    emit_entry
        test    rax, rax
        jnz     .Lhl_fatal_reap
        call    probe_finish
        cmp     ebx, 2                              # bash unavailable => fall back to /bin/sh
        jne     .Lhl_tail0
        mov     rdi, r14
        call    run_shell_line
        jmp     .Lhl_tail0
.Lhl_trunclog:
        EMITL   s_none, s_bash
.Lhl_skiprun:
        ERR     m_trunc, m_trunc_len
        jmp     .Lhl_tail0
.Lhl_cliplain:
        EMITL   s_none, s_bash
        call    run_cli
        mov     rax, [rip+last_status]
        mov     [rip+exit_code], rax
.Lhl_tail0:
        xor     edi, edi
        call    show_tail
.Lhl_done0:
        xor     eax, eax
        jmp     .Lhl_ret
.Lhl_fatal_reap:
        call    probe_finish
.Lhl_fatal:
        mov     qword ptr [rip+exit_code], 1
        mov     eax, 1
.Lhl_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# out_prompt(): "lk> " or "lk [[Context]] > "
out_prompt:
        push    rbx
        cmp     byte ptr [rip+mode_key], 0
        jne     .Lop_m
.Lop_n:
        lea     rdi, [rip+s_prompt]
        call    out_cstr
        jmp     .Lop_r
.Lop_m:
        lea     rdi, [rip+mode_key]
        call    tax_lookup
        test    rax, rax
        jnz     .Lop_m2
        mov     byte ptr [rip+mode_key], 0
        jmp     .Lop_n
.Lop_m2:
        mov     rbx, rax
        lea     rdi, [rip+s_pm1]
        call    out_cstr
        mov     rdi, rbx
        call    out_cstr
        lea     rdi, [rip+s_pm2]
        call    out_cstr
.Lop_r:
        pop     rbx
        ret

# ---------------------------------------------------------------------
# interactive(): read stdin loop -> handle_line.  Prompt only on a TTY.
# ---------------------------------------------------------------------
interactive:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     eax, SYS_ioctl              # TCGETS on stdin
        xor     edi, edi
        mov     esi, 0x5401
        lea     rdx, [rip+termios]
        syscall
        xor     r12d, r12d
        test    rax, rax
        jnz     .Lia_loop
        mov     r12d, 1
        mov     [rip+is_tty], r12                   # remember: stdin is a TTY
.Lia_loop:
        test    r12d, r12d
        jz      .Lia_read
        call    out_prompt
        call    out_flush
.Lia_read:
        call    read_line
        test    rax, rax
        js      .Lia_end
        mov     r13, rax
        lea     r14, [rip+linebuf]
.Lia_tl:
        test    r13, r13
        jz      .Lia_loop
        mov     al, [r14]
        cmp     al, ' '
        je      .Lia_tl_s
        cmp     al, 9
        jne     .Lia_tr
.Lia_tl_s:
        inc     r14
        dec     r13
        jmp     .Lia_tl
.Lia_tr:
        mov     al, [r14+r13-1]
        cmp     al, ' '
        je      .Lia_tr_s
        cmp     al, 9
        jne     .Lia_go
.Lia_tr_s:
        dec     r13
        jmp     .Lia_tr
.Lia_go:
        mov     byte ptr [r14+r13], 0
        mov     rdi, r14
        mov     rsi, r13
        call    handle_line
        test    eax, eax
        jz      .Lia_loop
.Lia_end:
        call    out_flush
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# join_args() -> rax = length; actbuf = argv[1..] separated by spaces (truncated at ACTMAX)
join_args:
        push    r13
        lea     rdi, [rip+actbuf]
        mov     r13d, 1
.Lja_arg:
        cmp     r13, [rip+argc]
        jae     .Lja_done
        lea     rax, [rip+actbuf]
        cmp     rdi, rax
        je      .Lja_nosp
        lea     rax, [rip+actbuf+ACTMAX]
        cmp     rdi, rax
        jae     .Lja_trunc
        mov     byte ptr [rdi], ' '
        inc     rdi
.Lja_nosp:
        mov     rax, [rip+argv_ptr]
        mov     rsi, [rax+r13*8]
        lea     rdx, [rip+actbuf+ACTMAX]
        call    bcopy_z
        test    rax, rax
        jz      .Lja_trunc
        mov     rdi, rax
        inc     r13
        jmp     .Lja_arg
.Lja_trunc:
        lea     rdi, [rip+actbuf+ACTMAX]
.Lja_done:
        mov     byte ptr [rdi], 0
        lea     rax, [rip+actbuf]
        sub     rdi, rax
        mov     rax, rdi
        pop     r13
        ret

# =====================================================================
_start:
        cld
        mov     rax, [rsp]
        mov     [rip+argc], rax
        lea     rcx, [rsp+8]
        mov     [rip+argv_ptr], rcx
        lea     rcx, [rsp+rax*8+16]
        mov     [rip+envp_ptr], rcx

        lea     rdi, [rip+s_home_eq]
        mov     rsi, [rip+envp_ptr]
        call    getenv
        test    rax, rax
        jnz     .Lst_home
        DIE     m_nohome, m_nohome_len, 1
.Lst_home:
        mov     [rip+home_ptr], rax

        cmp     qword ptr [rip+argc], 2
        jb      .Lst_cfg
        mov     rax, [rip+argv_ptr]
        mov     rdi, [rax+8]
        lea     rsi, [rip+s_opt_h]
        call    streq
        test    eax, eax
        jnz     .Lst_help
        mov     rax, [rip+argv_ptr]
        mov     rdi, [rax+8]
        lea     rsi, [rip+s_opt_help]
        call    streq
        test    eax, eax
        jz      .Lst_cfg
.Lst_help:
        mov     edi, 1
        lea     rsi, [rip+m_usage]
        mov     edx, m_usage_len
        call    write_all
        xor     edi, edi
        jmp     .Lst_exit

.Lst_cfg:
        mov     eax, SYS_ioctl              # stdout is a TTY? => color
        mov     edi, 1
        mov     esi, 0x5401
        lea     rdx, [rip+termios]
        syscall
        test    rax, rax
        jnz     .Lst_nc
        mov     qword ptr [rip+color_on], 1
        lea     rdi, [rip+s_nocolor_eq]     # NO_COLOR=non-empty => disable
        mov     rsi, [rip+envp_ptr]
        call    getenv
        test    rax, rax
        jz      .Lst_nc
        cmp     byte ptr [rax], 0
        je      .Lst_nc
        mov     qword ptr [rip+color_on], 0
.Lst_nc:
        call    build_conf_path
        call    init_config
        cmp     qword ptr [rip+argc], 1
        ja      .Lst_cli
        call    interactive
        jmp     .Lst_fin
.Lst_cli:
        call    join_args
        test    rax, rax
        jnz     .Lst_cli2
        mov     edi, 2
        lea     rsi, [rip+m_usage]
        mov     edx, m_usage_len
        call    write_all
        mov     qword ptr [rip+exit_code], 2
        jmp     .Lst_fin
.Lst_cli2:
        mov     qword ptr [rip+cli_flag], 1
        mov     rsi, rax
        lea     rdi, [rip+actbuf]
        call    handle_line
.Lst_fin:
        call    out_flush
        mov     rdi, [rip+exit_code]
.Lst_exit:
        mov     eax, SYS_exit
        syscall

        .section .note.GNU-stack,"",@progbits
