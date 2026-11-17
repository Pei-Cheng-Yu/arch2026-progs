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
gcd_u32_loop:
    beq a0, a1, gcd_u32_return
    andi t1, a0, 1
    andi t2, a1, 1
    add t3, t1, t2
    beqz t3, gcd_ab_even
    beqz t1, gcd_a_even
    beqz t2, gcd_b_even
    bltu a1, a0, gcd_a_bigger
    sub a1, a1, a0
    j gcd_u32_loop
gcd_ab_even:
    srli a0, a0, 1
    srli a1, a1, 1
    addi t0, t0, 1
    j gcd_u32_loop

gcd_a_even:
    srli a0, a0, 1
    j gcd_u32_loop

gcd_b_even:
    srli a1, a1, 1
    j gcd_u32_loop

gcd_a_bigger:
    sub a0, a0, a1
    j gcd_u32_loop

gcd_u32_return_b:
    mv a0, a1
    ret
gcd_u32_return_a:
    ret
gcd_u32_return:
    sll a0, a0, t0
    ret
    .size   gcd_u32_asm, .-gcd_u32_asm
