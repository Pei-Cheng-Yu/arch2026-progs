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
    beqz a2, move_read  #face 0: first row

    li t3, 10080  #5040 permutations x 2 bytes
    li t4, 1458  #729 orientations x 2 bytes
    add t0, t0, t3
    add t1, t1, t4

    li t2, 1
    beq a2, t2, move_read  #face 1: second row

    add t0, t0, t3  #face 2: third row
    add t1, t1, t4
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
    
#input: a0 keys, a1 count, a2 key
find_key:
    li t0, 0 # low
    mv t1, a1  # high
find_key_loop:
    bgeu t0, t1, ret_find_key
    add t2, t0, t1  #low+high
    srli t2, t2, 1  #mid
    slli t3, t2, 2   #byte offset = mid*4
    add  t3, a0, t3  #addr of keys[mid]
    lw   t4, 0(t3)   # t4 = keys[mid]
    bgeu t4, a2, update_high

    addi t0, t2, 1
    j find_key_loop
update_high:
    mv t1, t2
    j find_key_loop
ret_find_key:
    bgeu t0, a1, find_key_missing
    slli t3, t0, 2
    add t3, a0, t3
    lw t4, 0(t3)

    bne t4, a2, find_key_missing
    mv a0, t0
    ret
find_key_missing:
    li a0, -1
    ret

#input: a0 moves, a1 index
get_move:
    srli t0, a1, 1
    add  t0, a0, t0
    lbu  t0, 0(t0)
    andi t1, a1, 1
    slli t1, t1, 2

    srl  a0, t0, t1
    andi a0, a0, 15
    ret

#input: a0 p rank, a1, o rank, a2 moveID
move_ranked:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    sw s1, 4(sp)

    sltiu t0, a2, 3 #t0 = (move <3)
    xori t0, t0 ,1  #t0 = (move>=3)

    sltiu t1, a2, 6
    xori t1, t1, 1
    add s0, t0, t1

    slli t0, s0, 1
    add t0, t0 ,s0
    sub s1, a2, t0
    addi s1, s1, 1

move_ranked_loop:
    mv a2, s0
    jal ra, move_quarter

    addi s1, s1, -1
    bnez s1, move_ranked_loop

    lw s1, 4(sp)
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
#input a0 p, a1 o, a2 index, a3 desti, return a0 tail or -1
finish_five:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)

    mv s0, a0   #p_rank
    mv s1, a1   #o_rank
    mv s2, a2   #index
    mv s3, a3   #next des byle
    li s4, 0    #tail length

finish_loop:
    or t0, s0, s1 
    beqz t0, finish_done #p==0 and o==0:end
    bltz s2, finish_fail # index < 0?
    li t0, 5
    bgeu s4, t0, finish_fail # length >= 5?
    
    la a0, rubik_five_moves
    mv a1, s2
    jal ra, get_move    #move in a0

    li t0, 9
    bgeu a0, t0, finish_fail

#dst[length++] = move;
    sb a0, 0(s3)
    addi s3, s3, 1
    addi s4, s4, 1
#apply_move_ranked(&p, &o, move);
    mv a2, a0
    mv a0, s0
    mv a1, s1
    jal ra, move_ranked
    mv s0, a0
    mv s1, a1

    or t0, s0, s1
    beqz t0, finish_done
#index = find_key(rubik_five_keys,RUBIK_FIVE_COUNT,make_key(p, o));
    slli a2, s0, 10
    or a2, a2, s1
    la a0, rubik_five_keys
    li a1, 12224
    jal ra, find_key
    mv s2, a0
    j finish_loop

finish_done:
    mv a0, s4
    j finish_return

finish_fail:
    li a0, -1

finish_return:
    lw s4, 8(sp)
    lw s3, 12(sp)
    lw s2, 16(sp)
    lw s1, 20(sp)
    lw s0, 24(sp)
    lw ra, 28(sp)
    addi sp, sp, 32
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
    sw s5, 120(sp)
   
    mv s3, a2 #addr solve array
    li s5, 0 #prefix_len
    sh a0, 0(sp)
    sh a1, 2(sp) #save start p, o
    li t0, 3
    sb t0, 5(sp)
    li t0, 0
    sb zero, 4(sp)
    sb zero, 6(sp)
    mv s1, a0 # s1 as bound (threshold)
    
#try with-in five search
    slli a2, a0, 10
    or a2, a2, a1 #make key
    
    la a0, rubik_five_keys
    li a1, 12224
    jal ra, find_key
    bltz a0, ida_try_eleven

    mv a2, a0  #Match table index
    lhu a0, 0(sp)
    lhu a1, 2(sp)
    mv a3, s3
    jal ra, finish_five
    j clean_up

ida_try_eleven:
    lhu t0, 0(sp)
    lhu t1, 2(sp)
    slli a2, t0, 10
    or a2, a2, t1
    la a0, rubik_eleven_keys
    la a1, 2644
    jal ra, find_key
    bltz a0, ida_set_bound
    
    mv a1, a0
    la a0, rubik_eleven_moves
    jal ra, get_move
    li t0, 9
    bgeu a0, t0, ida_return_neg

    sb a0, 0(s3)    #solution[0]=move
    li s5, 1    #prefix_len =1

    sltiu t0, a0, 3
    xori t0, t0, 1
    sltiu t1, a0, 6
    xori t1, t1, 1
    add t0, t0 , t1
    sb t0, 5(sp)    #root_face

    mv a2, a0
    lhu a0, 0(sp)
    lhu a1, 2(sp)
    jal ra, move_ranked
    sh a0, 0(sp)
    sh a1, 2(sp)

ida_set_bound:
    lhu a0, 0(sp)
    lhu a1, 2(sp)
    jal ra, heuristic
    sb a0, 7(sp)

    bnez s5, ida_bound_ten
    mv s1, a0
    li t0, 6
    bgeu s1, t0, solve_ida_loop
    li s1, 6
    j solve_ida_loop
ida_bound_ten:
    li s1, 10

solve_ida_loop:
    li s2, -1 # next bound
    li s0, 0 #depth
    mv s4, sp
    sb zero, 4(s4)
    li t0, 11 #MAX_DEPTH
    sub t0, t0, s5 #MAX_DEPTH - prefix_len
    blt t0, s1, ida_return_neg
    
solve_ida_inner_loop:

    lbu t1, 7(s4)    # h
    add t1, s0, t1  # f = depth + h
    blt s1, t1, check_next_bound
    
    lhu t1, 0(s4) # p >=0
    lhu t2, 2(s4) # o >=0
    add t1, t1, t2 # p+o>=0 (usigned)
    beq t1, zero, ida_done # if(p==0&o==0) load solution
    
    sub t1, s1, s0
    addi t1, t1, -5
    bnez t1, ida_not_five_step

    lhu t0, 0(s4)   #cur p 
    lhu t1, 2(s4)   #cur O
#form key
    slli a2, t0, 10 
    or a2, a2, t1

    la a0, rubik_five_keys
    li a1, 12224
    jal ra, find_key

    bgez a0, ida_table_hit

    addi t1, s0, 6  #no hit -> need at least six move
    j check_next_bound
ida_not_five_step:

    li t1, 11 #MAX_DEPTH
    sub t1, t1, s5
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
    
ida_table_hit:
    sw a0, 124(sp)  #save the matched five-move-table index
    j ida_copy_path
ida_done: 
    li t0, -1
    sw t0, 124(sp)
ida_copy_path:
    li t0, 1 #i=1

load_sol_loop: #s3 addr
    addi t1, t0, -1
    add  t1, t1, s5 # prefix_len + i - 1
    blt s0, t0, load_sol_done
    add t2, s3, t1
    slli t3, t0, 3
    add t3, sp, t3
    lbu t3, 6(t3)
    sb t3, 0(t2) 
    addi t0, t0, 1 #i++
    j load_sol_loop
    
load_sol_done:
    lw a2, 124(sp)  #the  saved table index
    bltz a2, ida_no_tail
#call finish_five
    lhu a0, 0(s4)   #p
    lhu a1, 2(s4)   #o
    add a3, s3, s5
    add a3, a3, s0  #solution + prefix_len + depth
    jal ra, finish_five
    bltz a0, ida_return_neg

    add a0, a0, s0
    add a0, a0, s5  #prefix_len + depth + tail
    j clean_up

ida_no_tail:
    add a0, s0, s5 #depth + prefix_len
    j clean_up

ida_return_neg:
    li a0, -1
    
clean_up:
    lw s5, 120(sp)
    lw ra, 116(sp)
    lw s0, 112(sp)
    lw s1, 108(sp)
    lw s2, 104(sp)
    lw s3, 100(sp)
    lw s4, 96(sp)
    addi sp, sp, 128
    ret

