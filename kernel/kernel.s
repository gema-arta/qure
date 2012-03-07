.intel_syntax noprefix

.include "print.s" # declarations only

.text
.code16

	.macro PRINT_16 m
		.data
			9:.asciz "\m"
		.text
		push	si
		mov	si, offset 9b
		call	print_16
		pop	si
	.endm

	.macro PRINTLN_16 m
		PRINT_16 "\m"
		call	newline_16
	.endm

	.macro PH8_16 m x
		PRINT_16 "\m"
		.if \x != edx
		push	edx
		mov	edx, \x
		pop	edx
		.endif
		call	printhex8_16
	.endm

	.macro rmCOLOR c
		mov	[screen_color], byte ptr \c
	.endm


kmain:
	mov	ax, 0x0f00
	xor	di, di
	mov	cx, 160*25
	rep	stosd
	xor	di, di
	mov	al, '!'
	stosw

	mov	ax, cs
	mov	ds, ax

####### print hello

	println_16 "Kernel booting"

	print_16 "CS:IP "
	mov	dx, ax
	mov	ah, 0xf2
	call	printhex_16
	call	0f
0:	pop	dx
	sub	dx, offset 0b
	call	printhex_16

	print_16 "Kernel Size: "
	mov	edx, KERNEL_SIZE - kmain
	call	printhex8_16

	# print signature
	print_16 "Signature: "
	mov	edx, [sig] # [KERNEL_SIZE - 4]
	rmCOLOR	0x0b
	call	printhex8_16
	rmCOLOR	0x0f
	call	newline_16

.if 0
	mov	cx, 21
	mov	bx, offset kmain
0:	mov	dx, bx
	rmCOLOR	0x07
	call	printhex_16
	rmCOLOR	0x08
	mov	edx, [bx]
	call	printhex8_16
	call	newline_16
	add	bx, 0x200
	loop	0b
.endif

####### enter protected mode

	println_16 "Entering protected mode"
	mov	ax, 0

	# make it return elsewhere
	push	word ptr offset kentry
	jmp	protected_mode
################################
#### Console/Print #############
.code16
################################
#### 16 bit debug functions ####
.macro PRINT_START_16
	push	es
	push	di
	push	ax
	mov	ax, 0xb800
	mov	es, ax
	mov	di, [screen_pos]
	mov	ah, [screen_color]
.endm

.macro PRINT_END_16
	mov	[screen_pos], di
	pop	ax
	pop	di
	pop	es	
.endm


printhex_16:
	push	ecx
	mov	ecx, 4
	rol	edx, 16
	jmp	1f
printhex2_16:
	push	ecx
	mov	ecx, 2
	rol	edx, 24
	jmp	1f
printhex8_16:
	push	ecx
	mov	ecx, 8
1:	PRINT_START_16
0:	rol	edx, 4
	mov	al, dl
	and	al, 0x0f
	cmp	al, 10
	jl	1f
	add	al, 'A' - '0' - 10
1:	add	al, '0'
	stosw
	loop	0b
	add	di, 2
	PRINT_END_16
	pop	ecx
	ret

newline_16:
	push	ax
	push	dx
	mov	ax, [screen_pos]
	mov	dx, 160
	div	dl
	mul	dl
	add	ax, dx
	mov	[screen_pos], ax
	pop	dx
	pop	ax
	ret

print_16:
	PRINT_START_16
0:	lodsb
	or	al, al
	jz	1f
	stosw
	jmp	0b
1:	PRINT_END_16
	ret

###################################

DEFINE = 1
.include "print.s"
.include "pmode.s"
.include "keyboard.s"

###################################

.code32
kentry:
	# we're in flat mode, so set ds so we can use our data..
	mov	ax, SEL_compatDS
	mov	ds, ax

#	mov	edx, 0xf00ba4
#	call	printhex8
	PRINT "Protected mode initialized."


halt:	call	newline
	PRINTc	0xb, "System Halt."
0:	hlt
	jmp	0b




.data
sig:.long 0x1337c0de
.equ KERNEL_SIZE, .
