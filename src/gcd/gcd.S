# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq a0, x0, gcd_u32_return_b
    beq a1, x0, gcd_u32_return_a
    li t0, 0
gcd_ab_even:
    or   t1, a0, a1
    andi t1, t1, 1
    bnez t1, gcd_strip_a

    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    j gcd_ab_even
gcd_strip_a:
    andi t1, a0, 1
    bnez t1, gcd_u32_loop
    srli a0, a0, 1
    j gcd_strip_a
gcd_u32_loop:
    andi t1, a1, 1
    bnez t1, gcd_compare
    srli a1, a1, 1
    j gcd_u32_loop

gcd_compare:
    beq a0, a1, gcd_u32_return
    bltu a0, a1, gcd_subtract
    mv t1, a0
    mv a0, a1
    mv a1, t1

gcd_subtract:
    sub a1, a1, a0
    srli a1, a1, 1
    j gcd_u32_loop

gcd_u32_return:
    sll a0, a0, t0
    ret
gcd_u32_return_b:
    mv a0, a1
    ret

gcd_u32_return_a:
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
