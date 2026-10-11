# uart receive through the plic. the testbench types the bytes of programs/uartrx.input on the
# serial line; every byte raises the uart's interrupt (plic source 10, machine external
# interrupt), the handler claims it, drains the receiver into a ring buffer and completes it.
# the main code echoes what arrived, lower case letters turned to upper case:
#   a        boot
#   ...      the input, upper cased
#   z        done
# main keeps its state in s and a registers and the handler uses only t registers, so an interrupt
# that lands anywhere in the main code must not disturb it.
    .set UART,       0x10000000
    .set PLIC,       0x0c000000
    .set PLIC_PRIO,  0x0c000028      # priority of source 10
    .set PLIC_EN,    0x0c002000
    .set PLIC_THR,   0x0c200000
    .set PLIC_CLAIM, 0x0c200004
    .set COUNT,      8               # bytes in uartrx.input

    .text
    .globl _start
_start:
    li    s0, UART
1:  lbu   t2, 5(s0)              # LSR
    andi  t2, t2, 0x20           # THRE
    beqz  t2, 1b
    li    t2, 'a'
    sb    t2, 0(s0)

    la    t0, handler
    csrw  mtvec, t0
    li    t0, PLIC_PRIO
    li    t1, 1
    sw    t1, 0(t0)              # source 10 priority 1
    li    t0, PLIC_EN
    li    t1, 0x400
    sw    t1, 0(t0)              # enable source 10
    li    t0, PLIC_THR
    sw    zero, 0(t0)            # threshold 0
    li    t0, 1
    sb    t0, 1(s0)              # IER: received data
    li    t0, 0x800              # MEIE
    csrs  mie, t0
    csrsi mstatus, 8             # MIE

    li    s1, 0                  # tail: next byte to echo
    li    s2, 0                  # bytes echoed
    la    s3, head
    la    s4, buf
loop:
    lw    a0, 0(s3)              # head, moved by the handler
    beq   a0, s1, loop
    add   a1, s4, s1
    lbu   a2, 0(a1)
    addi  s1, s1, 1
    andi  s1, s1, 15
    addi  a3, a2, -97            # 'a'..'z' to upper case
    li    a4, 26
    bgeu  a3, a4, 3f
    addi  a2, a2, -32
3:
2:  lbu   a3, 5(s0)
    andi  a3, a3, 0x20
    beqz  a3, 2b
    sb    a2, 0(s0)
    addi  s2, s2, 1
    li    a4, COUNT
    blt   s2, a4, loop

4:  lbu   a3, 5(s0)
    andi  a3, a3, 0x20
    beqz  a3, 4b
    li    a2, 'z'
    sb    a2, 0(s0)
done:
    j     done

    .balign 4
handler:
    csrr  t0, mcause
    li    t1, 0x8000000b         # machine external interrupt
    bne   t0, t1, bad
    li    t0, PLIC_CLAIM
    lw    t1, 0(t0)              # claim: the source id
    li    t2, 10
    bne   t1, t2, bad
drain:
    li    t0, UART
    lbu   t2, 5(t0)              # LSR
    andi  t2, t2, 1              # DR
    beqz  t2, drained
    lbu   t2, 0(t0)              # RBR
    la    t3, head
    lw    t4, 0(t3)
    la    t5, buf
    add   t5, t5, t4
    sb    t2, 0(t5)
    addi  t4, t4, 1
    andi  t4, t4, 15
    sw    t4, 0(t3)
    j     drain
drained:
    li    t0, PLIC_CLAIM
    sw    t1, 0(t0)              # complete
    mret
bad:
    li    t0, UART
    li    t2, '!'
    sb    t2, 0(t0)
    j     done

    .balign 4
head:
    .word 0
buf:
    .space 16
