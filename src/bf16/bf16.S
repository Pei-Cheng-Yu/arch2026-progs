# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    srli t0, a0, 23
    andi t0, t0, 0xFF
    li t1, 0xFF
    beq t0, t1, bf16_from_f32_return
    slli t1, a0, 16  #discarded bits
    bge t1, zero, bf16_from_f32_return  #less than half
    srli t1, a0, 16
    andi t1, t1, 1
    li   t0, 0x7FFF
    add  a0, a0, t0
    add  a0, a0, t1
bf16_from_f32_return:
    srli a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor  a2, a0, a1
    li t0, 0x8000   #sign_mask
    and a2, a2, t0  #sign
    srli a3, a0, 7
#exp_a
    andi a3, a3, 0xFF  
#exp_b
    srli a4, a1, 7
    andi a4, a4, 0xFF

    li t0, 0x007F #mant_mask
    and a5, a0, t0  #mant_a
    and a6, a1, t0
    li t0, 0xFF
    beq a3, t0, bf16_mul_special_a
    beq a4, t0, bf16_mul_special_b
    li t0, 0x7FFF

    and t1, a0, t0
    beqz t1, bf16_mul_return_zero

    and t1, a1, t0
    beqz t1, bf16_mul_return_zero
    
    li t0, 128  #hidden_bit
    bnez a3,  bf16_mul_a_normal
    li a3, 1    #exp_a=1

bf16_mul_a_norm_loop:
    bgeu a5, t0, bf16_mul_a_ready
    slli a5, a5, 1
    addi a3, a3, -1
    j bf16_mul_a_norm_loop

bf16_mul_a_normal:
    ori a5,a5, 128

bf16_mul_a_ready:
 #start normalize b
    bnez a4, bf16_mul_b_normal
    li a4, 1 #exp_b=1

bf16_mul_b_norm_loop:
    bgeu a6, t0, bf16_mul_b_ready
    slli a6, a6, 1
    addi a4, a4, -1
    j bf16_mul_b_norm_loop

bf16_mul_b_normal:
    ori a6, a6, 128

bf16_mul_b_ready:
    li t1, 0 

bf16_mul_product_loop:
    andi t2, a6, 1  #check lowest bit
    beqz t2, bf16_mul_product_shift #skip add if zero
    add  t1, t1, a5

bf16_mul_product_shift:
    slli a5, a5, 1
    srli a6, a6, 1
    bnez a6, bf16_mul_product_loop

    add  a3, a3, a4
    addi a3, a3, -127   #exp_a + exp_b -bias

    li t0, 0x8000
    bltu t1, t0, bf16_mul_product_ready

    srli t1, t1, 1
    addi a3, a3, 1

bf16_mul_product_ready:
    srli t1, t1, 7 
    andi t1, t1, 0x7F   #(product >> 7) & BF16_MANT_MASK

    li t0, 255
    bge a3, t0, bf16_mul_return_inf

    bge zero, a3, bf16_mul_underflow  # result_exp <= 0

# Normal result.
    slli a3, a3, 7
    or a0, a2, a3
    or a0, a0, t1
    ret

bf16_mul_underflow:
    li t0, -6
    blt a3, t0, bf16_mul_return_zero

    li t0, 1
    sub t0, t0, a3
    srl t1, t1, t0
    or a0, a2, t1
    ret

bf16_mul_return_zero:
    mv   a0, a2
    ret

bf16_mul_special_a:
    beqz a5, bf16_mul_a_inf
    ret
bf16_mul_a_inf:
    li t0, 0x7FFF
    and t0, a1, t0
    beqz t0, bf16_mul_invalid
    j bf16_mul_return_inf
bf16_mul_special_b:
    beqz a6, bf16_mul_b_inf
    mv a0, a1
    ret

bf16_mul_b_inf:
    li t0, 0x7FFF
    and t0, a0, t0
    beqz t0, bf16_mul_invalid
bf16_mul_return_inf:
    li a0, 0x7F80
    or a0, a0, a2
    ret
bf16_mul_invalid:
    li a0, 0x7FC0
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

bf16_sqrt_asm:
    srli a1, a0, 7
    andi a1, a1, 0xFF
    andi a2, a0, 0x7F

    li t0, 255
    beq a1, t0, bf16_sqrt_special

#check zero before negative
    li t0, 0x7FFF  #mag_mask
    and t0, a0, t0
    beqz t0, bf16_sqrt_zero

    srli t0, a0, 15  #sign
    bnez t0, bf16_sqrt_nan
    beqz a1, bf16_sqrt_zero  #positive subnormal

    ori a2, a2, 128  #hidden_bit
    addi a3, a1, -127  #e=exp-bias

    andi t0, a3, 1  #check odd exponent
    beqz t0, bf16_sqrt_even
    slli a2, a2, 1  #mant*=2
    addi a3, a3, -1  #e--
bf16_sqrt_even:
    srai a3, a3, 1  #e/2
    addi a3, a3, 127  #result_exp=e/2+bias

    li a4, 90  #low
    li a5, 256  #high
    li a6, 128  #result

bf16_sqrt_search:
    bltu a5, a4, bf16_sqrt_normalize  #low>high
    add a7, a4, a5
    srli a7, a7, 1  #mid=(low+high)/2

#mid*mid
    li t0, 0  #product
    mv t1, a7  #shifted
    mv t2, a7  #multiplier

bf16_sqrt_square_loop:
    andi t3, t2, 1  #check lowest bit
    beqz t3, bf16_sqrt_square_shift  #skip add if zero
    add t0, t0, t1

bf16_sqrt_square_shift:
    slli t1, t1, 1
    srli t2, t2, 1
    bnez t2, bf16_sqrt_square_loop

    srli t0, t0, 7  #(mid*mid)/128
    bltu a2, t0, bf16_sqrt_too_high  #square>mant

    mv a6, a7  #result=mid
    addi a4, a7, 1  #low=mid+1
    j bf16_sqrt_search

bf16_sqrt_too_high:
    addi a5, a7, -1  #high=mid-1
    j bf16_sqrt_search

bf16_sqrt_normalize:
    li t0, 256

bf16_sqrt_shift_right:
    bltu a6, t0, bf16_sqrt_check_low
    srli a6, a6, 1  #result>>=1
    addi a3, a3, 1  #result_exp++
    j bf16_sqrt_shift_right

bf16_sqrt_check_low:
    li t0, 128  #hidden_bit

bf16_sqrt_shift_left:
    bgeu a6, t0, bf16_sqrt_pack
    slli a6, a6, 1  #result<<=1
    addi a3, a3, -1  #result_exp--
    j bf16_sqrt_shift_left

bf16_sqrt_pack:
    li t0, 255
    bge a3, t0, bf16_sqrt_inf
    bge zero, a3, bf16_sqrt_zero  #result_exp<=0

    slli a3, a3, 7
    andi a6, a6, 0x7F  #remove hidden bit
    or a0, a3, a6
    ret

bf16_sqrt_special:
    bnez a2, bf16_sqrt_return  #return NaN unchanged
    srli t0, a0, 15
    bnez t0, bf16_sqrt_nan  #negative infinity

bf16_sqrt_return:
    ret

bf16_sqrt_nan:
    li a0, 0x7FC0
    ret

bf16_sqrt_zero:
    li a0, 0
    ret

bf16_sqrt_inf:
    li a0, 0x7F80
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
