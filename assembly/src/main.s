# =====================================================================
#  LogKlerk Assembly CSV Version  v0.0.1
#  x86-64 Linux | GNU as (Intel syntax) | no libc, pure syscalls
#
#  Build :  as --64 -g lk.s -o lk.o
#           ld -z noexecstack -z relro -z now -o lk lk.o
#
#  INTERNAL REGISTER CONVENTION (same as System V AMD64)
#    arguments    : rdi, rsi, rdx, rcx, r8, r9
#    return       : rax
#    callee-saved : rbx, rbp, r12-r15  (functions using them MUST push/pop)
#    caller-saved : rax, rcx, rdx, rsi, rdi, r8-r11 (may be clobbered by functions)
#    `syscall` clobbers: rax (return), rcx, r11. The rest are preserved.
#    Each function lists "CLOBBER" = caller-saved registers clobbered.
#
#  Stack: no recursion, no stack arrays. All buffers live in .bss with
#  fixed sizes + bounds checks on every write.
# =====================================================================
        .intel_syntax noprefix

# ---------- Linux x86-64 syscall numbers ----------
        .equ SYS_read,          0
        .equ SYS_write,         1
        .equ SYS_open,          2
        .equ SYS_close,         3
        .equ SYS_ioctl,         16
        .equ SYS_mkdir,         83
        .equ SYS_exit,          60
        .equ SYS_clock_gettime, 228

# ---------- open() flags ----------
        .equ O_RDONLY,   0x0
        .equ O_WRONLY,   0x1
        .equ O_CREAT,    0x40
        .equ O_EXCL,     0x80
        .equ O_APPEND,   0x400
        .equ O_NOFOLLOW, 0x20000
        .equ O_CLOEXEC,  0x80000
        .equ EEXIST_NEG, -17
        .equ EINTR_NEG,  -4

# ---------- buffer limits (ALL writes are checked against these) ----------
        .equ LINEMAX,  2047         # max length of 1 input line (buf = +1 for NUL)
        .equ ACTMAX,   2047         # max length of activity from argv
        .equ ENTRYMAX, 8192         # 1 CSV line buffer
        .equ PATHMAX,  4096
        .equ CONFMAX,  16383        # config > 16 KB is truncated (buf = +1 for NUL)
        .equ INBUF_SZ, 4096
        .equ TAX_MAX,  32           # max taxonomy entries

# =====================================================================
        .section .rodata
default_conf:
        .ascii "[settings]\n"
        .ascii "DIR=\"$HOME/.local/share/logklerk/\"\n"
        .ascii "TZ_OFFSET=0\n"
        .ascii "[taxonomy]\n"
        .ascii "gg=\"Googling\"\n"
        .ascii "gam=\"Google AI Mode\"\n"
        .ascii "claude=\"Claude\"\n"
        .ascii "soy=\"Search on Youtube\"\n"
        .ascii "diary=\"Diary\"\n"
        .asciz "com=\"Commentary\"\n"

s_home_eq:      .asciz "HOME="
s_homevar:      .asciz "$HOME"
s_conf_suffix:  .asciz "/.config/logklerk/lk.conf"
s_default_dir:  .asciz "$HOME/.local/share/logklerk/"
s_sec_settings: .asciz "[settings]"
s_sec_taxonomy: .asciz "[taxonomy]"
s_k_dir:        .asciz "DIR"
s_k_tz:         .asciz "TZ_OFFSET"
s_ctx_bash:     .asciz "bash"
s_opt_h:        .asciz "-h"
s_opt_help:     .asciz "--help"
s_exit:         .asciz "exit"
s_quit:         .asciz "quit"
s_header:       .ascii "date,context,activity\n"
        .equ s_header_len, . - s_header
s_prompt:       .ascii "lk> "
        .equ s_prompt_len, . - s_prompt

m_usage:
        .ascii "LogKlerk asm v0.0.1\n"
        .ascii "  lk                   mode interaktif (exit/quit/Ctrl-D utk keluar)\n"
        .ascii "  lk <key> <teks...>   catat dgn konteks dari [taxonomy]\n"
        .ascii "  lk <perintah...>     key tidak dikenal => konteks \"bash\"\n"
        .ascii "config: ~/.config/logklerk/lk.conf\n"
        .equ m_usage_len, . - m_usage
m_nohome:   .ascii "lk: variabel HOME tidak ada\n"
        .equ m_nohome_len, . - m_nohome
m_noact:    .ascii "lk: key dikenal tapi teks kosong. Pakai: lk <key> <teks>\n"
        .equ m_noact_len, . - m_noact
m_dirlong:  .ascii "lk: path DIR terlalu panjang\n"
        .equ m_dirlong_len, . - m_dirlong
m_open:     .ascii "lk: gagal membuka/membuat file log (cek DIR & izin)\n"
        .equ m_open_len, . - m_open
m_big:      .ascii "lk: baris CSV melebihi buffer, tidak ditulis\n"
        .equ m_big_len, . - m_big
m_write:    .ascii "lk: gagal menulis ke file log\n"
        .equ m_write_len, . - m_write

# =====================================================================
        .section .data
        .balign 8
fd:         .quad -1                # log file fd, -1 = not yet opened
tz_off:     .quad 0                 # offset in seconds from config

# =====================================================================
        .section .bss
        .balign 16
argc:       .skip 8
argv_ptr:   .skip 8
envp_ptr:   .skip 8
home_ptr:   .skip 8
dir_ptr:    .skip 8                 # raw DIR value (points into confbuf)
dir_len:    .skip 8                 # expanded DIR length (ending with '/')
tax_count:  .skip 8
in_pos:     .skip 8
in_len:     .skip 8
tax_keys:   .skip 8*TAX_MAX         # pointer to key (inside confbuf)
tax_vals:   .skip 8*TAX_MAX         # pointer to value (inside confbuf)
tsbuf:      .skip 32
termios:    .skip 64
linebuf:    .skip LINEMAX+1
actbuf:     .skip ACTMAX+1
inbuf:      .skip INBUF_SZ
entrybuf:   .skip ENTRYMAX
pathbuf:    .skip PATHMAX
confbuf:    .skip CONFMAX+1

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
# write_all(edi=fd, rsi=buf, rdx=len) -> rax = 0 ok, -1 error
# Handles short writes & EINTR. Never loops infinitely (a write
# returning 0 is treated as an error).
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

# strlen(rdi=cstr) -> rax.  Only for trusted NUL-terminated strings
# (argv/env/our own buffers).  CLOBBER: rax
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
# Copies up to NUL (NUL is not copied). Writes only to addresses < limit.
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

# ---------------------------------------------------------------------
# getenv(rdi="NAME=", rsi=envp) -> rax = ptr to value, 0 if not found
# Comparison stops at the NUL of the name (not the env NUL) -> no over-read.
# CLOBBER: rax, rcx, rsi, r8
# ---------------------------------------------------------------------
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

# streq(rdi, rsi) -> eax=1 equal / 0 different.  CLOBBER: rax, rcx
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

# starts_with(rdi=str, rsi=prefix) -> eax=1/0, rcx = prefix length if 1
# CLOBBER: rax, rcx
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

# tax_lookup(rdi=key cstr) -> rax = context ptr, 0 if not found
# CLOBBER: rax, rcx, rsi, r8   (rdi is preserved)
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

# parse_int(rdi=cstr) -> rax (signed). Max 10 digits => cannot overflow.
# CLOBBER: rax, rcx, rdx, rdi, r8
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

# write_dec(rdi=dst, rax=value, ecx=digit_count) -> rdi = dst+digit_count
# Zero-padded; values with extra digits are truncated (does not exceed bounds).
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
# fmt_time(rdi=dst[>=19 bytes]) -> writes "YYYYMMDDTHHMMSS.mmm", rdi=dst+19
# UTC time + TZ_OFFSET (seconds). civil_from_days algorithm (H. Hinnant).
# Callee-saved registers are used & restored. CLOBBER: rax, rcx, rdx, rsi, r8-r11
# ---------------------------------------------------------------------
fmt_time:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 16                 # struct timespec {sec, nsec}
        mov     r12, rdi
        mov     eax, SYS_clock_gettime
        xor     edi, edi                # CLOCK_REALTIME
        mov     rsi, rsp
        syscall
        test    rax, rax
        jz      .Lft_have
        mov     qword ptr [rsp], 0      # on failure: use epoch, do not crash
        mov     qword ptr [rsp+8], 0
.Lft_have:
        mov     rax, [rsp]
        add     rax, [rip+tz_off]
        jns     .Lft_pos
        xor     eax, eax                # clamp: never negative
.Lft_pos:
        mov     rbx, rax                # epoch seconds (local)
        mov     rax, [rsp+8]
        xor     edx, edx
        mov     rcx, 1000000
        div     rcx
        mov     r14, rax                # milliseconds
        mov     rax, rbx
        xor     edx, edx
        mov     rcx, 86400
        div     rcx                     # rax = days, rdx = seconds in day
        mov     r15, rdx                # sod
        add     rax, 719468             # z
        xor     edx, edx
        mov     rcx, 146097
        div     rcx
        mov     r8, rax                 # era
        mov     r9, rdx                 # doe
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 1460
        div     rcx
        mov     r10, rax                # doe/1460
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 36524
        div     rcx
        mov     r11, rax                # doe/36524
        mov     rax, r9
        xor     edx, edx
        mov     rcx, 146096
        div     rcx                     # doe/146096
        mov     rcx, r9
        sub     rcx, r10
        add     rcx, r11
        sub     rcx, rax
        mov     rax, rcx
        xor     edx, edx
        mov     rcx, 365
        div     rcx
        mov     r10, rax                # yoe
        imul    r8, r8, 400
        add     r8, r10                 # y
        mov     rax, r10
        shr     rax, 2                  # yoe/4
        mov     rcx, r10
        imul    rcx, rcx, 365
        add     rcx, rax
        mov     rax, r10
        xor     edx, edx
        mov     r11, 100
        div     r11                     # yoe/100
        sub     rcx, rax
        mov     rax, r9
        sub     rax, rcx                # doy
        mov     r9, rax
        lea     rax, [rax+rax*4+2]      # 5*doy+2
        xor     edx, edx
        mov     rcx, 153
        div     rcx                     # mp
        mov     r10, rax
        imul    rax, rax, 153
        add     rax, 2
        xor     edx, edx
        mov     rcx, 5
        div     rcx
        sub     r9, rax
        inc     r9                      # d
        cmp     r10, 10
        jb      .Lft_lt
        sub     r10, 9
        jmp     .Lft_m
.Lft_lt:
        add     r10, 3                  # m
.Lft_m:
        cmp     r10, 2
        ja      .Lft_noadj
        inc     r8                      # months 1-2 => year +1
.Lft_noadj:
        mov     rbx, r8                 # y
        mov     r13, r10                # m
        mov     [rsp], r9               # d (timespec slot is no longer used)
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
        mov     r15, rdx                # remaining seconds
        mov     ecx, 2
        call    write_dec               # HH
        mov     rax, r15
        xor     edx, edx
        mov     rcx, 60
        div     rcx
        mov     r15, rdx                # SS
        mov     ecx, 2
        call    write_dec               # MM
        mov     rax, r15
        mov     ecx, 2
        call    write_dec               # SS
        mov     byte ptr [rdi], '.'
        inc     rdi
        mov     rax, r14
        mov     ecx, 3
        call    write_dec               # mmm
        add     rsp, 16
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# csv_field(rdi=dst, rsi=src, rdx=limit, rcx=len) -> rax = new dst / 0
# RFC 4180: quote field if it contains , or "; internal quotes are
# doubled (" -> ""). CR/LF are replaced with spaces so 1 entry = 1 line.
# Margin check: before processing each source byte, there must be >= 3
# free bytes (worst-case 2 output bytes + closing quote).
# CLOBBER: rax, rcx, rdi, rsi, r8-r11
# ---------------------------------------------------------------------
csv_field:
        lea     r9, [rsi+rcx]           # end of src
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

# ---------------------------------------------------------------------
# ensure_open() -> rax 0 ok / -1.  File name = timestamp of first entry.
# open(O_CREAT|O_EXCL) -> if successful, write header (race-free, without
# stat). EEXIST -> open in append mode. O_NOFOLLOW rejects symlinks, mode 0600.
# CLOBBER: rax, rcx, rdx, rsi, rdi, r11
# ---------------------------------------------------------------------
ensure_open:
        cmp     qword ptr [rip+fd], 0
        jge     .Leo_ok
        lea     rdi, [rip+pathbuf]
        add     rdi, [rip+dir_len]      # dir_len <= PATHMAX-32 guaranteed by build_dir
        lea     rsi, [rip+tsbuf]
        mov     ecx, 15
        rep movsb
        mov     dword ptr [rdi], 0x7673632e     # ".csv"
        mov     byte ptr [rdi+4], 0
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
        jmp     .Leo_ok
.Leo_exists:
        mov     eax, SYS_open
        lea     rdi, [rip+pathbuf]
        mov     esi, O_WRONLY|O_APPEND|O_CLOEXEC|O_NOFOLLOW
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Leo_fail
        mov     [rip+fd], rax
.Leo_ok:
        xor     eax, eax
        ret
.Leo_fail:
        mov     rax, -1
        ret

# ---------------------------------------------------------------------
# emit_entry(rdi=context cstr, rsi=activity ptr, rdx=activity len)
#   -> rax 0 ok / -1 (error message already printed)
# 1 CSV line is built in entrybuf then written with a SINGLE write() to fd
# with O_APPEND => lines do not interleave even when multiple shells write.
# ---------------------------------------------------------------------
emit_entry:
        push    rbx
        push    r12
        push    r13
        push    r14
        mov     r12, rdi
        mov     r13, rsi
        mov     r14, rdx
        lea     rdi, [rip+tsbuf]
        call    fmt_time
        call    ensure_open
        test    rax, rax
        jnz     .Lee_eopen
        lea     rdi, [rip+entrybuf]
        lea     rsi, [rip+tsbuf]
        mov     ecx, 19
        rep movsb
        mov     byte ptr [rdi], ','
        inc     rdi
        mov     rbx, rdi
        mov     rdi, r12
        call    strlen
        mov     rcx, rax
        mov     rdi, rbx
        mov     rsi, r12
        lea     rdx, [rip+entrybuf+ENTRYMAX-2]   # leave 2 bytes: ',' / '\n'
        call    csv_field
        test    rax, rax
        jz      .Lee_ebig
        mov     rdi, rax
        mov     byte ptr [rdi], ','
        inc     rdi
        mov     rsi, r13
        mov     rcx, r14
        lea     rdx, [rip+entrybuf+ENTRYMAX-2]
        call    csv_field
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
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# parse_config(): parse confbuf (NUL-terminated) IN-PLACE.
# Lines are NUL-terminated, key/value are pointers into confbuf (no
# copying => no buffer overflow). Supports: [section], key="value",
# # and ; comments, spaces/tabs/CRLF. Entries > TAX_MAX are ignored.
# ---------------------------------------------------------------------
parse_config:
        push    rbx
        push    r12
        push    r13
        push    r14
        lea     rbx, [rip+confbuf]
        xor     r12d, r12d              # section: 0 none, 1 settings, 2 taxonomy
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
        mov     r14, r13                # r14 = start of next line
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
        jz      .Lpc_next               # no '=' -> ignore line
        cmp     al, '='
        je      .Lpc_haveeq
        inc     rsi
        jmp     .Lpc_feq
.Lpc_haveeq:
        mov     rdi, rsi
        mov     byte ptr [rsi], 0
        inc     rsi                     # rsi = start of value
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
        cmp     byte ptr [rbx], 0       # empty key -> ignore
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
        mov     r9, rsi
        mov     rdi, rbx
        lea     rsi, [rip+s_k_dir]
        call    streq
        test    eax, eax
        jz      .Lpc_chk_tz
        mov     [rip+dir_ptr], r9
        jmp     .Lpc_next
.Lpc_chk_tz:
        mov     rdi, rbx
        lea     rsi, [rip+s_k_tz]
        call    streq
        test    eax, eax
        jz      .Lpc_next
        mov     rdi, r9
        call    parse_int
        mov     [rip+tz_off], rax
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

# ---------------------------------------------------------------------
# load_config(): read ~/.config/logklerk/lk.conf into confbuf; if missing
# or failed, use built-in default_conf. Always NUL-terminated.
# ---------------------------------------------------------------------
load_config:
        push    rbx
        push    r12
        lea     rdi, [rip+pathbuf]
        mov     rsi, [rip+home_ptr]
        lea     rdx, [rip+pathbuf+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lld_default
        mov     rdi, rax
        lea     rsi, [rip+s_conf_suffix]
        lea     rdx, [rip+pathbuf+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lld_default
        mov     byte ptr [rax], 0
        mov     eax, SYS_open
        lea     rdi, [rip+pathbuf]
        mov     esi, O_RDONLY|O_CLOEXEC
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Lld_default
        mov     rbx, rax                # config fd
        xor     r12d, r12d              # total bytes read
.Lld_rd:
        mov     rdx, CONFMAX
        sub     rdx, r12
        jz      .Lld_close              # full -> truncate
        lea     rsi, [rip+confbuf]
        add     rsi, r12
        xor     eax, eax                # SYS_read
        mov     edi, ebx
        syscall
        cmp     rax, EINTR_NEG
        je      .Lld_rd
        test    rax, rax
        jle     .Lld_close
        add     r12, rax
        jmp     .Lld_rd
.Lld_close:
        mov     eax, SYS_close
        mov     edi, ebx
        syscall
        lea     rax, [rip+confbuf]
        mov     byte ptr [rax+r12], 0
        test    r12, r12
        jnz     .Lld_out                # config is non-empty
.Lld_default:
        lea     rdi, [rip+confbuf]
        lea     rsi, [rip+default_conf]
        lea     rdx, [rip+confbuf+CONFMAX]
        call    bcopy_z
        mov     byte ptr [rax], 0
.Lld_out:
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# build_dir(): expand DIR ("$HOME" or "~" at start) into pathbuf, ensure
# trailing '/', store length in dir_len. Reserve 32 bytes for file name.
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
        mov     r12, rbx                # save original
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
        mov     rbx, r12                # e.g. "$HOMEX" -> literal
        jmp     .Lbd_literal
.Lbd_home:
        mov     rsi, [rip+home_ptr]
        lea     rdi, [rip+pathbuf]
        lea     rdx, [rip+pathbuf+PATHMAX-32]
        call    bcopy_z
        test    rax, rax
        jz      .Lbd_err
        mov     rdi, rax
        mov     rsi, rbx
        lea     rdx, [rip+pathbuf+PATHMAX-32]
        call    bcopy_z
        jmp     .Lbd_tail
.Lbd_literal:
        lea     rdi, [rip+pathbuf]
        mov     rsi, rbx
        lea     rdx, [rip+pathbuf+PATHMAX-32]
        call    bcopy_z
.Lbd_tail:
        test    rax, rax
        jz      .Lbd_err
        mov     rdi, rax
        lea     rcx, [rip+pathbuf]
        cmp     rdi, rcx
        je      .Lbd_err                # empty DIR
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

# mkdir_p(): mkdir -p for pathbuf (mode 0700). Errors are ignored here;
# real failures surface clearly when open()ing the log file.
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8, r9, r11
mkdir_p:
        lea     rsi, [rip+pathbuf]
        mov     r9, [rip+dir_len]
        mov     r8d, 1
.Lmk_l:
        cmp     r8, r9
        jae     .Lmk_d
        cmp     byte ptr [rsi+r8], '/'
        jne     .Lmk_n
        mov     byte ptr [rsi+r8], 0
        mov     eax, SYS_mkdir
        mov     rdi, rsi
        mov     esi, 0700
        syscall
        lea     rsi, [rip+pathbuf]      # syscall doesn't clobber rsi, but we modified esi above
        mov     byte ptr [rsi+r8], '/'
.Lmk_n:
        inc     r8
        jmp     .Lmk_l
.Lmk_d:
        ret

# ---------------------------------------------------------------------
# getc() -> eax = byte (0..255) or -1 (EOF).  Buffered read(0).
# CLOBBER: rax, rcx, rdx, rsi, rdi, r11
# ---------------------------------------------------------------------
getc:
        mov     rax, [rip+in_pos]
        cmp     rax, [rip+in_len]
        jb      .Lgc_have
        xor     eax, eax                # SYS_read
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

# ---------------------------------------------------------------------
# read_line() -> rax = length (linebuf NUL-terminated), -1 on EOF.
# Lines > LINEMAX: excess bytes are DISCARDED (truncated), never writing
# past linebuf.
# ---------------------------------------------------------------------
read_line:
        push    rbx
        xor     ebx, ebx
.Lrl_c:
        call    getc
        cmp     eax, -1
        je      .Lrl_eof
        cmp     eax, 10
        je      .Lrl_done
        cmp     ebx, LINEMAX
        jae     .Lrl_c
        lea     rdx, [rip+linebuf]
        mov     [rdx+rbx], al
        inc     ebx
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
# interactive(): loop reading stdin -> log entry. Return: exit code in edi.
# ---------------------------------------------------------------------
interactive:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     eax, SYS_ioctl          # TCGETS: success (0) = stdin is a tty
        xor     edi, edi
        mov     esi, 0x5401
        lea     rdx, [rip+termios]
        syscall
        xor     r12d, r12d
        test    rax, rax
        jnz     .Lia_loop
        mov     r12d, 1
.Lia_loop:
        test    r12d, r12d
        jz      .Lia_read
        mov     edi, 1
        lea     rsi, [rip+s_prompt]
        mov     edx, s_prompt_len
        call    write_all
.Lia_read:
        call    read_line
        test    rax, rax
        js      .Lia_end
        mov     r13, rax                # length
        lea     r14, [rip+linebuf]      # start (after left trim)
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
        jne     .Lia_trdone
.Lia_tr_s:
        dec     r13
        jmp     .Lia_tr
.Lia_trdone:
        mov     byte ptr [r14+r13], 0
        mov     rdi, r14
        lea     rsi, [rip+s_exit]
        call    streq
        test    eax, eax
        jnz     .Lia_end
        mov     rdi, r14
        lea     rsi, [rip+s_quit]
        call    streq
        test    eax, eax
        jnz     .Lia_end
        xor     ecx, ecx                # find end of first token
.Lia_tok:
        cmp     rcx, r13
        jae     .Lia_nokey
        mov     al, [r14+rcx]
        cmp     al, ' '
        je      .Lia_sp
        cmp     al, 9
        je      .Lia_sp
        inc     rcx
        jmp     .Lia_tok
.Lia_sp:
        mov     r15, rcx
        mov     bl, [r14+rcx]
        mov     byte ptr [r14+rcx], 0   # temporarily NUL-terminate
        mov     rdi, r14
        call    tax_lookup
        mov     [r14+r15], bl           # restore
        test    rax, rax
        jz      .Lia_nokey
        mov     rcx, r15
.Lia_skip:
        cmp     rcx, r13
        jae     .Lia_nokey              # key without text -> log as-is
        mov     dl, [r14+rcx]
        cmp     dl, ' '
        je      .Lia_skip_s
        cmp     dl, 9
        jne     .Lia_hit
.Lia_skip_s:
        inc     rcx
        jmp     .Lia_skip
.Lia_hit:
        mov     rdi, rax
        lea     rsi, [r14+rcx]
        mov     rdx, r13
        sub     rdx, rcx
        call    emit_entry
        test    rax, rax
        jnz     .Lia_fail
        jmp     .Lia_loop
.Lia_nokey:
        lea     rdi, [rip+s_ctx_bash]
        mov     rsi, r14
        mov     rdx, r13
        call    emit_entry
        test    rax, rax
        jnz     .Lia_fail
        jmp     .Lia_loop
.Lia_fail:
        mov     edi, 1
        jmp     .Lia_ret
.Lia_end:
        xor     edi, edi
.Lia_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# cli_mode(): lk <key> <text...>  |  lk <command...>.  Return edi=exit code
# ---------------------------------------------------------------------
cli_mode:
        push    rbx
        push    r12
        push    r13
        mov     rax, [rip+argv_ptr]
        mov     rdi, [rax+8]            # argv[1]
        call    tax_lookup
        mov     r12, rax                # context or 0
        mov     r13d, 1                 # index of first argument for activity
        test    r12, r12
        jz      .Lcl_join
        mov     r13d, 2
        cmp     r13, [rip+argc]
        jb      .Lcl_join
        ERR     m_noact, m_noact_len
        mov     edi, 2
        jmp     .Lcl_ret
.Lcl_join:
        lea     rdi, [rip+actbuf]
.Lcl_arg:
        cmp     r13, [rip+argc]
        jae     .Lcl_joined
        lea     rax, [rip+actbuf]
        cmp     rdi, rax
        je      .Lcl_nosp
        lea     rax, [rip+actbuf+ACTMAX]
        cmp     rdi, rax
        jae     .Lcl_trunc
        mov     byte ptr [rdi], ' '
        inc     rdi
.Lcl_nosp:
        mov     rax, [rip+argv_ptr]
        mov     rsi, [rax+r13*8]
        lea     rdx, [rip+actbuf+ACTMAX]
        call    bcopy_z
        test    rax, rax
        jz      .Lcl_trunc
        mov     rdi, rax
        inc     r13
        jmp     .Lcl_arg
.Lcl_trunc:
        lea     rdi, [rip+actbuf+ACTMAX]    # too long -> truncated
.Lcl_joined:
        lea     rsi, [rip+actbuf]
        mov     rdx, rdi
        sub     rdx, rsi
        mov     rdi, r12
        test    rdi, rdi
        jnz     .Lcl_emit
        lea     rdi, [rip+s_ctx_bash]
.Lcl_emit:
        call    emit_entry
        mov     edi, 0
        test    rax, rax
        jz      .Lcl_ret
        mov     edi, 1
.Lcl_ret:
        pop     r13
        pop     r12
        pop     rbx
        ret

# =====================================================================
_start:
        cld                             # DF=0 guaranteed for `rep movsb`
        mov     rax, [rsp]
        mov     [rip+argc], rax
        lea     rcx, [rsp+8]
        mov     [rip+argv_ptr], rcx
        lea     rcx, [rsp+rax*8+16]     # envp = argv + (argc+1)*8
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
        call    load_config
        call    parse_config
        call    build_dir
        call    mkdir_p
        cmp     qword ptr [rip+argc], 1
        ja      .Lst_cli
        call    interactive
        jmp     .Lst_exit
.Lst_cli:
        call    cli_mode
.Lst_exit:
        mov     eax, SYS_exit
        syscall

        .section .note.GNU-stack,"",@progbits
