# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.


.data
p:
    .zero 7
o:
    .zero 7
solution:
    .zero 11
.align 4

    
move_r:   .asciz "R"
move_r2:  .asciz "R2"
move_ri:  .asciz "R'"
move_b:   .asciz "B"
move_b2:  .asciz "B2"
move_bi:  .asciz "B'"
move_d:   .asciz "D"
move_d2:  .asciz "D2"
move_di:  .asciz "D'"

.align 4
move_names:
    .word move_r, move_r2, move_ri
    .word move_b, move_b2, move_bi
    .word move_d, move_d2, move_di
    
.text

.globl  rubik_solve_asm
.type   rubik_solve_asm, @function
.align  2
rubik_solve_asm:
    addi sp, sp, -32

    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s5, 16(sp)
    sw s6, 12(sp)
    sw s7, 8(sp)

    sw a1, 0(sp)
    sw a2, 4(sp) 
    la s0, p
    la s1, o
    li t0, 0
    li t4, 7 #stop condition  for array_p
array_p:
     add t1, a0, t0 # t1 is the address of target index for input
     lbu t2, 0(t1)
     addi t2, t2, -49 #convert into zero-base
     bgeu t2, t4, invalid

    li t5, 0 

check_duplicate:
    bgeu t5, t0, store_p #whether checck all

    add t3, s0, t5
    lbu t6, 0(t3)
    beq t2, t6, invalid

    addi t5, t5, 1
    j check_duplicate

store_p:
     add t3, s0, t0
     sb t2, 0(t3)
     addi t0, t0, 1 # got the next index offset
     blt t0, t4, array_p #loop
     
     li t4, 14

    li t5, 0    # valid O sum.
    li t6, 3    #valid value <3.
array_o:
     add t1, a0, t0 # t1 is the address of target index for input
     lbu t2, 0(t1)
     addi t2, t2, -49 #convert into zero-base
     bgeu t2, t6, invalid
     add t5, t5, t2   # sum += converted o

    addi t1, t0, -7          # O array index=i-7
    add t3, s1, t1
    sb t2, 0(t3)

    addi t0, t0, 1 # got the next index offset
    blt t0, t4, array_o
    lbu t2, 14(a0)
    bnez t2, invalid
reduce_sum:
    bltu t5, t6, check_sum  # t6 is still 3.
    addi t5, t5, -3
    j reduce_sum

check_sum:
    bnez t5, invalid




    la a0, p
    la a1, o
    jal ra, rank
    la a2, solution
    jal ra, solve_ida
    
    li t0, -1
    beq a0, t0, return_solver
    
    mv s5, a0    #lenght
    li s6, 0 #i=0
    la s7, solution

#count required bytes
    li t0, 1    # byte for \0
    la t6, move_names   #move table addr
output_count_moves:
    bgeu s6, s5, output_size_done
    beqz s6, output_count_name #no space before first move
    addi t0, t0,1
output_count_name:
    add t1, s7, s6  #addr of solution[]
    lbu t2, 0(t1)

    slli t2,t2, 2 # IDx4 byte per entry
    add t2, t6, t2  #addr of move_name[moveID]
    lw t3, 0(t2)

output_count_chars:
    lbu t4, 0(t3)   #read char
    beqz t4, output_count_next  #check end
    
    addi t0, t0, 1  #count char
    addi t3, t3, 1  # next source (move_name)
    j output_count_chars

output_count_next:
    addi s6, s6, 1  #next entry of solution
    j output_count_moves

#check cap
output_size_done:
    lw t1, 4(sp)
    bltu t1, t0, output_small_buffer # if cap<need

# Write output

    lw t0, 0(sp)
    li s6, 0    

output_write_moves:
    bgeu s6, s5, output_done # finished all?
    beqz s6, output_write_name # no space before first ('\0')
    li t4, 32   #ASCII of spacce
    sb t4, 0(t0)    #write space
    addi t0, t0, 1  #advance desti pointer

output_write_name:
    add t1, s7, s6  #addr of soluation
    lbu t2, 0(t1)   #read move ID
    slli t2, t2, 2
    add t2, t6, t2  #addr of move_name[moveID]
    lw t3, 0(t2)

output_write_chars:
    lbu t4, 0(t3)
    beqz t4, output_write_next  #stop when '\0'
    
    sb t4, 0(t0)
    addi t3, t3, 1
    addi t0, t0, 1
    j output_write_chars

output_write_next:
    addi s6, s6, 1
    j output_write_moves

output_done:
    sb zero, 0(t0)
    mv a0, s5
    j return_solver

#insufficient cap
output_small_buffer:
    lw t1, 4(sp)
    beqz t1, output_buffer_error    #cap=0

    lw t0, 0(sp)
    sb zero, 0(t0)  #cap>0

output_buffer_error:
    li a0, -2
    j return_solver

invalid:
    li a0, -1
return_solver:
    lw s7, 8(sp)
    lw s6, 12(sp)
    lw s5, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)

    addi sp, sp, 32
    ret

.size rubik_solve_asm, .-rubik_solve_asm
rank:
    li t0, 0 #p
    li t1, 0 #o
    li a2, 7 #CUBIES
    li t2, 0 # index i
rank_p_loop:
    li t3, 0 #smaller = 0
    addi t4, t2, 1 #j-i+1
    bge t4, a2, rank_p_next
    add t6, a0, t2
    lbu t6, 0(t6)    #p[i]
    
rank_p_inner:
    add t5, a0, t4
    lbu t5, 0(t5) #p[j]
    bgeu t5, t6, rank_p_next_j
    addi t3, t3, 1

rank_p_next_j:
    addi t4, t4, 1
    blt t4, a2, rank_p_inner
    
    # product = p_rank*(7-i)
    sub t5, a2, t2 
    li t6, 0
    
rank_p_multiply:
    add t6, t6, t0
    addi t5, t5, -1
    bne t5, zero, rank_p_multiply
    add t0, t6, t3 # p = product+smaller
    
rank_p_next:
    addi t2, t2, 1
    blt t2, a2, rank_p_loop

    li t2, 0    # i = 0
    li a2, 6    # i<6

rank_o_loop:
    slli t5, t1, 1            # 2 × o_rank
    add t1, t1, t5            # 3 × o_rank

    add t5, a1, t2
    lbu t5, 0(t5)             # o[i]
    add t1, t1, t5

    addi t2, t2, 1
    blt t2, a2, rank_o_loop

    mv a0, t0                 # Return p
    mv a1, t1                 # Return o , those are not be express as p*ORIEN..+o, return sperately
    ret
    

    
#inpute: a0 p rank, a1 0 rank, a2 face
#output: a0 new p, a1 new o
move_quarter: 
    la t0, permutation_moves
    la t1, orientation_moves
    mv t2, a2
    li t3, 10080              #5040 permutaition per face, each occupied 2 byte
    li t4, 1458               #720 orientation per face, each 2 btye
move_select_row:
    beq t2, zero, move_read
    add t0, t0, t3
    add t1, t1, t4
    addi t2, t2, -1
    j move_select_row
move_read:
    slli t2, a0, 1 # rank -> index
    add t0, t0, t2
    slli t2, a1, 1
    add t1, t1, t2
    lhu a0, 0(t0)
    lhu a1, 0(t1)
    ret

#input: a0 p , a1 o
heuristic:
    la t0, permutation_distances
    la t1, orientation_distances
    add t0, t0, a0
    add t1, t1, a1
    lbu a0, 0(t0)
    lbu a1, 0(t1)
    bge a0, a1, heuristic_ret
    mv a0, a1
heuristic_ret:
    ret
    
    
#input: a0 p, a1 o, a2 addr of solution array
solve_ida:
    addi sp, sp, -32
    addi sp, sp, -96 # 12 frames x 8b each frame (0:p, 2:o, 4: next move, 5: previous face, 6: incomming move, 7: h
    
    sw ra, 116(sp)
    sw s0, 112(sp)
    sw s1, 108(sp)
    sw s2, 104(sp)
    sw s3, 100(sp)
    sw s4, 96(sp)
    
    
    sh a0, 0(sp)
    sh a1, 2(sp) #save start p, o
    jal ra, heuristic
    sb a0, 7(sp) # save start h
    li t0, 3
    sb t0, 5(sp)
    li t0, 0
    sb t0, 4(sp)
    sb t0, 6(sp) #init other field
    mv s1, a0 # s1 as bound (threshold)
    
    mv s3, a2 #addr solve array
solve_ida_loop:
    li s2, -1 # next bound
    li s0, 0 #depth
    mv s4, sp
    sb zero, 4(s4)
    li t0, 11 #MAX_DEPTH
    blt t0, s1, ida_return_neg
    
solve_ida_inner_loop:

    lbu t1, 7(s4)    # h
    add t1, s0, t1  # f = depth + h
    blt s1, t1, check_next_bound
    
    lhu t1, 0(s4) # p >=0
    lhu t2, 2(s4) # o >=0
    add t1, t1, t2 # p+o>=0 (usigned)
    beq t1, zero, ida_done # if(p==0&o==0) load solution
    
    li t1, 11 #MAX_DEPTH
    beq s0, t1, next_inner
    
after_new_frame:
    lbu t0, 4(s4)    
    li t1, 9 #MOVES
    beq t0, t1, next_inner
    
    li   t1, 0    # face = 0(R)
    li   t2, 3
    bltu t0, t2, face_done  #move<3:keep 0
    
    li   t1, 1    # face=1(B)
    li   t2, 6
    bltu t0, t2, face_done  #move<6: keep 1

    li   t1, 2    # face= 2(D)

face_done:
#t0=move
#t1=face index
    lbu t2, 5(s4) #previous face
    beq t1, t2, apply_next_move
    addi t2, t0, 1
    sb t2, 4(s4) #cur->next_move++
    slli t2, t1, 1 #face<<1
    add t2, t2, t1 #+face
    sub t2, t0, t2 #move - ((face << 1) + face) , t2 = remainder
    addi t3, s4, 8  # next frame (child) addr
    
    beq t2, zero, use_current_rank
    lhu a0, 0(t3) # p=child->p
    lhu a1, 2(t3) # o =child->o
    j rank_applied
    
use_current_rank:
    lhu a0, 0(s4)
    lhu a1, 2(s4)
    
rank_applied:
    mv a2, t1
    mv a3, t3
    mv a4, t0
    jal ra, move_quarter
    sh a0, 0(a3) # save child p
    sh a1, 2(a3) #o
    jal ra, heuristic
    sb a2, 5(a3) #face
    sb a4, 6(a3) #move
    sb a0, 7(a3) # h
    sb zero, 4(a3)
    
    addi s0, s0, 1
    addi s4, s4, 8
    j solve_ida_inner_loop
    
check_next_bound:
    bgeu t1, s2, next_inner #f>= next_bound -> go next
    mv s2, t1
next_inner:
    beq s0, zero, ida_inner_done
    addi s0, s0, -1
    addi s4, s4, -8
    j after_new_frame    

apply_next_move:
    addi t2, t0, 3 #move+3
    sb t2, 4(s4)
    j after_new_frame

ida_inner_done:
    li t0, -1
    beq s2, t0, ida_return_neg
    mv s1, s2
    j solve_ida_loop
    
ida_done: 
    # load solution
    li t0, 1 #i=1
    
load_sol_loop: #s3 addr
    addi t1, t0, -1
    blt s0, t0, load_sol_done
    add t2, s3, t1
    slli t3, t0, 3
    add t3, sp, t3
    lbu t3, 6(t3)
    sb t3, 0(t2) 
    addi t0, t0, 1 #i++
    j load_sol_loop
    
load_sol_done:
    mv a0, s0
    j clean_up
ida_return_neg:
    li a0, -1
    
clean_up:
    lw ra, 116(sp)
    lw s0, 112(sp)
    lw s1, 108(sp)
    lw s2, 104(sp)
    lw s3, 100(sp)
    lw s4, 96(sp)
    addi sp, sp, 128
    ret

