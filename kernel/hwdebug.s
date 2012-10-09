.intel_syntax noprefix
.text32

# debug registers:
# DR7	Debug Control register
#	lnRWlnRWlnRWlnRW..G...GLGLGLGLGL
/*	3333222211110000ooDooiEE33221100*/
#
#	len3[2] | len2[2] | len1[2] | len0[2]
#
#	L0, L1, L2, L3 (bits 0, 2, 4, 6): local breakpoint enable (cur task)
#		on task switch these are cleared.
#	G0, G1, G2, G3 (bits 1, 3, 5, 7): global breakpoint enable (all tasks)
#		on task switch these remain the same.
#	LE (bit 8) local exact breakpoint enable
#	GE (bit 9) global exact breakpoint enable
#		LE and GE are not commonly supported in newer architectures.
#	GD (bit 13): general detect; enable debug register protection, by
#	  triggering the debug interrupt when the next instr refs DR0..7.
#	RW0..RW3 (bits 16,17, 20,21, 24,25, 28,29).
#	  When CR4.DE (debug extensions) = 1:
#		00 = break on instruction execution only
#		01 = break on data writes only
#		10 = break on I/O reads or writes
#		11 = break on data reads or writes but not instruction fetches
#	  When CR4.DE is clear (386/486 compatible):
#		00 = break on instruction execution only
#		01 = break on data writes only
#		10 = undefined
#		11 = break on data reads or writes but not instruction fetches
#	LEN0..LEn3: data length:
#		00 = 1 byte	(requred when RWx = 00 (execution))
#		01 = 2 byte
#		10 = udnefined / 8 bytes
#		11 = 4 byte

# DR6	debug status register 0xffff << 16 | BT BS BD | 011111111 | B3 B2 B1 B0
#	b3..b0: breakpoint condition detected; only valid when DR7 Ln or Gn set
#	BD (bit 13): next instr accesses DR0..7; only valid when DR7.GD is set
#	BS (bit 14): interrupt cause is single step (TF flag in EFLAGS)
#	BT (bit 15): interrupt cause is task switch (Trap flag in TSS set)
# DR5	alias for DR7; #UD invalid opcode exception on access when CR4.DE == 0
# DR4 	alias for DR6; #UD invalid opcode exception on access when CR4.DE == 0
# DR3	Linear address 3
# DR2	linear address 2
# DR1	linear address 1
# DR0	linear address 0

# in: eax = mem address
breakpoint_enable_memwrite_dword:
enable_breakpoint_memwrite_dword:
	DEBUG "Set breakpoint: addr:"
	DEBUG_DWORD eax
	GDT_GET_BASE ebx, ds
	add	eax, ebx
	DEBUG " hw addr:"
	DEBUG_DWORD eax


breakpoint_set_memwrite_dword:
	mov	ebx, dr7
	#	ebx, 0b11111111111111110010011111111111 # 0=reserved bit
	#              f   f   f   f   2   7   aabbccdd

	test	al, 1
	jz	1f
	# not byte aligned; DR0 = first byte, DR1 = last byte, DR2 = middle word
	mov	dr0, eax
	add	eax, 3
	mov	dr1, eax
	sub	eax, 2
	mov	dr2, eax
	#	......|....MidlLastFrst
	and	ebx, 0b11110000000000001111111111111111 # clear bits to change
	or	ebx, 0b00000101000100010000000000010101 # len 1, data wr only
	mov	dr7, ebx

	ret

1:	test	al, 2
	jz	0f

	mov	dr0, eax
	add	eax, 2
	mov	dr1, eax      #SECNfrst
	and	ebx, 0b11111111000000001111111111111111 # clear bits to change
	or	ebx, 0b00000000010101010000000000000101 # len 2 Write, len 2 write
	mov	dr7, ebx
	ret

0:
	mov	dr0, eax	# use 4th register

	###############lnRWlnRWlnRWlnRW..G...GLGLGLGLGL
	###############3333222211110000ooDooiEE33221100
	#and	eax, 0b11111111111111110010011111111111
	#	.......####
	and	ebx, 0b11111111111100001111111111111111 # clear bits to change
	or	ebx, 0b00000000000011010000000000000001 # len 4, data wr only

	mov	dr7, ebx
	ret


breakpoint_set_memwrite_word:
	mov	ebx, dr7
	test	al, 1
	jz	1f

	mov	dr0, eax
	inc	eax
	mov	dr1, eax
		#              LLRWLLRW  LL=00=byte
	and	ebx, 0b11111111000000001111111111111111 # clear bits to change
	or	ebx, 0b00000000000100010000000000000101 # len 1, data wr only
	mov	dr7, ebx
	ret

1:	# word aligned
	mov	dr0, eax
		#      ............LLRW LL=01=word
	and	ebx, 0b11111111111100001111111111111111 # clear bits to change
	or	ebx, 0b00000000000001010000000000000001 # len 1, data wr only
	mov	dr7, ebx
	ret

breakpoint_set_memwrite_byte:
	mov	ebx, dr7
	mov	dr0, eax
	and	ebx, 0b11111111111100001111111111111111 # clear bits to change
	or	ebx, 0b00000000000000010000000000000101 # len 1, data wr only
	mov	dr7, ebx
	ret

# in: eax = address
# in: bl = size: 1, 2, 3
breakpoint_set_memwrite:

	test	bl, ~3
	jnz	9f
	or	bl, bl
	jz	breakpoint_set_code

	push	edx
	pushcolor 0xe0
	printc	0xe1, "Breakpoint: "
	mov	edx, eax
	call	printhex8
	GDT_GET_BASE edx, ds
	add	eax, edx
	mov	edx, eax
	printc	0xe1 " (phys addr: "
	call	printhex8
	printc	0xe1, ") size "
	push	ecx
	mov	cl, bl
	dec	cl
	mov	edx, 1
	shl	edx, cl
	pop	ecx
	call	printhex1
	mov	edx, [eax]
	printc 0xe1, " cur value: "
	mov	edx, [eax]
	call	printhex8
	call	printspace
	call	printhex2
	shr	edx, 8
	call	printhex2
	shr	edx, 8
	call	printhex2
	shr	edx, 8
	call	printhex2
	call	newline
	popcolor
	pop	edx

	cmp	bl, 3
	jz	breakpoint_set_memwrite_dword
	cmp	bl, 2
	jz	breakpoint_set_memwrite_word
	cmp	bl, 1
	jz	breakpoint_set_memwrite_byte

9:	printlnc 4, "breakpoint_set_memwrite: wrong size: "
	push	edx
	movzx	edx, bl
	call	printdec32
	pop	edx
	printlnc 4, " - not 1, 2 or 3"
	stc
	jmp	0b


# in: eax = address
breakpoint_set_code:
	printlnc 0xe4, "code breakpoint not implemented yet"
	ret
