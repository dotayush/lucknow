# physical memory protection. machine mode sets up regions, user code then touches them and the handler
# prints the mcause digit of every fault. regions (entry: range, permissions):
#   0  NAPOT 0x80000000..0x80000fff  rwx     the program itself
#   1  NAPOT 0x10000000..0x10000007  rw      the uart
#   3  TOR   0x80001000..0x80001fff  r       (entry 2 holds the lower bound, off)
#   4  NA4   0x80002000              rw
#   7  TOR   0x80003000..0x80003fff  r, locked (entry 6 holds the lower bound)
# prints a 7 5 1 e 5 7 h (user), then 7 l L P (machine): a letter is an access that worked, a digit is
# the mcause of one that did not (1 fetch, 5 load, 7 store or amo). L: a locked pmpcfg ignores writes,
# P: so does the pmpaddr below a locked TOR entry.
# expected output: a751e57h7lLP
    .set UART, 0x10000000

    .macro putc ch
1:  lbu   t2, 5(s0)              # LSR
    andi  t2, t2, 0x20           # THRE
    beqz  t2, 1b
    li    t2, \ch
    sb    t2, 0(s0)              # THR
    .endm

    .text
    .globl _start
_start:
    li    s0, UART
    la    t0, handler
    csrw  mtvec, t0
    li    t0, 0x20000000 | 0x1ff
    csrw  pmpaddr0, t0
    li    t0, 0x04000000
    csrw  pmpaddr1, t0
    li    t0, 0x80001000 >> 2
    csrw  pmpaddr2, t0
    li    t0, 0x80002000 >> 2
    csrw  pmpaddr3, t0
    li    t0, 0x80002000 >> 2
    csrw  pmpaddr4, t0
    li    t0, 0x80003000 >> 2
    csrw  pmpaddr6, t0
    li    t0, 0x80004000 >> 2
    csrw  pmpaddr7, t0
    # pmpcfg0: entry 0 = 0x1f, 1 = 0x1b, 2 = 0, 3 = 0x09 (TOR r)
    li    t0, 0x09001b1f
    csrw  pmpcfg0, t0
    # pmpcfg1: entry 4 = 0x13 (NA4 rw), 5 = 0, 6 = 0, 7 = 0x89 (locked TOR r)
    li    t0, 0x89000013
    csrw  pmpcfg1, t0
    li    t0, 0x1800
    csrc  mstatus, t0            # MPP = user
    la    t0, user
    csrw  mepc, t0
    mret

    .balign 4
user:
    li    s1, 0x80001000
    lw    t0, 0(s1)              # read only region: fine
    putc  'a'
    sw    t0, 0(s1)              # store fault, 7
    li    s2, 0x80003000 + 0x1000 # no region at all
    lw    t0, 0(s2)              # load fault, 5
    la    ra, after_fetch
    jr    s1                     # fetch from a region without x: fetch fault, 1 (handler returns to ra)
after_fetch:
    li    s1, 0x80002000
    lw    t0, 0(s1)              # NA4 rw: fine
    sw    t0, 0(s1)
    putc  'e'
    lw    t0, 4(s1)              # one word past the NA4 region: 5
    li    s1, 0x80001000
    amoadd.w t0, t0, (s1)        # an amo needs w: 7
    lr.w  t0, (s1)               # lr only needs r: fine
    putc  'h'
    li    a7, 2
    ecall                        # back to machine mode

    .balign 4
machine:
    li    s1, 0x80003000
    sw    zero, 0(s1)            # locked region binds machine mode: 7
    lw    t0, 0(s1)
    putc  'l'
    csrw  pmpcfg1, zero          # entry 7 is locked: ignored
    csrr  t0, pmpcfg1
    srli  t0, t0, 24
    li    t1, 0x89
    bne   t0, t1, bad
    putc  'L'
    li    t0, 0x12345678
    csrw  pmpaddr6, t0           # below a locked TOR entry: ignored
    csrr  t0, pmpaddr6
    li    t1, 0x80003000 >> 2
    bne   t0, t1, bad
    putc  'P'
done:
    j     done
bad:
    putc  'x'
    j     done

    .balign 4
handler:
    csrr  t0, mcause
    li    t1, 8
    beq   t0, t1, ecall
    addi  t1, t0, '0'
1:  lbu   t2, 5(s0)
    andi  t2, t2, 0x20
    beqz  t2, 1b
    sb    t1, 0(s0)
    li    t1, 1
    beq   t0, t1, fetch
    csrr  t1, mepc
    addi  t1, t1, 4
    csrw  mepc, t1
    mret
fetch:
    csrw  mepc, ra
    mret
ecall:
    li    t1, 0x1800
    csrs  mstatus, t1            # return to machine mode
    la    t1, machine
    csrw  mepc, t1
    mret
