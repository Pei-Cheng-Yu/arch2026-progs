# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li t0, 0
    beqz a1, op1_return
op1_loop:
    and t1, a0, a1
    xor a0, a0, a1
    slli a1, t1, 1
    addi t0, t0, 1
    bnez a1, op1_loop
op1_return:
    sw  t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    srli t1, a0, 1
    and a0, a0, a1
    srli a1, a1, 1
    add t1, t1, a1
    andi a0, a0, 1
    add a0, t1, a0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    xor t0, a0, a1
    srli t0, t0, 31 #sign diff

    bge a0, zero, q_mul_ua_done
    sub a0, zero, a0
q_mul_ua_done:
    bge a1, zero, q_mul_ub_done
    sub a1, zero, a1
q_mul_ub_done:
# uint64_t product
    li t1, 0    #low
    li t2, 0
# uint64_t shifted=ua
    mv t3, a0   #low
    li t4, 0

q_mul_loop:
    beqz a1, q_mul_loop_done
    andi t5, a1, 1
    beqz t5, q_mul_shift

q_mul_add_shift:
    add t5, t1, t3
    sltu t6, t5, t1 #carry?
    add t2, t2, t4
    add t2, t2, t6
    mv t1, t5
q_mul_shift:
    srli t5, t3, 31
    slli t4, t4, 1
    or t4, t4, t5   #from low to high?
    slli t3, t3, 1 #shifted<<=1

    srli a1, a1, 1
    j q_mul_loop
q_mul_loop_done:
    beqz t0, q_mul_round
    not t1, t1
    not t2, t2
    addi t1, t1, 1
    seqz t5, t1
    add t2, t2 ,t5
q_mul_round:
    li t5, 0x80000
    add t6, t1, t5
    sltu t5, t6, t1 #carry?
    add t2, t2, t5
    mv t1, t6

    srli    t1, t1, 20
    slli    t2, t2, 12
    or      a0, t1, t2
    ret
    .size   q_mul_asm, .-q_mul_asm
