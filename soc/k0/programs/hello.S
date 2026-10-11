# prints "hello, lucknow\n" on the uart and spins. polls LSR.THRE before every byte like a
# real driver. linked at the ram base.
    .text
    .globl _start
_start:
    lui   t0, 0x10000            # uart base 0x1000_0000
    la    t1, message
next:
    lbu   t2, 0(t1)
    beqz  t2, done
wait:
    lbu   t3, 5(t0)              # LSR
    andi  t3, t3, 0x20           # THRE
    beqz  t3, wait
    sb    t2, 0(t0)              # THR
    addi  t1, t1, 1
    j     next
done:
    j     done

    .section .rodata
message:
    .asciz "hello, lucknow\n"
