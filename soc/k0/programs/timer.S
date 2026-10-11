# interrupts through the clint. prints "aTTTSVz" on the uart:
#   a    boot
#   TTT  three machine timer interrupts, direct mtvec, handler rearms mtimecmp and mrets
#   S    a software interrupt raised by writing msip, taken right after the store
#   V    a timer interrupt through a vectored mtvec (the entry for cause 7)
#   z    done
# the main code only keeps state in s registers: the handlers use t registers freely, so an
# interrupt that lands anywhere in the main code must not disturb it.
    .set UART,     0x10000000
    .set CLINT,    0x02000000
    .set MTIMECMP, 0x02004000
    .set MTIME,    0x0200bff8

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
    li    s1, MTIMECMP
    li    s2, MTIME
    li    s3, 0                  # timer interrupts seen
    li    s4, 0                  # software interrupts seen
    li    s5, 0                  # vectored timer interrupts seen
    li    s6, 3
    putc  'a'

    # three direct mode timer interrupts
    la    t0, handler
    csrw  mtvec, t0
    sw    zero, 4(s1)            # mtimecmp high, the low half is still all ones
    lw    t0, 0(s2)
    addi  t0, t0, 200
    sw    t0, 0(s1)
    li    t0, 0x80               # MTIE
    csrs  mie, t0
    csrsi mstatus, 8               # MIE
wait_timer:
    wfi
    blt   s3, s6, wait_timer

    # software interrupt
    li    t0, 8                  # MSIE
    csrs  mie, t0
    li    t1, CLINT
    li    t2, 1
    sw    t2, 0(t1)
wait_soft:
    beqz  s4, wait_soft

    # vectored timer interrupt
    la    t0, vtable
    ori   t0, t0, 1
    csrw  mtvec, t0
    lw    t0, 0(s2)
    addi  t0, t0, 200
    sw    t0, 0(s1)
    li    t0, 0x80
    csrs  mie, t0
wait_vector:
    beqz  s5, wait_vector

    csrci mstatus, 8
    putc  'z'
done:
    j     done

    .balign 4
handler:
    csrr  t0, mcause
    li    t1, 0x80000007
    beq   t0, t1, h_timer
    li    t1, 0x80000003
    beq   t0, t1, h_soft
    putc  '!'                    # any other cause is a bug
    j     done
h_timer:
    putc  'T'
    addi  s3, s3, 1
    bge   s3, s6, h_timer_off
    lw    t0, 0(s2)
    addi  t0, t0, 200
    sw    t0, 0(s1)              # rearm, this also drops mtip
    mret
h_timer_off:
    li    t0, 0x80
    csrc  mie, t0
    mret
h_soft:
    putc  'S'
    addi  s4, s4, 1
    li    t0, CLINT
    sw    zero, 0(t0)            # drop msip
    mret

    .balign 4
vtable:                          # entry n is the handler of interrupt n
    j     handler                # 0
    j     handler                # 1
    j     handler                # 2
    j     handler                # 3 software
    j     handler                # 4
    j     handler                # 5
    j     handler                # 6
    j     v_timer                # 7 timer
v_timer:
    putc  'V'
    addi  s5, s5, 1
    li    t0, 0x80
    csrc  mie, t0
    mret
