# performance counters (zihpm). counts a known workload with event counters 3..10 and prints the counts as
# digits, then checks mcountinhibit, the 64 bit counters, and user mode access through mcounteren.
#   events: 1 load, 2 store, 3 branch taken, 4 branch not taken, 5 jump, 6 exception, 10 mul/div, 11 amo
#   workload: 5 loads, 3 stores, a 10 iteration loop (9 taken, 1 not taken), 2 jumps, 1 ecall,
#             3 mul and 1 div, 2 amoadd
# expected output: 53912142 k h u 2   (printed without the spaces)
#   53912142  loads, stores, taken, not taken, jumps, exceptions, mul/div, amo
#   k         counters stay put while inhibited
#   h         a counter written to 0xFFFFFFFF counts into its high half
#   u         user mode reads hpmcounter3 once mcounteren allows it
#   2         and gets an illegal instruction trap for hpmcounter4, which it was not given
    .set UART, 0x10000000

    .macro putc ch
1:  lbu   t2, 5(s0)
    andi  t2, t2, 0x20
    beqz  t2, 1b
    li    t2, \ch
    sb    t2, 0(s0)
    .endm

    # print the low digit of a csr
    .macro putdigit csr
    csrr  t0, \csr
    addi  t0, t0, '0'
1:  lbu   t2, 5(s0)
    andi  t2, t2, 0x20
    beqz  t2, 1b
    sb    t0, 0(s0)
    .endm

    .text
    .globl _start
_start:
    li    s0, UART
    la    t0, win_handler
    csrw  mtvec, t0
    li    t0, 1
    csrw  mhpmevent3, t0         # loads
    li    t0, 2
    csrw  mhpmevent4, t0         # stores
    li    t0, 3
    csrw  mhpmevent5, t0         # branches taken
    li    t0, 4
    csrw  mhpmevent6, t0         # branches not taken
    li    t0, 5
    csrw  mhpmevent7, t0         # jumps
    li    t0, 6
    csrw  mhpmevent8, t0         # exceptions
    li    t0, 10
    csrw  mhpmevent9, t0         # mul and div
    li    t0, 11
    csrw  mhpmevent10, t0        # amo
    # the counters have been counting since reset (the boot rom's jump is a jump): start from zero
    csrw  mhpmcounter3, zero
    csrw  mhpmcounter4, zero
    csrw  mhpmcounter5, zero
    csrw  mhpmcounter6, zero
    csrw  mhpmcounter7, zero
    csrw  mhpmcounter8, zero
    csrw  mhpmcounter9, zero
    csrw  mhpmcounter10, zero
    la    s1, buf

    # ---- the measured part: nothing in it but the counted instructions (and addi, which is not counted)
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    sw    t0, 0(s1)
    sw    t0, 0(s1)
    sw    t0, 0(s1)
    li    t1, 10
loop:
    addi  t1, t1, -1
    bnez  t1, loop
    j     j1
j1: j     j2
j2:
    li    t0, 7
    mul   t0, t0, t0
    mul   t0, t0, t0
    mul   t0, t0, t0
    div   t0, t0, t1
    amoadd.w t0, t0, (s1)
    amoadd.w t0, t0, (s1)
    ecall
    li    t0, 0x7f8
    csrw  mcountinhibit, t0      # stop counters 3..10
    # ----

    la    t0, handler
    csrw  mtvec, t0
    putdigit mhpmcounter3
    putdigit mhpmcounter4
    putdigit mhpmcounter5
    putdigit mhpmcounter6
    putdigit mhpmcounter7
    putdigit mhpmcounter8
    putdigit mhpmcounter9
    putdigit mhpmcounter10

    # inhibited: three more loads must not count
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    csrr  t0, mhpmcounter3
    li    t1, 5
    bne   t0, t1, bad
    putc  'k'

    # 64 bits: 0xFFFFFFFF plus two loads
    li    t0, -1
    csrw  mhpmcounter3, t0
    csrw  mhpmcounter3h, zero
    csrw  mcountinhibit, zero
    lw    t0, 0(s1)
    lw    t0, 0(s1)
    li    t0, 0x7f8
    csrw  mcountinhibit, t0
    csrr  t0, mhpmcounter3
    li    t1, 1
    bne   t0, t1, bad
    csrr  t0, mhpmcounter3h
    bne   t0, t1, bad
    putc  'h'

    # user mode: counter 3 allowed, counter 4 not
    li    t0, 0x8
    csrw  mcounteren, t0
    li    t0, -1
    csrw  pmpaddr0, t0
    li    t0, 0x1f
    csrw  pmpcfg0, t0
    li    t0, 0x1800
    csrc  mstatus, t0            # MPP = user
    la    t0, user
    csrw  mepc, t0
    mret

    .balign 4
user:
    csrr  t0, hpmcounter3        # allowed
    putc  'u'
    csrr  t0, hpmcounter4        # not allowed: illegal instruction, handler prints 2
    putc  '!'
bad:
    putc  'x'
done:
    j     done

    .balign 4
win_handler:                     # no branches, loads or stores: it runs inside the measured part
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret

    .balign 4
handler:
    csrr  t0, mcause
    addi  t0, t0, '0'
1:  lbu   t2, 5(s0)
    andi  t2, t2, 0x20
    beqz  t2, 1b
    sb    t0, 0(s0)
    j     done                   # stop after the illegal instruction

    .balign 4
buf:
    .word 0, 0, 0, 0
