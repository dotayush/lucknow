# user mode. runs code with mstatus.MPP = 0 and checks what the hardware does to it:
#   machine only csr, wfi and mret trap as illegal instruction (2), a counter without mcounteren (2),
#   ecall reports cause 8 (not 11), a machine timer interrupt is taken with mstatus.MIE = 0,
#   and a trap handler that sets MPP = 11 returns to machine mode.
# prints, in order: 2222 8 c T 8 M (the digits are mcause values from the trap handler)
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
    la    t0, handler
    csrw  mtvec, t0
    li    s1, MTIMECMP
    li    t0, -1
    sw    t0, 4(s1)
    sw    t0, 0(s1)              # no timer interrupt for now
    li    t0, 0x80
    csrs  mie, t0                # timer enabled, mstatus.MIE stays 0
    li    t0, 0x1800
    csrc  mstatus, t0            # MPP = user
    la    t0, user
    csrw  mepc, t0
    mret

    .balign 4
user:
    csrr  t0, mstatus            # illegal: machine csr
    wfi                          # illegal
    mret                         # illegal
    csrr  t0, cycle              # illegal: mcounteren is 0
    li    a7, 1
    ecall                        # cause 8, the handler enables the counters
    csrr  t0, cycle              # fine now
    putc  'c'
    li    s2, MTIME
    li    s1, MTIMECMP
    lw    t0, 0(s2)
    addi  t0, t0, 200
    sw    zero, 4(s1)
    sw    t0, 0(s1)              # timer in 200 clocks, mstatus.MIE is 0
    li    s3, 0
spin:
    addi  s3, s3, 1
    bnez  s3, spin               # until the handler (cause 0x80000007) puts s3 to 0 through mepc
    li    a7, 2
    ecall                        # cause 8, the handler returns to machine mode
    csrr  t0, mstatus            # works in machine mode
    putc  'M'
done:
    j     done

    .balign 4
handler:
    csrr  t0, mcause
    bltz  t0, timer
    addi  t1, t0, '0'
1:  lbu   t2, 5(s0)
    andi  t2, t2, 0x20
    beqz  t2, 1b
    sb    t1, 0(s0)
    li    t1, 8
    bne   t0, t1, skip           # not an ecall: step over the instruction
    li    t1, 1
    beq   a7, t1, counters
    li    t1, 0x1800
    csrs  mstatus, t1            # a7 = 2: return to machine mode
    j     skip
counters:
    li    t1, 7
    csrw  mcounteren, t1
skip:
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret
timer:
    li    t1, -1
    sw    t1, 4(s1)
    sw    t1, 0(s1)              # drops mtip (s1 is MTIMECMP, the user code loaded it)
    putc  'T'
    la    t0, spin_end
    csrw  mepc, t0               # leave the spin loop
    mret

spin_end:
    li    s3, 0
    li    a7, 2
    ecall
    csrr  t0, mstatus
    putc  'M'
    j     spin_end
