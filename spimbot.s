########################################## SPIMBOT ############################################

.data

# syscall constants
PRINT_STRING	= 4

# spimbot constants
VELOCITY	= 0xffff0010
ANGLE		= 0xffff0014
ANGLE_CONTROL	= 0xffff0018
BOT_X		= 0xffff0020
BOT_Y		= 0xffff0024

SMOOSHED_MASK	= 0x2000
SMOOSHED_ACK	= 0xffff0064

FRUIT_SMASH	= 0xffff0068
FRUIT_SCAN	= 0xffff005c

BONK_MASK	= 0x1000
BONK_ACK	= 0xffff0060

TIMER		= 0xffff001c
TIMER_MASK	= 0x8000
TIMER_ACK	= 0xffff006c

OUT_OF_ENERGY_ACK	= 0xffff00c4
OUT_OF_ENERGY_INT_MASK	= 0x4000

GET_ENERGY	= 0xffff00c8

PUZZLE_MASK	= 0x800
PUZZLE_ACK	= 0xffff00d8

REQUEST_PUZZLE	= 0xffff00d0
SUBMIT_SOLUTION	= 0xffff00d4

REQUEST_WORD	= 0xffff00dc

directions:
	.word -1  0
	.word  0  1
	.word  1  0
	.word  0 -1

NODE_SIZE = 12


.align 2
fruit_data: 		.space 260
num_smooshed: 		.word 0

puzzle_address:		.word num_rows
num_rows:		.space 4
num_cols:		.space 4
puzzle_grid:		.space 8192
word_address:		.word puzzle_word
puzzle_word:		.space 128
puzzle_grid_received:	.word 0

# Stores the address for the next node to allocate
new_node_address:	.word node_memory
node_memory:		.space 4096



.text
main:
################################# Enable Interrupts ################################# 
	#enable interrupts
	li	$t4, BONK_MASK		# bonk interrupt enable bit
	or	$t4, $t4, SMOOSHED_MASK	# smooshed interrupt bit
	or	$t4, $t4, PUZZLE_MASK	# bonk interrupt bit set
	or	$t4, $t4, 1		# global interrupt enable
	mtc0	$t4, $12		# set interrupt mask (Status register)	





############################## Move To Smoosh Position ############################## 
	#check to see if at smoosh position
	check_y:
		li	$t0, 250
		lw	$t1, BOT_Y
		beq 	$t1, $t0, smooshify
		bgt	$t1, $t0, go_up

	go_down:
		li	$a0, 90
		li	$a1, 1
		li	$a2, 10
		jal	set_angle_control_velocity
		j	check_y

	go_up:
		li	$a0, 270
		li	$a1, 1
		li	$a2, 10
		jal	set_angle_control_velocity
		j	check_y






################################### Main Function ################################### 

	#smoosh fruit
	# s0 - fruit address
	# s1 - fruit x
	# s2 - fruit y
	# s3 - fruit id
	smooshify:
		# lw	$t7, GET_ENERGY
		# bgt	$t7, 30, follow_target_continue
		# sw  	$0, VELOCITY
		lw	$t7, GET_ENERGY	
		bgt 	$t7, 30, check_num_smooshed 	### MODIFY ###

		sw	$0, VELOCITY
		li 	$s5, 5
	 	
		#replenish:
		#beq	$s5, $0, check_num_smooshed
		jal	puzzle_main
		#lw	$t7, GET_ENERGY
		#sub	$s5, $s5, 1
		#j	replenish

		check_num_smooshed:
		li	$t0, 10
		sw	$t0, VELOCITY
		la	$t0, num_smooshed
		lw	$t7, 0($t0)
		li	$t2, 5		                ### MODIFY ###
		bgt	$t7, $t2, smash

		follow_target:
		move	$a0, $s3 		# a0 <- id
		jal	scan
		move	$s0, $v0		# &fruit to smoosh
		lw	$s1, 8($s0)		# fruit x value
		lw	$s2, 12($s0)		# fruit y value
		lw	$s3, 0($v0)		# fruit id
		# beq	$v0, $0, follow_target	# if v0 == 0 => the target is gone
		# lw	$s1, 8($s0)		#fruit_X
		lw	$t1, BOT_X
		beq	$t1, $s1, stay
		blt	$t1, $s1, go_right
		j	go_left
	
		go_right:
		li	$a0, 0
		li	$a1, 1
		li	$a2, 10
		jal	set_angle_control_velocity
		j	smooshify
	
		go_left:
		li	$a0, 180
		li	$a1, 1
		li	$a2, 10
		jal 	set_angle_control_velocity
		j	smooshify	

		stay:
		sw	$0, VELOCITY
		j 	smooshify






################################## Helper Functions ################################# 

	#move down to smash fruit and then move back to normal position
	smash:
	lw	$t7, num_smooshed	# if no more fruit left to smash, go back to its y position
	li	$t2, 1
	ble	$t7, $t2, smoosh_again
	li	$a0, 90			# else if fruit still to smash, move down
	li	$a1, 1
	li	$a2, 10
	jal	set_angle_control_velocity
	j	smash


	#go back to smooshing fruits
	smoosh_again:
	li	$a0, 270
	li	$a1, 1
	li	$a2, 10
	jal	set_angle_control_velocity
	j	check_y


	#finds the correct fruit
	# a0 - id: scan for existing fruit
	# v0 - address of the fruit
	scan:
		#scan for fruit
		la	$t0, fruit_data 	# fruit_data
		sw	$t0, FRUIT_SCAN

		#branch to correct scan function
		beq	$a0, $0, scan_for_best_fruit
		j	scan_for_specific_fruit

		#find highest value fruit
		scan_for_best_fruit:
		move	$v0, $t0		# &current fruit
		li	$t1, 0			# highest point value seen so far
		loop_thru_array:
		lw	$t2, 4($t0) 		# current fruit's point value
		lw	$t8, 12($t0)
		add	$t8, $t8, 50		
		lw	$t9, BOT_Y
		beq	$t2, 10, nextfruit
		ble	$t2, $t1, nextfruit
		ble	$t8, $t9, nextfruit
		lw	$t8, 8($t0)		# fruit's X value
		lw	$t9, BOT_X
		sub	$t8, $t8, $t9		#fruit_x - bot_x
		abs	$t8, $t8		#abs value of that
		bge	$t8, 50, nextfruit

		#CHANGES END
		move	$t1, $t2		# update...
		move	$v0, $t0		# update...
		nextfruit:
		lw	$t3, 0($t0)		# current fruit's id
		beq	$t3, $0, scan_end	# if current fruit's id is null
		add	$t0, $t0, 16		# look at next fruit
		j	loop_thru_array

		#find specific fruit
		scan_for_specific_fruit:
		lw	$t1, 0($t0) 			# current fruit's id
		beq	$t1, $0, scan_for_best_fruit	# if current fruit's id is NULL (reached end of array)
		move	$v0, $t0			# load address into $v0
		beq	$t1, $a0, scan_end		# if current fruit's id is the one we're looking for
		add	$t0, $t0, 16			# look at next fruit
		j	scan_for_specific_fruit

		scan_end:
		jr	$ra


	#update angle, angle control, and velocity to given values
	# a0 - angle
	# a1 - angle control
	# a2 - velocity
	set_angle_control_velocity:
		sw	$a0, ANGLE
		sw	$a1, ANGLE_CONTROL
		sw 	$a2, VELOCITY
		jr 	$ra











####################################### PUZZLE ###################################### 
puzzle_main:

	sub	$sp, $sp, 36
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)
	sw	$s5, 24($sp)
	sw	$s6, 28($sp)
	sw	$s7, 32($sp)

	# request puzzle
puzzle_request:
	lw	$s0, puzzle_address	# load fruits to memory
	sw	$s0, REQUEST_PUZZLE

busy_waiting:
	lw	$t0, puzzle_grid_received
	beq	$t0, $0, busy_waiting

	# set puzzle_grid_received to 0 again
	sw	$0, puzzle_grid_received
	
	# request word
	la	$s1, word_address
	sw	$s1, REQUEST_WORD

	# solve puzzle
	li	 $v0, 0			# Set $v0 to 0 to confirm actually returned non-zero
	la	 $a0, puzzle_grid
	la	 $a1, puzzle_word
	sub	 $a1, $a1, 4

	jal	solve_puzzle
	bne	$v0, $0, puzzle_return

	# free memory by new_node_address point to node_memory
	la	$t0, node_memory
	sw	$t0, new_node_address
	j	puzzle_request

puzzle_return:
	move $t0, $v0
	sw   $t0, SUBMIT_SOLUTION
	# free memory by new_node_address point to node_memory
	la	$t0, node_memory
	sw	$t0, new_node_address
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	lw	$s5, 24($sp)
	lw	$s6, 28($sp)
	lw	$s7, 32($sp)
	add	$sp, $sp, 36
	jr	$ra

allocate_new_node:
	lw	$v0, new_node_address
	add	$t0, $v0, NODE_SIZE
	sw	$t0, new_node_address
	jr	$ra

set_node:
	sub	$sp, $sp, 16
	sw	$ra, 0($sp)
	sw	$a0, 4($sp)
	sw	$a1, 8($sp)
	sw	$a2, 12($sp)

	jal	allocate_new_node
	lw	$a0, 4($sp)	# row
	sw	$a0, 0($v0)	# node->row = row
	lw	$a1, 8($sp)	# col
	sw	$a1, 4($v0)	# node->col = col
	lw	$a2, 12($sp)	# next
	sw	$a2, 8($v0)	# node->next = next

	lw	$ra, 0($sp)
	add	$sp, $sp, 16
	jr	$ra

#################################### SOLVE PUZZLE #################################### 
solve_puzzle:
	sub	$sp, $sp, 24
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)

	move	$s0, $a0		# puzzle
	move	$s1, $a1		# word

	lb	$t0, 0($s1)		# word[0]
	beq	$t0, 0, sp_false	# word[0] == '\0'

	li	$s2, 0			# row = 0

sp_row_for:
	lw	$t0, num_rows
	bge	$s2, $t0, sp_false	# !(row < num_rows)

	li	$s3, 0			# col = 0

sp_col_for:
	lw	$t0, num_cols
	bge	$s3, $t0, sp_row_next	# !(col < num_cols)

	move	$a0, $s0		# puzzle
	move	$a1, $s2		# row
	move	$a2, $s3		# col
	jal	get_char		# $v0 = current_char
	lb	$t0, 0($s1)		# target_char = word[0]
	bne	$v0, $t0, sp_col_next	# !(current_char == target_char)

	move	$a0, $s0		# puzzle
	move	$a1, $s2		# row
	move	$a2, $s3		# col
	li	$a3, '*'
	jal	set_char

	move	$a0, $s0		# puzzle
	add	$a1, $s1, 1		# word + 1
	move	$a2, $s2		# row
	move	$a3, $s3		# col
	jal	search_neighbors
	move	$s4, $v0

	move	$a0, $s0		# puzzle
	move	$a1, $s2		# row
	move	$a2, $s3		# col
	lb	$a3, 0($s1)		# word[0]
	jal	set_char

	bne	$s4, $0, sp_true

sp_col_next:
	add	$s3, $s3, 1		# col++
	j	sp_col_for

sp_row_next:
	add	$s2, $s2, 1		# row++
	j	sp_row_for

sp_false:
	li	$v0, 0			# false
	j	sp_done


# Node * head = set_node(row, col, exist);
# return head;
sp_true:
	move	$a0, $s2
	move	$a1, $s3
	move	$a2, $s4
	jal	set_node
	# move $v0, $s4
	# li	$v0, 1			# true

sp_done:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	add	$sp, $sp, 24
	jr	$ra


################################## SEARCH NEIGHBORS ################################## 
## Node * search_neighbors(char *puzzle, const char *word, int row, int col)
search_neighbors:
	bne	$a1, 0, sn_main		# !(word == NULL)
	li	$v0, 0			# return NULL (data flow)
	jr	$ra			# return NULL (control flow)

sn_main:
	sub	$sp, $sp, 36
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)
	sw	$s5, 24($sp)
	sw	$s6, 28($sp)
	sw	$s7, 32($sp)

	move	$s0, $a0		# puzzle
	move	$s1, $a1		# word
	move	$s2, $a2		# row
	move	$s3, $a3		# col
	li	$s4, 0			# i

sn_loop:
	mul	$t0, $s4, 8		# i * 8
	lw	$t1, directions($t0)	# directions[i][0]
	add	$s5, $s2, $t1		# next_row
	lw	$t1, directions+4($t0)	# directions[i][1]
	add	$s6, $s3, $t1		# next_col

	ble	$s5, -1, sn_next	# !(next_row > -1)
	lw	$t0, num_rows

	blt	$s5, $t0, sn_skip1 	# (next_row < num_rows)
	sub	$s5, $s5, $t0 		# next_row -= num_rows
sn_skip1:
	ble	$s6, -1, sn_next	# !(next_col > -1)
	lw	$t0, num_cols
	blt	$s6, $t0, sn_skip2	# (next_col < num_cols)
	sub	$s6, $s6, $t0 		# next_col -= num_cols

sn_skip2:
	mul	$t0, $s5, $t0		# next_row * num_cols
	add	$t0, $t0, $s6		# next_row * num_cols + next_col
	add	$s7, $s0, $t0		# &puzzle[next_row * num_cols + next_col]
	lb	$t0, 0($s7)		# puzzle[next_row * num_cols + next_col]
	lb	$t1, 0($s1)		# *word
	bne	$t0, $t1, sn_next	# !(puzzle[next_row * num_cols + next_col] == *word)

	lb	$t0, 1($s1)		# *(word + 1)
	bne	$t0, 0, sn_search	# !(*(word + 1) == '\0')
	move	$a0, $s5		# next_row
	move	$a1, $s6		# next_col
	li	$a2, 0			# NULL
	jal	set_node		# $v0 will contain return value
	j	sn_return

sn_search:
	li	$t0, '*'
	sb	$t0, 0($s7)		# puzzle[next_row * num_cols + next_col] = '*'
	move	$a0, $s0		# puzzle
	add	$a1, $s1, 1		# word + 1
	move	$a2, $s5		# next_row
	move	$a3, $s6		# next_col
	jal	search_neighbors
	lb	$t0, 0($s1)		# *word
	sb	$t0, 0($s7)		# puzzle[next_row * num_cols + next_col] = *word
	beq	$v0, 0, sn_next		# !next_node
	move	$a0, $s5		# next_row
	move	$a1, $s6		# next_col
	move	$a2, $v0		# next_node
	jal	set_node
	j	sn_return

sn_next:
	add	$s4, $s4, 1		# i++
	blt	$s4, 4, sn_loop		# i < 4
	
	li	$v0, 0			# return NULL (data flow)

sn_return:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	lw	$s5, 24($sp)
	lw	$s6, 28($sp)
	lw	$s7, 32($sp)
	add	$sp, $sp, 36
	jr	$ra

get_char:
	lw	$v0, num_cols
	mul	$v0, $a1, $v0	# row * num_cols
	add	$v0, $v0, $a2	# row * num_cols + col
	add	$v0, $a0, $v0	# &array[row * num_cols + col]
	lb	$v0, 0($v0)	# array[row * num_cols + col]
	jr	$ra

set_char:
	lw	$v0, num_cols
	mul	$v0, $a1, $v0	# row * num_cols
	add	$v0, $v0, $a2	# row * num_cols + col
	add	$v0, $a0, $v0	# &array[row * num_cols + col]
	sb	$a3, 0($v0)	# array[row * num_cols + col] = c
	jr	$ra










##################################### INTERRUPT HANDLER #####################################

protect_interrupt_handler: 
	j	protect_interrupt_handler


.kdata					# interrupt handler data (separated just for readability)
chunkIH:	.space 8		# space for two registers
non_intrpt_str:	.asciiz "Non-interrupt exception\n"
unhandled_str:	.asciiz "Unhandled interrupt type\n"


.ktext 0x80000180
interrupt_handler:
.set noat
	move	$k1, $at		# Save $at                               
.set at
	la	$k0, chunkIH
	sw	$a0, 0($k0)		# Get some free registers                  
	sw	$a1, 4($k0)		# by storing them to a global variable     
	sw	$t0, 8($k0)    
	sw	$t1, 12($k0)
	sw	$t2, 12($k0)

	mfc0	$k0, $13		# Get Cause register                       
	srl	$a0, $k0, 2                
	and	$a0, $a0, 0xf		# ExcCode field                            
	bne	$a0, 0, non_intrpt         


interrupt_dispatch:			# Interrupt:                             
	mfc0	$k0, $13		# Get Cause register, again                 
	beq	$k0, 0, done		# handled all outstanding interrupts     

	and	$a0, $k0, BONK_MASK	# is there a bonk interrupt?                
	bne	$a0, 0, bonk_interrupt   

	and	$a0, $k0, PUZZLE_MASK
	bne	$a0, 0, puzzle_request_interrupt

	and	$a0, $k0, SMOOSHED_MASK	# is there a smooshed interrupt?
	bne	$a0, 0, smooshed_interrupt

	# add dispatch for other interrupt types here.

	li	$v0, PRINT_STRING	# Unhandled interrupt types
	la	$a0, unhandled_str
	syscall 
	j	done

bonk_interrupt:
	sw	$zero, VELOCITY		# stop bot

	# check the num_smooshed whether to FRUIT_SMASH
	la	$t0, num_smooshed												#!!!
	lw	$t1, 0($t0)
	li	$t2, 1
	ble	$t1, $t2, bonk_end

	sub	$t1, $t1, 1		# num_smooshed--
	sw	$t1, 0($t0)

	bgt	$t1, $zero, bonk_skip
	li	$t0, 270
	sw	$t0, ANGLE
	li	$t0, 1
	sw	$t0, ANGLE_CONTROL
bonk_skip:
	li	$t0, 1			# write anything to fruit_smash
	sw	$t0, FRUIT_SMASH
bonk_end:
	sw	 $a1, BONK_ACK		# acknowledge interrupt
	j	 interrupt_dispatch	# see if other interrupts are waiting

	# SMASH FRUIT
	# smash:
	# lw	$t7, num_smooshed	
	# sw	$t7, FRUIT_SMASH	# smash fruit
	# sub	$t7, $t7, 1		# decrement num_smooshed
	# sw	$t7, num_smooshed
	# li 	$t8, 1
	# ble	$t7, $t8, done_smashing # if num_smooshed is 0, stop smashing
	# j	smash

	# done_smashing:
	# sw	$a1, BONK_ACK		# acknowledge interrupt	
	# j	interrupt_dispatch	# see if other interrupts are waiting

puzzle_request_interrupt:
	li	$t7, 1
	sw	$t7, puzzle_grid_received
	sw	$a1, PUZZLE_ACK
	j	interrupt_dispatch

smooshed_interrupt:
	sw	$a1, SMOOSHED_ACK	# acknowledge interrupt
	lw	$t7, num_smooshed	# increment num_smooshed
	add	$t7, $t7, 1
	sw	$t7, num_smooshed
	j	interrupt_dispatch	# see if other interrupts are waiting


non_intrpt:				# was some non-interrupt
	li	$v0, PRINT_STRING
	la	$a0, non_intrpt_str
	syscall				# print out an error message
	# fall through to done


done:
	la	$k0, chunkIH
	lw	$a0, 0($k0)		# Restore saved registers
	lw	$a1, 4($k0)
	lw	$t0, 8($k0)
	lw	$t1, 12($k0)
	lw	$t2, 12($k0)
.set noat
	move	$at, $k1		# Restore $at
.set at 
	eret



