# =====================================================================
#  LogKlerk lkc module  v0.0.3                       (src/modules/lkc.asm)
#  Reads the CSV logs: date filter, asc/desc order, colored output.
#
#  Pulled into src/main.asm with   .include "modules/lkc.asm"
#  (one assembly unit, so it shares main's helpers, macros and constants).
#
#  Needs from main.asm : macro ERR, out_cstr / out_bytes / out_ch / out_flush,
#      print_row, strlen, strcmp, streq, skip_ws, bcopy_z, fmt_time,
#      pathbuf, pbuf2, tsbuf, dir_len, ext_ptr, s_header(_len), PATHMAX,
#      SYS_* / O_* constants, EINTR_NEG
#  Provides            : cmd_lkc(rdi = argument cstr)
#
#  Usage   lkc                      today's rows (current local day)
#          lkc all                  every row of every file
#          lkc 202611               a month   (YYYY, YYYYMM, YYYYMMDD,
#          lkc 20261128T12            YYYYMMDDThh ... up to YYYYMMDDThhmmss)
#          lkc 20261101-20261128    a range (inclusive)
#          lkc <filter> desc        newest file first
# =====================================================================

        .equ FILEMAX,   4194304     # 4 MiB per CSV file read by lkc
        .equ LINEPTRS,  65536       # matching lines per file
        .equ DIRSZ,     262144      # getdents64 buffer
        .equ MAXFILES,  4096        # log files listed

        .section .rodata
s_asc:          .asciz "asc"
s_desc:         .asciz "desc"
s_all:          .asciz "all"
s_lbl_file:     .asciz "[!] "
s_noentries:    .asciz "[!] no entries\n"
m_lkc_usage:
        .ascii "[!] lkc [all|YYYY|YYYYMM|YYYYMMDD|YYYYMMDDThh|<dari>-<sampai>] [asc|desc]  (default: hari ini, waktu lokal)\n"
        .equ m_lkc_usage_len, . - m_lkc_usage
m_nodir:    .ascii "[!] lkc: folder log tidak bisa dibaca\n"
        .equ m_nodir_len, . - m_nodir

        .section .bss
        .balign 8
lkc_have:   .skip 8                 # 1 = a date filter (lo/hi) is active
lkc_desc:   .skip 8                 # 1 = descending order
lkc_all:    .skip 8                 # 1 = "all" keyword given
lkc_total:  .skip 8                 # rows printed so far
lkc_lolen:  .skip 8
lkc_hilen:  .skip 8
lkc_lo:     .skip 24                # filter lower bound (prefix compare)
lkc_hi:     .skip 24                # filter upper bound (prefix compare)
file_count: .skip 8
fileptrs:   .skip 8*MAXFILES        # pointers to file names inside dirbuf
lineptrs:   .skip 8*LINEPTRS        # matching rows of the current file
dirbuf:     .skip DIRSZ
filebuf:    .skip FILEMAX+1

        .text

# ---------------------------------------------------------------------
# lkc_default_today(): when neither a filter nor "all" was given, restrict
# the listing to the current local day (first 8 chars of the timestamp).
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
# ---------------------------------------------------------------------
lkc_default_today:
        cmp     qword ptr [rip+lkc_have], 0
        jne     .Lkd_ret
        cmp     qword ptr [rip+lkc_all], 0
        jne     .Lkd_ret
        lea     rdi, [rip+tsbuf]
        call    fmt_time
        mov     qword ptr [rip+lkc_lolen], 8
        mov     qword ptr [rip+lkc_hilen], 8
        lea     rsi, [rip+tsbuf]
        lea     rdi, [rip+lkc_lo]
        mov     ecx, 8
        rep movsb
        mov     byte ptr [rdi], 0
        lea     rsi, [rip+tsbuf]
        lea     rdi, [rip+lkc_hi]
        mov     ecx, 8
        rep movsb
        mov     byte ptr [rdi], 0
        mov     qword ptr [rip+lkc_have], 1
.Lkd_ret:
        ret

# ---------------------------------------------------------------------
# row_match(rdi=row) -> eax 1/0.  Matches when lo <= ts(prefix) and ts <= hi.
# CLOBBER: rax, rcx, rsi, rdi, r8
# ---------------------------------------------------------------------
row_match:
        cmp     qword ptr [rip+lkc_have], 0
        je      .Lrm_yes
        mov     r8, rdi
        mov     rsi, r8
        lea     rdi, [rip+lkc_lo]
        mov     rcx, [rip+lkc_lolen]
        repe cmpsb
        jb      .Lrm_no
        mov     rsi, r8
        lea     rdi, [rip+lkc_hi]
        mov     rcx, [rip+lkc_hilen]
        repe cmpsb
        ja      .Lrm_no
.Lrm_yes:
        mov     eax, 1
        ret
.Lrm_no:
        xor     eax, eax
        ret

# parse_spec(rdi=token) -> rax 0 ok / 1 bad.  "a" or "a-b", [0-9T], each side 1..15
# CLOBBER: rax, rcx, rdx, rsi, rdi, r8-r11
parse_spec:
        mov     r10, rdi
        xor     ecx, ecx
        mov     r8, -1
.Lps_l:
        mov     al, [r10+rcx]
        test    al, al
        jz      .Lps_end
        cmp     al, '-'
        jne     .Lps_nd
        cmp     r8, -1
        jne     .Lps_bad
        mov     r8, rcx
        jmp     .Lps_n
.Lps_nd:
        cmp     al, 'T'
        je      .Lps_n
        cmp     al, '0'
        jb      .Lps_bad
        cmp     al, '9'
        ja      .Lps_bad
.Lps_n:
        inc     rcx
        cmp     rcx, 64
        ja      .Lps_bad
        jmp     .Lps_l
.Lps_end:
        mov     r11, r10
        mov     r9, rcx
        mov     rax, r10
        mov     rdx, rcx
        cmp     r8, -1
        je      .Lps_have
        mov     r9, r8
        lea     rax, [r10+r8+1]
        mov     rdx, rcx
        sub     rdx, r8
        dec     rdx
.Lps_have:
        test    r9, r9
        jz      .Lps_bad
        cmp     r9, 15
        ja      .Lps_bad
        test    rdx, rdx
        jz      .Lps_bad
        cmp     rdx, 15
        ja      .Lps_bad
        mov     [rip+lkc_lolen], r9
        mov     [rip+lkc_hilen], rdx
        mov     rsi, r11
        lea     rdi, [rip+lkc_lo]
        mov     rcx, r9
        rep movsb
        mov     byte ptr [rdi], 0
        mov     rsi, rax
        lea     rdi, [rip+lkc_hi]
        mov     rcx, rdx
        rep movsb
        mov     byte ptr [rdi], 0
        xor     eax, eax
        ret
.Lps_bad:
        mov     eax, 1
        ret

# list_dir(): fill fileptrs/file_count with *LK_DEFAULT_FORMAT files of the log folder, sorted by name.
# -> rax 0 ok / -1
list_dir:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     qword ptr [rip+file_count], 0
        lea     rdi, [rip+pbuf2]
        lea     rsi, [rip+pathbuf]
        mov     rcx, [rip+dir_len]
        rep movsb
        mov     byte ptr [rdi], 0
        mov     eax, SYS_open
        lea     rdi, [rip+pbuf2]
        mov     esi, O_RDONLY|O_DIRECTORY|O_CLOEXEC
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Lld2_fail
        mov     rbx, rax
        xor     r12d, r12d
.Lld2_read:
        mov     rdx, DIRSZ
        sub     rdx, r12
        cmp     rdx, 1024
        jb      .Lld2_done
        mov     eax, SYS_getdents64
        mov     rdi, rbx
        lea     rsi, [rip+dirbuf]
        add     rsi, r12
        syscall
        cmp     rax, EINTR_NEG
        je      .Lld2_read
        test    rax, rax
        jle     .Lld2_done
        lea     r14, [rip+dirbuf]
        add     r14, r12
        add     r12, rax
.Lld2_ent:
        lea     rax, [rip+dirbuf]
        add     rax, r12
        cmp     r14, rax
        jae     .Lld2_read
        movzx   ecx, word ptr [r14+16]
        test    ecx, ecx
        jz      .Lld2_done
        lea     r15, [r14+19]
        movzx   edx, byte ptr [r14+18]
        add     r14, rcx
        cmp     dl, 8
        je      .Lld2_chk
        test    dl, dl
        jnz     .Lld2_ent
.Lld2_chk:
        mov     rdi, r15
        call    strlen
        mov     r8, rax
        mov     rdi, [rip+ext_ptr]
        call    strlen
        mov     r9, rax
        cmp     r8, r9
        jbe     .Lld2_ent
        lea     rdi, [r15+r8]
        sub     rdi, r9
        mov     rsi, [rip+ext_ptr]
        call    streq
        test    eax, eax
        jz      .Lld2_ent
        mov     rax, [rip+file_count]
        cmp     rax, MAXFILES
        jae     .Lld2_ent
        lea     rcx, [rip+fileptrs]
        mov     [rcx+rax*8], r15
        inc     rax
        mov     [rip+file_count], rax
        jmp     .Lld2_ent
.Lld2_done:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
        lea     r8, [rip+fileptrs]
        mov     r9, [rip+file_count]
        mov     r10d, 1
.Lso_i:
        cmp     r10, r9
        jae     .Lso_done
        mov     r11, [r8+r10*8]
        mov     rbx, r10
.Lso_j:
        test    rbx, rbx
        jz      .Lso_ins
        mov     rdi, [r8+rbx*8-8]
        mov     rsi, r11
        call    strcmp
        test    eax, eax
        jle     .Lso_ins
        mov     rax, [r8+rbx*8-8]
        mov     [r8+rbx*8], rax
        dec     rbx
        jmp     .Lso_j
.Lso_ins:
        mov     [r8+rbx*8], r11
        inc     r10
        jmp     .Lso_i
.Lso_done:
        xor     eax, eax
        jmp     .Lld2_out
.Lld2_fail:
        mov     rax, -1
.Lld2_out:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# lkc_one_file(rdi=file name): read, filter, print. Adds to lkc_total.
lkc_one_file:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r15, rdi
        lea     rdi, [rip+pbuf2]
        lea     rsi, [rip+pathbuf]
        mov     rcx, [rip+dir_len]
        rep movsb
        mov     rsi, r15
        lea     rdx, [rip+pbuf2+PATHMAX-1]
        call    bcopy_z
        test    rax, rax
        jz      .Lof2_ret
        mov     byte ptr [rax], 0
        mov     eax, SYS_open
        lea     rdi, [rip+pbuf2]
        mov     esi, O_RDONLY|O_CLOEXEC|O_NOFOLLOW
        xor     edx, edx
        syscall
        test    rax, rax
        js      .Lof2_ret
        mov     rbx, rax
        xor     r12d, r12d
.Lof2_rd:
        mov     rdx, FILEMAX
        sub     rdx, r12
        jz      .Lof2_rdd
        lea     rsi, [rip+filebuf]
        add     rsi, r12
        xor     eax, eax
        mov     rdi, rbx
        syscall
        cmp     rax, EINTR_NEG
        je      .Lof2_rd
        test    rax, rax
        jle     .Lof2_rdd
        add     r12, rax
        jmp     .Lof2_rd
.Lof2_rdd:
        mov     eax, SYS_close
        mov     rdi, rbx
        syscall
        lea     rax, [rip+filebuf]
        mov     byte ptr [rax+r12], 0
        lea     rbx, [rip+filebuf]
        lea     r13, [rbx+r12]
        xor     r14d, r14d
.Lof2_ln:
        cmp     rbx, r13
        jae     .Lof2_lnd
        mov     r15, rbx
.Lof2_f:
        cmp     rbx, r13
        jae     .Lof2_e
        cmp     byte ptr [rbx], 10
        je      .Lof2_e
        inc     rbx
        jmp     .Lof2_f
.Lof2_e:
        mov     byte ptr [rbx], 0
        mov     r9, rbx
        inc     rbx
        cmp     r9, r15
        jbe     .Lof2_ln
        cmp     byte ptr [r9-1], 13
        jne     .Lof2_cr
        mov     byte ptr [r9-1], 0
.Lof2_cr:
        movzx   eax, byte ptr [r15]
        sub     eax, '0'
        cmp     eax, 9
        ja      .Lof2_ln
        mov     rdi, r15
        call    row_match
        test    eax, eax
        jz      .Lof2_ln
        cmp     r14, LINEPTRS
        jae     .Lof2_ln
        lea     rax, [rip+lineptrs]
        mov     [rax+r14*8], r15
        inc     r14
        jmp     .Lof2_ln
.Lof2_lnd:
        test    r14, r14
        jz      .Lof2_ret
        add     [rip+lkc_total], r14
        lea     rdi, [rip+s_lbl_file]
        call    out_cstr
        lea     rdi, [rip+pbuf2]
        call    out_cstr
        mov     edi, 10
        call    out_ch
        lea     rsi, [rip+s_header]
        mov     edx, s_header_len
        call    out_bytes
        xor     r12d, r12d
.Lof2_pr:
        cmp     r12, r14
        jae     .Lof2_ret
        mov     rax, r12
        cmp     qword ptr [rip+lkc_desc], 0
        je      .Lof2_pi
        mov     rax, r14
        dec     rax
        sub     rax, r12
.Lof2_pi:
        lea     rcx, [rip+lineptrs]
        mov     rsi, [rcx+rax*8]
        mov     rdi, rsi
        call    strlen
        mov     rdx, rax
        call    print_row
        inc     r12
        jmp     .Lof2_pr
.Lof2_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret

# ---------------------------------------------------------------------
# cmd_lkc(rdi=argument cstr, writable): lkc [all|filter] [asc|desc]
# No filter = only the current local day; "all" = every row of every file. File order
# = file name (asc) or reversed (desc); rows inside a file follow the same order.
# ---------------------------------------------------------------------
cmd_lkc:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     rbx, rdi
        mov     qword ptr [rip+lkc_have], 0
        mov     qword ptr [rip+lkc_desc], 0
        mov     qword ptr [rip+lkc_total], 0
        mov     qword ptr [rip+lkc_all], 0
.Lkc_tok:
        mov     rdi, rbx
        call    skip_ws
        mov     rbx, rdi
        cmp     byte ptr [rbx], 0
        je      .Lkc_run
        mov     r12, rbx
.Lkc_te:
        mov     al, [rbx]
        test    al, al
        jz      .Lkc_tend
        cmp     al, ' '
        je      .Lkc_tend
        cmp     al, 9
        je      .Lkc_tend
        inc     rbx
        jmp     .Lkc_te
.Lkc_tend:
        cmp     byte ptr [rbx], 0
        je      .Lkc_nonul
        mov     byte ptr [rbx], 0
        inc     rbx
.Lkc_nonul:
        mov     rdi, r12
        lea     rsi, [rip+s_asc]
        call    streq
        test    eax, eax
        jz      .Lkc_t1
        mov     qword ptr [rip+lkc_desc], 0
        jmp     .Lkc_tok
.Lkc_t1:
        mov     rdi, r12
        lea     rsi, [rip+s_desc]
        call    streq
        test    eax, eax
        jz      .Lkc_t2
        mov     qword ptr [rip+lkc_desc], 1
        jmp     .Lkc_tok
.Lkc_t2:
        mov     rdi, r12
        lea     rsi, [rip+s_all]
        call    streq
        test    eax, eax
        jz      .Lkc_t3
        cmp     qword ptr [rip+lkc_have], 0     # "all" cannot be combined with a filter
        jne     .Lkc_usage
        mov     qword ptr [rip+lkc_all], 1
        jmp     .Lkc_tok
.Lkc_t3:
        cmp     qword ptr [rip+lkc_have], 0
        jne     .Lkc_usage
        cmp     qword ptr [rip+lkc_all], 0
        jne     .Lkc_usage
        mov     rdi, r12
        call    parse_spec
        test    rax, rax
        jnz     .Lkc_usage
        mov     qword ptr [rip+lkc_have], 1
        jmp     .Lkc_tok
.Lkc_run:
        call    lkc_default_today
        call    list_dir
        test    rax, rax
        jnz     .Lkc_nodir
        mov     r13, [rip+file_count]
        xor     r12d, r12d
.Lkc_file:
        cmp     r12, r13
        jae     .Lkc_end
        mov     rax, r12
        cmp     qword ptr [rip+lkc_desc], 0
        je      .Lkc_idx
        mov     rax, r13
        dec     rax
        sub     rax, r12
.Lkc_idx:
        lea     rcx, [rip+fileptrs]
        mov     rdi, [rcx+rax*8]
        inc     r12
        call    lkc_one_file
        jmp     .Lkc_file
.Lkc_end:
        cmp     qword ptr [rip+lkc_total], 0
        jne     .Lkc_flush
        lea     rdi, [rip+s_noentries]
        call    out_cstr
.Lkc_flush:
        call    out_flush
        jmp     .Lkc_ret
.Lkc_nodir:
        ERR     m_nodir, m_nodir_len
        jmp     .Lkc_ret
.Lkc_usage:
        ERR     m_lkc_usage, m_lkc_usage_len
.Lkc_ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
