# timer interrupts that land in the middle of an amo must not lose it or run it twice.
# the main loop does 60 amoadd.w of 1 on one word, a timer interrupt (every 37 clocks)
# lands wherever it lands, and in the end the word has to be exactly 60.
# prints "ok" when it is (and at least 5 interrupts were taken), "no" otherwise.
# meant to be run with slow memories too, see ./run.sh
    .set UART,     0x10000000
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
    li    s3, 0                  # interrupts taken
    la    s4, counter
    li    s5, 60                 # iterations
    li    s6, 1

    sw    zero, 0(s4)
    la    t0, handler
    csrw  mtvec, t0
    sw    zero, 4(s1)
    lw    t0, 0(s2)
    addi  t0, t0, 37
    sw    t0, 0(s1)
    li    t0, 0x80
    csrs  mie, t0
    csrsi mstatus, 8

loop:
    amoadd.w zero, s6, (s4)
    addi  s5, s5, -1
    bnez  s5, loop

    csrci mstatus, 8
    lw    s7, 0(s4)
    li    t0, 60
    bne   s7, t0, bad
    li    t0, 5
    blt   s3, t0, bad
    putc  'o'
    putc  'k'
    j     done
bad:
    putc  'n'
    putc  'o'
done:
    j     done

    .balign 4
handler:
    addi  s3, s3, 1
    lw    t0, 0(s2)
    addi  t0, t0, 37
    sw    t0, 0(s1)              # rearm, drops mtip
    mret

    .data
counter:
    .word 0
