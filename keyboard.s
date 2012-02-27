.intel_syntax noprefix

# PS/2:
KB_FLAG_OBF	= 0b00000001	# Output buffer full
KB_FLAG_IBF	= 0b00000010	# Output buffer full
KB_FLAG_SYS	= 0b00000100	# POST: 0: power-on reset; 1: BAT code, powered
KB_FLAG_A2	= 0b00001000	#

KB_FLAG_INH	= 0b00010000	# Communication inhibited
KB_FLAG_MOBF	= 0b00100000	# PS2: OBF for mouse; AT: TxTO (timeout)
KB_FLAG_TO	= 0b01000000	# PS2: Timeout; AT: RxTO
KB_FLAG_PERR	= 0b10000000	# Parity Error


.data
old_kb_isr: .word 0, 0
.text
.code16
hook_keyboard_isr16:
	push	fs
	push	eax
	cli
	push	0
	pop	fs
	mov	eax, fs:[9 * 4]
	mov	[old_kb_isr], eax
	mov	fs:[ 9 * 4], word ptr offset isr_keyboard16
	mov	fs:[ 9 * 4 + 2], cs
	pop	eax
	pop	fs
	sti
	ret

restore_keyboard_isr16:
	cli
	push	fs
	push	eax
	push	0
	pop	fs
	mov	eax, [old_kb_isr]
	mov	fs:[ 9 * 4], eax
	pop	eax
	pop	fs
	sti
	ret

.data
scr_o: .word 7 * 160
.text
.code16
isr_keyboard16:
	push	es
	push	di
	push	ax

	push	0xb800
	pop	es
	mov	di, [scr_o]
	mov	ah, 0x90
0:	in	al, 0x64
	and	al, 1
	jz	0b

	in	al, 0x60

	mov	dl, al
	call	printhex2
	mov	[scr_o], di

	mov	al, 0x20 # send EOI
	out	0x20, al
	pop	ax
	pop	di
	pop	es

	iret

.code32
isr_keyboard32:
	push	ds
	push	es
	push	edi
	push	eax
	push	dx

	mov	ax, SEL_compatDS
	mov	ds, ax

	call	buf_avail
	jle	2f

	# debug
	mov	ax, SEL_vid_txt
	mov	es, ax
	xor	edi, edi
	mov	di, [scr_o]

	mov	ah, 0x90
#0:	in	al, 0x64
#	and	al, 1
#	jz	0b

	in	al, 0x60

	#################
.if 1
	cmp	al, 0xe0	# escape code
	jne	0f

	# signal ready to read next byte without sending EOI
	in	al, 0x61
	or	al, 0x80
	out	0x61, al
	and	al, 0x7f
	out	0x61, al

	# read next byte

	in	al, 0x60	

	# split make/break code

	mov	ah, al	# invert break code (0x80) to 1 on make
	not	ah
	shr	ah, 7

	and	al, 0x7f	# al = key

	.data
		keys_pressed: .space 128
		kb_shift: .byte 0
		kb_caps: .byte 0
		keymap:
		.byte 0, 0 	# 00: error code
		.byte 0x1b, 1;	# 01: escape	BIOS: 0x011b

		.byte '1', '!'	# 02
		.byte '2', '@'	# 03
		.byte '3', '#'	# 04
		.byte '4', '$'	# 05
		.byte '5', '%'	# 06
		.byte '6', '^'	# 07
		.byte '7', '&'	# 08
		.byte '8', '*'	# 09
		.byte '9', '('	# 0a
		.byte '0', ')'	# 0b
		.byte '-', '_'	# 0c
		.byte '=', '+'	# 0d
		.byte 0, 0	# 0e backspace

		.byte '\t','\t' # 0f tab
		.byte 'q', 'Q'	# 10
		.byte 'w', 'W'	#
		.byte 'e', 'E'	#
		.byte 'r', 'R'	#
		.byte 't', 'T'	#
		.byte 'y', 'Y'	#
		.byte 'u', 'U'	#
		.byte 'i', 'I'	#
		.byte 'o', 'O'	#
		.byte 'p', 'P'	#
		.byte '[', '{'	#
		.byte ']', '}'	# 1b
		.byte 0x0d, 0x0d# 1c enter

		.byte 0, 0	# 1d Left Control
		.byte 'a', 'A'	# 1e
		.byte 's', 'S'	#
		.byte 'd', 'D'	#
		.byte 'f', 'F'	#
		.byte 'g', 'G'	#
		.byte 'h', 'H'	#
		.byte 'j', 'J'	#
		.byte 'k', 'K'	#
		.byte 'l', 'L'	#
		.byte ';', ':'	#
		.byte ''', '"'	# 28

		.byte '`', '~'	# 29

		.byte 0, 0	# 2a Left Shift
		.byte '\', '|'	# 2b
		.byte 'z', 'Z'	# 2c
		.byte 'x', 'X'	#
		.byte 'c', 'C'	#
		.byte 'v', 'V'	#
		.byte 'b', 'B'	#
		.byte 'n', 'N'	#
		.byte 'm', 'M'	#
		.byte ',', '<'	#
		.byte '.', '>'	#
		.byte '/', '?'	# 35
		.byte 0, 0	# 36 Right Shift

		.byte '*', 0	# 37 Keypad * / PrtScrn
		.byte 0, 0	# 38 Left Alt
		.byte ' ', ' '	# 39 Space Bar
		.byte 0, 0	# 3a Caps Lock

		.byte 0,0	# 3b F1
		.byte 0,0	# 3c F2
		.byte 0,0	# 3d F3
		.byte 0,0	# 3e F4
		.byte 0,0	# 3f F5
		.byte 0,0	# 40 F6
		.byte 0,0	# 41 F7
		.byte 0,0	# 42 F8
		.byte 0,0	# 43 F9
		.byte 0,0	# 44 F10

		.byte 0,0	# 45 Num Lock
		.byte 0,0	# 46 Scroll Lock
		.byte 0,0	# 47 Keypad 7 / Home
		.byte 0,0	# 48 Keypad 8 / Up
		.byte 0,0	# 49 Keypad 9 / PgUp
		.byte 0,0	# 4a Keypad -
		.byte 0,0	# 4b Keypad 4 / Left
		.byte 0,0	# 4c Keypad 5
		.byte 0,0	# 4d Keypad 6 / Right
		.byte 0,0	# 4e Keypad +
		.byte 0,0	# 4f Keypad 1 / End
		.byte 0,0	# 50 Keypad 2 / Down
		.byte 0,0	# 51 Keypad 3 / PgDn
		.byte 0,0	# 52 Keypad 0 / Ins
		.byte 0,0	# 53 Keypad Del

		.byte 0,0	# 54 Alt-SysRq
		.byte 0,0	# 55 less common: F11/F12/PF1/FN
		.byte 0,0	# 56 unlabeled key left/right of left alt

		.byte 0,0	# 57 F11
		.byte 0,0	# 58 F12
	.text

	mov	dx, ax
	and	edx, 0xff
	mov	[keys_pressed + edx], ah

	# Check for shift key

	cmp	al, 0x2a	# left shift
	je	1f
	cmp	al, 0x36	# right shift
	jne	0f
1:	# have shift!
	mov	[kb_shift], ah
	jmp	3f

0:	cmp	al, 0x3a	# caps lock
	jne	0f
	mov	al, [kb_caps]	# TODO: need to find init state
	xor	al, 1
	mov	[kb_caps], al
	jmp	3f

0:	or	ah, ah
	jz	3f	# only store keys that are pressed

	# translate 
	mov	dx, ax
	and	edx, 0x7f
	shl	dx, 1
	xor	ah, [kb_caps]
	add	dl, ah # shift 
	# adc not needed as low bit was/is 0
	shl	ax, 8 # preserve scancode
	mov	al, [keymap + edx]
.endif

3:	#################
	call	buf_putw

	mov	dx, ax
	mov	ah, 0xf1
	call	printhex_32
	mov	ah, 0xf2
	stosw
	add	di, 2
	mov	[scr_o], di
2:
	PIC_SEND_EOI IRQ_KEYBOARD
	pop	dx
	pop	eax
	pop	edi
	pop	es
	pop	ds
	iret


.code32
hook_keyboard_isr32:
	pushf
	cli
	mov	al, 0x20 # [pic_ivt_offset]
	add	al, IRQ_KEYBOARD
	mov	cx, SEL_compatCS
	mov	ebx, offset isr_keyboard32
	call	hook_isr32
	
	PIC_ENABLE_IRQ IRQ_KEYBOARD

	PRINT_32 "KB Status: "
	in	al, 0x64
	mov	dl, al
	mov	ah, 0xf0
	call	printhex2_32
	call	printbin8_32
	popf
	ret


.data
KB_BUF_SIZE = 32
# circular buffer, hardware-software thread safe due to separate read/write
# variables. The read offset is however not software-software thread safe.
keyboard_buffer:	.space KB_BUF_SIZE
keyboard_buffer_ro:	.long 0	# write offset
keyboard_buffer_wo:	.long 0 # read offset
kb_count$: .long 0
.text

buf_err$:
	pushf
	push	es
	push	edi
	push	edx
	mov	edx, eax
	mov	ah, 0xf4
	SCREEN_INIT
	PRINT_32 "Buffer Assertion Error: avail: "
	call	printhex8_32
	PRINT_32 " R="
	mov	edx, [keyboard_buffer_ro]
	call	printhex_32
	PRINT_32 " W="
	mov	edx, [keyboard_buffer_wo]
	call	printhex_32
	pop	edx
	pop	edi
	pop	es
	popf
	ret

buf_avail:
	# shift view: wo = origin.
	mov	eax, [keyboard_buffer_ro]
	sub	eax, [keyboard_buffer_wo]
	dec	eax
	jge	0f
	# wo < 0, so ad KB_BUF_SIZE
	add	eax, KB_BUF_SIZE
	js	buf_err$ # shouldnt happen..
0:	ret

buf_putw:
	push	ebx
	mov	ebx, [keyboard_buffer_wo]
	mov	[keyboard_buffer + ebx], ax
	add	ebx, 2
	jmp	buf_put_$

buf_putb:
	push	ebx
	mov	ebx, [keyboard_buffer_wo]
	mov	[keyboard_buffer + ebx], al
	inc	ebx
	jmp	buf_put_$

buf_put_$:
	cmp	ebx, KB_BUF_SIZE-1
	jb	0f
	xor	ebx, ebx
0:	mov	[keyboard_buffer_wo], ebx
	pop	ebx
	ret


##########################################################################
### Public API 
##########################################################################

# Potential multitasking problems:
# Writing to IO port. The last port written/read needs to be synchronous,
# so when an IRQ occurs, or when another task reads/writes from the
# IO port, this corrupts communication.
# IRQ's can be disabled by cli; for port access, this needs to be protected
# using CPL0 and a taskgate that only runs on one CPU at a time. Trusting
# on the task switching's recursion preventing should then provide a means
# to have only one task that deals with a specific IO port.
keyboard:
	push	ds
	push	esi
	mov	si, SEL_compatDS
	mov	ds, si

	or	ah, ah
	jz	k_get$
	cmp	ah, 1
	jz	k_peek$
	cmp	ah, 2
	jz	k_getshift$
	cmp	ah, 3
	jz	k_setspeed$
0:	pop	esi
	pop	ds
	ret

#Int 16/AH=09h - KEYBOARD - GET KEYBOARD FUNCTIONALITY
#Int 16/AH=0Ah - KEYBOARD - GET KEYBOARD ID
#Int 16/AH=10h - KEYBOARD - GET ENHANCED KEYSTROKE (enhanced kbd support only)
#Int 16/AH=11h - KEYBOARD - CHECK FOR ENHANCED KEYSTROKE (enh kbd support only)
#Int 16/AH=12h - KEYBOARD - GET EXTENDED SHIFT STATES (enh kbd support only)

k_get$:	
	mov	esi, [keyboard_buffer_ro]
1:	cmp	esi, [keyboard_buffer_wo]
	jnz	1f
	hlt		# wait for interrupt
	jmp	1b	# check again
1:	mov	ax, [keyboard_buffer + esi]
	add	esi, 2
	cmp	esi, KB_BUF_SIZE
	jl	1f
	sub	esi, KB_BUF_SIZE
1:	mov	[keyboard_buffer_ro], esi
	jmp	0b
k_peek$:
	mov	esi, [keyboard_buffer_ro]
	cmp	esi, [keyboard_buffer_wo]
	jz	0b
	mov	ax, [keyboard_buffer + esi]
	jmp	0b
k_getshift$:
	jmp	0b
k_setspeed$:
	jmp	0b


KB_GET		= 0
KB_PEEK		= 1
KB_GETSHIFT	= 2
KB_SETSPEED	= 3
int32_16h_keyboard:
	call	keyboard

	push	ebp		# update flags
	mov	ebp, esp
	push	eax
	pushfd
	pop	eax
	mov	[ebp + 6], eax
	pop	eax
	pop	ebp

	iret