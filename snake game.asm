# bitnmap display config
#  unit width in pixels = 8 
#  unit height in pixels = 8 
# display width in pixels = 512
# display height in pixels = 256
# base address for disaply = 0x10010000(static data)

.data 
display: .space 8192 #64*32*4Bytes : display screen
snake_x: .space 8192 #2048 pixel 
snake_y: .space 8192
snake_len: .word 3
dir_x: .word 1 #to right so head will increase 
dir_y: .word 0 #dir_y=1 then downward motion the head pixel will increase downward
food_x: .word 0 
food_y: .word 0
score: .word 0
game_over: .word 0
msg_over: .asciiz "Game over!"
msg_nl: .asciiz "\n"


.text
.global main 
##################################
# main 
##################################
main : 
jal clear_screen
jal init_game 

game_loop:
jal read_input
jal update_snake
lw $t0, game_over
bnez $t0,end_game 

li $v0,32
li $a0,100
syscall #sleep for 100ms
j game_loop

end_game:
li $v0,4
la $a0,msg_over
syscall #print msg_over 
li $v0,1
lw $a0,score
syscall #print the score
li $v0,10
syscall #stop the exuction


###############################
# set_pixel : $a0=x(column) , $a1=y(row) , $a2=color
# it draws one colored cell on the bitmap display
#address=0x10010000(1st display pixel)+(y*64+x)*4Bytes
###############################
set_pixel:
sll $t0,$a1,6 #t0=y*64
add $t0,$t0,$a0 #t0=t0+x
sll $t0,$t0,2 #*4
lui $t1,0x1001 # since the 1st 2 bytes of static address will not be changed in addition since the 2nd addition operand is 4s multication so 1st byte is always 0 and 2nd byte does not matter since it will be added to 00
add $t0,$t1,$t0
sw $a2,0($t0)
jr $ra


###############################
# clear_screen : fill all pixels (cells) with black
###############################
clear_screen:
lui $t0,0x1001
li $t1,2048
cs_loop:
sw $zero,0($t0) #black color=0
addi $t1,$t1,-1
addi $t0,$t0,4
bnez $t1,cs_loop
jr $ra


######################################
# init_game : build starting snake (head at 10(column),16(row) moving right)
######################################
init_game:
addi $sp,$sp,-4
sw $ra,0($sp)

la $t0,snake_x # $t0 = address of the snake_x array
la $t1,snake_y # $t1 = address of the snake_y array

#the snake=head+body+tail
#colums (x values)
li $t2,10
sw $t2,0($t0) #head==snake_x[0]
li $t2,9
sw $t2,4($t0) #body==snake_x[1]
li $t2,8
sw $t2,8($t0) #tail==snake_x[2]

#rows (y values)
li $t2,16
sw $t2,0($t1)#head
sw $t2,4($t1)#body
sw $t2,8($t1)#tail

#li $t2,3
#sw $t2,snake_len
#li $t2,1
#sw $t2,dir_x
#sw $zero,dir_y
#sw $zero,score
#sw $zero,game_over

#draw head (yellow)
li $a0,10 #column
li $a1,16 #row
li $a2,0x00ffff00 
jal set_pixel

# draw body (green)
li $a0,9 #column
li $a1,16 #row
li $a2,0x0000FF00
jal set_pixel

#draw tail (green)
li $a0,8 #column
li $a1,16 #row
li $a2,0x0000FF00
jal set_pixel

jal place_food

lw $ra,0($sp)
addi $sp,$sp,4
jr $ra


###############################
# read_input: non-blocking keyboard (MMIO), W/A/S/D
# Ignores moves that would reverse the snake into itself.
###############################
read_input:
lui $t0,0xffff #t0=0xffff0000
lw $t1,0($t0) #receiver control , read the control register at 0xFFFF0000
andi $t1,$t1,1
beqz $t1,ri_done #no key waiting
lw $t2,4($t0) #receiver data (ASCII),read actual data at 0xffff0004 address
lw $t3,dir_x
lw $t4,dir_y


li $t5,119 # 'w' : up
bne $t2,$t5,ri_s #key!=w check if = s
li $t6,1
beq $t4,$t6,ri_done #the snake currentlly is moving down so we ignore it to avoid the snake to eat itself
sw $zero,dir_x #no horizantal motion
li $t6,-1
sw $t6,dir_y
j ri_done

ri_s:
li $t5,115 #'s' : down
bne $t5,$t2,ri_a #key!=s check if = a
li $t6,-1
beq $t4,$t6,ri_done #currentlly moving up ...
sw $zero,dir_x
li $t6,1
sw $t6,dir_y
j ri_done

ri_a:
li $t5,97 #'a' : left
bne $t5,$t2,ri_d
li $t6,1
beq $t3,$t6,ri_done #currentlly moving right
li $t6,-1
sw $t6,dir_x
sw $zero,dir_y
j ri_done


ri_d:
li $t5,100 #'d' : right
bne $t2,$t5,ri_done
li $t6,-1
beq $t3,$t6,ri_done #currentlly moving left
li $t6,1
sw $t6,dir_x
sw $zero,dir_y

ri_done:
jr $ra




##########################################
# update_snake: move, collide, eat, grow, draw
# Uses $s0-$s7 freely (main keeps nothing in them).
#   $s2,$s3 = new head x,y     $s4,$s5 = array bases
#   $s6     = snake length     $s7     = ate food flag
###########################################
update_snake:
addi $sp,$sp,-4
sw $ra,0($sp)

la $s4,snake_x
la $s5,snake_y
lw $s0,0($s4) #head x
lw $s1,0($s5) #head y
lw $t0,dir_x  # -1, 0 or 1
lw $t1,dir_y  # -1, 0 or 1
add $s2,$s0,$t0 #new x
add $s3,$s1,$t1 #new y


# wall collision 
bltz $s2,us_dead
bltz $s3,us_dead
li $t0,64
bge $s2,$t0,us_dead
li $t0,32
bge $s3,$t0,us_dead

 

# self collision
lw $s6,snake_len
li $t0,0 
us_self:
bge $t0,$s6,us_selfok
sll $t1,$t0,2
add $t2,$s4,$t1
lw $t3,0($t2)
bne  $t3, $s2, us_next
add  $t2, $s5, $t1
lw   $t3, 0($t2)
beq  $t3, $s3, us_dead

us_next:
addi $t0,$t0,1
j us_self

us_selfok:
 # ---- did we eat the food? ----
 lw $t0,food_x
 lw $t1,food_y
 li $s7,0
 bne $s2,$t0,us_noeat
 bne $s3,$t1,us_noeat
 li $s7,1 #flag that the head is on the food
 
 us_noeat:
  # ---- erase tail if not growing ----
  bnez $s7, us_grow
    addi $t0, $s6, -1
    sll  $t0, $t0, 2
    add  $t1, $s4, $t0
    lw   $a0, 0($t1)
    add  $t1, $s5, $t0
    lw   $a1, 0($t1)
    li   $a2, 0                    # black
    jal  set_pixel
    j    us_shift
    
us_grow:
addi $s6,$s6,1
sw $s6,snake_len
lw $t0,score
addi $t0,$t0,1
sw $t0,score

    # ---- shift body: for i = len-1 down to 1: pos[i] = pos[i-1] ----
us_shift:
    addi $t0, $s6, -1
us_shift_loop:
    blez $t0, us_shift_done
    sll  $t1, $t0, 2               # offset i
    addi $t2, $t1, -4              # offset i-1
    add  $t3, $s4, $t2
    lw   $t4, 0($t3)
    add  $t3, $s4, $t1
    sw   $t4, 0($t3)
    add  $t3, $s5, $t2
    lw   $t4, 0($t3)
    add  $t3, $s5, $t1
    sw   $t4, 0($t3)
    addi $t0, $t0, -1
    j    us_shift_loop
us_shift_done:

#store new head 
sw $s2,0($s4)
sw $s3,0($s5)

    # old head (now index 1) becomes green
lw $a0,4($s4)
lw $a1,4($s5)
 li   $a2, 0x0000FF00
    jal  set_pixel
    
    #draw new head ( yellow)
    move $a0,$s2
    move $a1,$s3
     li   $a2, 0x00FFFF00
    jal  set_pixel
    
       beqz $s7, us_done
    jal  place_food                # ate -> new food
    j    us_done
    
    us_dead:
    li $t0,1
    sw $t0,game_over
    
    us_done:
      lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
    
    
##################################
# place_food: random cell not on the snake, drawn in red
#################################
place_food:
addi $sp,$sp,-4
sw $ra,0($sp)

pf_retry:
li $v0,42
li $a0,0
li $a1,64
syscall
move $s0,$a0 #random x

li $v0,42
li $a0,0
li $a1,32
syscall
move $s1,$a0 #random y

la $t4,snake_x
la $t5,snake_y
lw $t6,snake_len
li $t0,0

pf_chk: 
bge $t0,$t6,pf_ok
sll $t1,$t0,2
add $t2,$t4,$t1
lw $t3,0($t2)
bne $t3,$s0,pf_nx
add $t2,$t5,$t1
lw $t3,0($t2)
beq $t3,$s1,pf_retry #landed on snake try again 

pf_nx:
addi $t0,$t0,1
j pf_chk

pf_ok:
sw $s0,food_x
sw $s1,food_y
#draw the food
move $a0,$s0
move $a1,$s1
li $a2,0x00FF0000 #red 
jal set_pixel

 lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
 









