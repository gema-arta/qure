#############################################################################
#
# OOFS Volume Descriptor
#
# This simple class maintains an array of {LBA, sectors} (regions)
# in the first (few) sector(s) of the partition.
#
# It further provides a dynamic array containing class instances (objects)
# associated with the regions, which can be initialized by calling the
# load_entry( index, class ) method, which instantiates the object,
# and calls the constructor passing along the LBA and sectors.
#
# NOTE THIS ODDITY:
#
#  The first entry in the instance array is a self-reference!
#
#  The first entry in that array describes the volume descriptor itself,
#  specifying (at current) a use of 1 sector, even though this class
#  manages the entire partition.
#
#
.intel_syntax noprefix

.global class_oofs_vol

.global oofs_vol_api_get_obj
.global oofs_vol_api_add
.global oofs_vol_api_delete
.global oofs_vol_api_load_entry
.global oofs_vol_api_lookup

.global oofs_get_by_lba	# non-virtual method

.struct 0
oofs_el_sectors:	.long 0
oofs_el_lba:	.long 0
OOFS_EL_STRUCT_SIZE = 8

.macro OOFS_IDX_TO_EL reg
	.if OOFS_EL_STRUCT_SIZE == 8
	shl	\reg, 3
#	.elseif OOFS_EL_STRUCT_SIZE == 16
#	shl	\reg, 4
	.else
	.error "OOFS_EL_STRUCT_SIZE != 16, 8"
	.endif
.endm

DECLARE_CLASS_BEGIN oofs_vol, oofs_persistent
oofs_children:	.long 0	# ptr array

oofs_vol_persistent:
oofs_magic:	.long 0
oofs_count:	.long 0
oofs_array:	# {oofs_el_obj, oofs_el_sectors}[]
# direct access to first entry: special semantics: free space

.org oofs_vol_persistent + 512	# make data struct size at least 1 sector


DECLARE_CLASS_METHOD oofs_api_init, oofs_vol_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_vol_print, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_child_moved, oofs_vol_child_moved, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_vol_load, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_onload, oofs_vol_onload, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_vol_save, OVERRIDE

DECLARE_CLASS_METHOD oofs_vol_api_add, oofs_vol_add
DECLARE_CLASS_METHOD oofs_vol_api_delete, oofs_vol_delete
DECLARE_CLASS_METHOD oofs_vol_api_load_entry, oofs_vol_load_entry
DECLARE_CLASS_METHOD oofs_vol_api_get_obj, oofs_vol_get_obj
DECLARE_CLASS_METHOD oofs_vol_api_lookup, oofs_vol_lookup
DECLARE_CLASS_END oofs_vol
#################################################
.text32
# in: eax = instance
# in: edx = parent
# in: ecx = persistent size (sectors)
oofs_vol_init:
	.if OOFS_DEBUG
		DEBUG_CLASS; printlnc 14, ".oofs_vol_init"
	.endif

	call	oofs_persistent_init	# super.init()
	jc	9f

	push_	eax edx ebx

	mov	ebx, eax

	mov	eax, 10	# init cap
	call	ptr_array_new
	jc	91f
	mov	[ebx + oofs_children], eax

	mov	[ebx + oofs_magic], dword ptr OOFS_MAGIC
	mov	[ebx + oofs_lba], dword ptr 0	# first sector

	mov	[ebx + oofs_count], dword ptr 1
	# first array element: self-referential entry recording the vol sector
	mov	[ebx + oofs_array + 0 + oofs_el_sectors], dword ptr 1
	mov	[ebx + oofs_array + 0 + oofs_el_lba], dword ptr 0
	call	ptr_array_newentry
	jc	91f
	mov	[eax + edx], ebx	# children[0] = this
	# second entry: free space (always last entry)
	dec	ecx
	mov	[ebx + oofs_array + OOFS_EL_STRUCT_SIZE + oofs_el_sectors], ecx
	inc	ecx
	mov	[ebx + oofs_array + OOFS_EL_STRUCT_SIZE + oofs_el_lba], dword ptr 1

0:	pop_	ebx edx eax
9:	STACKTRACE 0
	ret
91:	printlnc 4, "oof_vol_init: ptr_array error"
	stc
	jmp	0b

# in: eax = this
oofs_vol_save:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14 ".oofs_vol_save"
		printc 9, " LBA="
		pushd	[eax + oofs_lba]
		call	_s_printhex8
		printc 9, " array.count="
		pushd	[eax + oofs_count]
		call	_s_printhex8
		call	newline
	.endif

.if 1
	push_	ecx edx esi
	mov	edx, offset oofs_vol_persistent
	lea	esi, [eax + oofs_vol_persistent]
	mov	ecx, [eax + oofs_count]
	inc	ecx
	OOFS_IDX_TO_EL ecx
	add	ecx, offset oofs_array - offset oofs_vol_persistent
	call	[eax + oofs_persistent_api_write]
	pop_	esi edx ecx
.else
	push_	eax ebx ecx esi edx
	mov	ebx, [eax + oofs_lba]
	mov	ecx, [eax + oofs_count]
	inc	ecx	# add the final free space entry
	OOFS_IDX_TO_EL ecx
	lea	ecx, [ecx + oofs_array - oofs_vol_persistent]
	lea	esi, [eax + oofs_vol_persistent]

	mov	eax, [eax + oofs_persistence]
	mov	edx, [eax + obj_class]
	call	[eax + fs_obj_api_write]
	pop_	edx esi ecx ebx eax
.endif
	ret

# in: eax = instance
# out: eax = mreallocced instance if needed
oofs_vol_load:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printlnc 14, ".oofs_vol_load"
	.endif

	push_	ecx edx edi
	lea	edi, [eax + oofs_vol_persistent]
	mov	ecx, 512	# read 1 sector
	call	[eax + oofs_persistent_api_read]	# out: eax=this
	# update first entry:
	mov	edx, [eax + oofs_children]
	mov	[edx], eax
	pop_	edi edx ecx
	jc	9f

	call	[eax + oofs_persistent_api_onload]

9:	STACKTRACE 0
	ret


oofs_vol_onload:
	push_	ecx edx

	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_vol_onload"
	.endif

	cmp	[eax + oofs_magic], dword ptr OOFS_MAGIC
	jnz	91f

	.if OOFS_DEBUG
		printc 10, " (sig ok)";
		printc 10, " count="
		pushd	[eax + oofs_count]
		call	_s_printhex8
	.endif

	mov	ecx, [eax + oofs_count]
	inc	ecx	# also load the free size at end
	OOFS_IDX_TO_EL ecx
	lea	ecx, [ecx + oofs_vol_persistent]
	cmp	ecx, 512
	cmc
	jae	1f	# it'll fit
###########################################
	.if OOFS_DEBUG
		printc 13, " (resize)"
	.endif
	# resize
	mov	edx, ecx
	add	edx, 511
	and	edx, ~511
	call	class_instance_resize
	jc	92f
	# update
	mov	edi, [eax + oofs_children]
	mov	[edi], eax

#	mov	[eax + oofs_parent], esi
	lea	edi, [eax + oofs_vol_persistent + 512]
	mov	ebx, [eax + oofs_lba]	# 0
	# ecx still ok
	sub	ecx, 512
	jle	93f

	# XXX call oofs_persistent_read
	.if 1
	push_	edx esi
	mov	edx, offset oofs_vol_persistent
	pop_	esi edx
	printc 0xf4, "oofs_vol_onload: multiple sector read not implemented"
	int 3
	.else
	push	eax
	mov	edx, eax #[eax + obj_class]
	mov	eax, [esi + oofs_persistence]
	call	[eax + fs_obj_api_read]
	pop	eax
	.endif
	jc	9f

###########################################
1:	mov	ecx, [eax + oofs_children]

	push	eax
	mov	eax, [eax + oofs_count]
	inc	eax
	call	ptr_array_new
	mov	edx, eax
	pop	eax
	mov	[eax + oofs_children], edx

	jecxz	1f
	push_	eax edi esi	# copy old array over new
	lea	edi, [edx - 4]	# overwrite index
	lea	esi, [ecx - 4]
	mov	eax, ecx	# backup
	mov	ecx, [esi]	# get index from orig array
	shr	ecx, 2
	inc	ecx
	rep	movsd
	call	buf_free	# buf is array base class
	pop_	esi edi eax
1:
	.if OOFS_DEBUG > 1
		OK
###########################################
	call	[eax + oofs_api_print]
###########################################
	.endif

9:	pop_	edx ecx
	STACKTRACE 0
	ret
91:	printlnc 4, "oofs_vol_onload: wrong partition magic"
	stc
	jmp	9b
92:	printlnc 4, "oofs_vol_onload: mrealloc error"
	stc
	jmp	9b
93:	printlnc 4, "oofs_vol_onload: remaining size <=0"
	stc
	jmp	9b



# in: eax = this (oofs instance)
# in: ecx = bytes to reserve
# in: edx = class def ptr
# out: eax = instance
oofs_vol_add:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_vol_add "
		pushd [edx + class_name]; call _s_print;
		printc 9, " size="
		push ecx; call _s_printhex8
		printc 9, " array.count="
		pushd [eax + oofs_count]
		call _s_printhex8
		call	newline
	.endif
	push_	eax edx
	mov	eax, edx
	mov	edx, offset class_oofs
	call	class_extends
	pop_	edx eax
	jc	91f
	# or:
	# push eax
	# mov eax, [eax + obj_class]
	# xchg eax, edx
	# call class_extends
	# mov edx, eax
	# pop eax
	push_	ebx eax edx ebp
	lea	ebp, [esp + 4]
	mov	edx, [eax + oofs_count]
#	or	edx, edx
#	jz	2f
	and	edx, 511
	jz	1f
	add	edx, OOFS_EL_STRUCT_SIZE
	cmp	edx, 512
	jbe	2f

1:	# grow
	mov	edx, [eax + oofs_count]
	inc	edx	# add the free size entry
	OOFS_IDX_TO_EL edx
	lea	edx, [edx + oofs_array - oofs_vol_persistent + 512]
	call	class_instance_resize
	jc	9f

2:	# record entry
	push_	ebx ecx
	add	ecx, 511
	shr	ecx, 9	# convert to sectors

	mov	ebx, [eax + oofs_count]
	inc	ebx	# add the free size entry
	OOFS_IDX_TO_EL ebx
	lea	ebx, [eax + oofs_array + ebx]

	# tail = free space
	# append adjusted tail
	inc	dword ptr [eax + oofs_count]
	mov	edx, [ebx - OOFS_EL_STRUCT_SIZE + oofs_el_sectors] # get free space
	sub	edx, ecx	# edx = remaining free space
	jle	92f

	# update prev last entry: set size.
	mov	[ebx - OOFS_EL_STRUCT_SIZE + oofs_el_sectors], ecx	# reserve

	# append entry representing free space:
	mov	[ebx + oofs_el_sectors], edx # remaining free space
	add	ecx, [ebx - OOFS_EL_STRUCT_SIZE + oofs_el_lba]	# lba field now avail
	mov	[ebx + oofs_el_lba], ecx # new free start

	pop_	ecx ebx
	call	[eax + oofs_persistent_api_save]
	#orb	[eax + oofs_flags], OOFS_FLAG_DIRTY

	# instantiate array element
	mov	edx, eax	# parent ref
	mov	eax, [ebp]	# classdef
	call	class_newinstance
	jc	9f
	push_	ebx ecx
	mov	ebx, [ebp+4]	# this
	mov	ecx, [ebx + oofs_count]
	dec	ecx
#	sub	ecx, 2	# -1:count->idx; -1: one-before-last
	OOFS_IDX_TO_EL ecx
	lea	ebx, [ebx + oofs_array + ecx]
	mov	ecx, [ebx + oofs_el_sectors]
	mov	ebx, [ebx + oofs_el_lba]

	call	[eax + oofs_api_init]
	pop_	ecx ebx
	jc	93f
	mov	ebx, eax

	# record object instance
0:	mov	eax, [ebp+4]	# this
	mov	edx, [eax + oofs_count]
	dec	edx
	shl	edx, 2
	mov	eax, [eax + oofs_children]
	cmp	edx, [eax + array_index]
	jb	2f		# edx = index
	call	ptr_array_newentry	# out: eax + edx : ignore.
	jc	94f
	jmp	0b
2:
	mov	[eax + edx], ebx

	.if OOFS_DEBUG
		OK
		mov 	eax, [ebp + 4] # get orig eax
		call	[eax + oofs_api_print]
	.endif

	mov	[ebp + 4], ebx	# change eax return value

	clc
9:	pop_	ebp edx eax ebx
	STACKTRACE 0
	ret

91:	printc 4, "oofs_add: "
	pushd	[edx + class_name]
	call	_s_print
	printc 4, " not super of "
	mov	edx, [eax + obj_class]
	pushd	[edx + class_name]
	call	_s_println
	stc
	jmp	9b

92:	printc 4, "oofs_add: not enough free sectors"
	add	edx, ecx
	DEBUG_DWORD edx, "avail"
	DEBUG_DWORD ecx, "requested"
	call	newline
	pop_	ecx ebx
	stc
	jmp	9b

93:	printlnc 4, "oofs_add: oofs_api_init fail"
	call	class_deleteinstance
	# TODO: undo reservation
	stc
	jmp	9b

94:	printlnc 4, "oofs_add: out of memory"
	stc
	jmp	9b

# in: eax = this
# in: ebx = entry nr
oofs_vol_delete:
	push_	ebx esi eax
	DEBUG_DWORD ebx,"oofs_delete entry"

	call	[eax + oofs_vol_api_get_obj]
	jc	91f
	# mark object deleted
	mov	eax, [esp]
	mov	esi, [eax + oofs_children]
	mov	dword ptr [esi + ebx * 4], 0	# mark deleted

	# mark region free if last
	cmp	ebx, [eax + oofs_count]
	jnz	0f
	# merge
	decd	[eax + oofs_count]
	mov	esi, [eax + oofs_array + ebx * 8 + oofs_el_sectors]
	add	[eax + oofs_array + ebx * 8 - 8 + oofs_el_sectors], esi

0:	pop_	eax esi ebx
	ret

91:	printc 4, "oofs_delete: no such entry: "
	push	ebx
	call	_s_printhex8
	call	newline
	stc
	jmp	0b

# in: eax = this
# in: edx = instance
oofs_unload:
	push_	ebx eax
	xor	ebx, ebx
0:	mov	eax, [esp]
	call	[eax + oofs_vol_api_get_obj]	# in: eax,ebx; out: eax
	jc	0f	# last entry
	inc	ebx
	cmp	edx, eax
	jnz	0b
	# match
	mov	eax, [esp]
	# mark object deleted
	mov	eax, [eax + oofs_children]
	mov	dword ptr [eax + ebx * 4 - 4], 0	# mark deleted
0:	pop_	eax ebx
	ret


# in: eax = this
# in: edx = classdef ptr
# in: ecx = index
oofs_vol_load_entry:
	# instantiate array element
	push_	edi esi ecx ebx edx eax ebp
	lea	ebp, [esp + 4]

	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_load_entry"
		printc 9, " index="
		push	ecx
		call	_s_printhex8

		printc 9, " array.count="
		pushd	[eax + oofs_count]
		call	_s_printhex8

		printc 9, " LBA="
		pushd	[eax + oofs_array + ecx * 8 + oofs_el_lba]
		call	_s_printhex8
		printc 9, " sectors="
		pushd	[eax + oofs_array + ecx * 8 + oofs_el_sectors]
		call	_s_printhex8

		printc 9, " class="
		pushd	[edx + class_name]
		call	_s_println
	.endif

	cmp	ecx, [eax + oofs_count]
	jae	91f
	xchg	eax, edx	# eax=classdef; edx=this
	call	class_newinstance
	jc	92f

	# edx = this, still
	mov	edi, ecx
	mov	ebx, [edx + oofs_array + ecx * 8 + oofs_el_lba]
	mov	ecx, [edx + oofs_array + ecx * 8 + oofs_el_sectors]
	#DEBUG_DWORD ebx,"lba"
	#DEBUG_DWORD ecx, "size"
	call	[eax + oofs_api_init]
	jc	93f
	mov	ebx, eax
	lea	edx, [edi * 4]
	# record object instance
0:	mov	eax, [ebp]	# this
	mov	edi, eax	# backup for entries_print
	mov	eax, [eax + oofs_children]
	cmp	edx, [eax + array_index]
	jb	1f
	push	edx
	call	ptr_array_newentry	# out: eax + edx
	pop	edx
	jc	94f
	jmp	0b	# check again
1:	mov	[eax + edx], ebx	# update instance array
	mov	[ebp], ebx

	mov	eax, ebx
	call	[eax + oofs_persistent_api_load]
	# child_moved handles instance array update
	jc	95f
	xchg	eax, [ebp]	# eax:=this; [ebp]:=entry instance return value eax
	.if OOFS_DEBUG > 1
	call	[eax + oofs_api_print]
	clc
	.endif

0:	pop_	ebp eax edx ebx ecx esi edi
	STACKTRACE 0
	ret

91:	LOAD_TXT "index>count"
	DEBUG_CLASS
	DEBUG_DWORD ecx;DEBUG_DWORD [eax+oofs_count]
	jmp	9f
92:	LOAD_TXT "newinstance fail"
	jmp	9f

93:	LOAD_TXT "entry init fail"
	jmp	90f
95:	LOAD_TXT "entry load fail"
	DEBUG_METHOD oofs_persistent_api_load
	jmp	90f
94:	mov	eax, ebx
	LOAD_TXT "ptr_array_newentry fail"
90:	call	class_deleteinstance
9:	printc 4, "oofs_load_entry: "
	call	println
	stc
	jmp	0b

# in: eax = this
# in: edx = old child ptr
# in: ebx = new child ptr
oofs_vol_child_moved:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_vol_child_moved"
		printc 9, " old="
		call	printhex8
		printc 9, " new="
		push	ebx
		call	_s_printhex8
		call	newline
	.endif

	push_	edi ecx eax
	mov	edi, [eax + oofs_children]
	or	edi, edi
	jz	91f
	mov	ecx, [eax + array_index]
	shr	ecx, 2
	jz	91f
	mov	eax, edx
	repnz	scasd
	jnz	91f
	mov	[edi - 4], ebx
9:	pop_	eax ecx edi
	STACKTRACE 0
	ret

91:	call	0f
	printc 4, "unknown child: "
	call	printhex8
	call	newline
	int 3
	stc
	jmp	9b

0:	printc 4, "oofs_vol_child_moved: "
	ret

# in: eax = this
# in: ebx = start lba of entry
# out: ebx = entry index
oofs_get_by_lba:
	push	edx
	xor	edx, edx
	jmp	1f
0:	cmp	ebx, [eax + oofs_array + edx * 8 + oofs_el_lba]
	jz	2f
	inc	edx
1:	cmp	edx, [eax + oofs_count]
	jb	0b
	stc
0:	pop	edx
	ret
2:	mov	ebx, edx
	jmp	0b


# iteration method
# in: eax = this
# in: ebx = counter - set to 0 for first in list
# out: CF: counter invalid
# out: eax = object (if CF=0)
oofs_vol_get_obj:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_vol_get_obj"
		printc 9, " idx="
		push	ebx
		call	_s_printhex8
		call	newline
	.endif

	push_	ebx edx

	# check if we have that many persistent entries
	cmp	ebx, [eax + oofs_count]
	ja	9f
	# check if we have that many loaded
	mov	edx, [eax + oofs_children]
	shl	ebx, 2
	cmp	ebx, [edx + array_index]
	jae	9f

	mov	eax, [edx + ebx]
	clc
0:	pop_	edx ebx
	STACKTRACE 0
	ret
9:	stc
	jmp	0b

# find by class
# in: eax = this
# in: edx = class
# in: ebx = counter (0 for start)
# out: CF = 0: edx valid; 1: ebx = -1, edx unmodified
# out: ebx = next counter / -1
# out: eax = object instance matching class edx
oofs_vol_lookup:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_vol_lookup"
		printc 9, " iter="
		push	ebx
		call	_s_printhex8
		printc 9, " class="
		pushd	[edx + class_name]
		call	_s_println
	.endif
	push	ecx
0:	push	eax
	call	[eax + oofs_vol_api_get_obj]	# out: eax
	jc	9f
	inc	ebx
	or	eax, eax
	stc
	jz	1f
	# ebx verified
	mov	ecx, eax	# backup in case match
	call	class_instanceof
1:	pop	eax
	jc	0b
	mov	eax, ecx
	pop	ecx
	clc
	ret
9:	mov	ebx, -1
	pop_	eax ecx
	ret

###########################################################################

# in: eax = this
oofs_vol_print:
	STACKTRACE 0,0
	call	oofs_persistent_print	# super.print()
	push_	edi esi edx ecx ebx

	printc 11, " Entries: "
	mov	edx, [eax + oofs_count]
	call	printdec32
	call	newline

	mov	ecx, edx
	or	ecx, ecx
	jz	9f

	lea	esi, [eax + oofs_array]
	xor	ebx, ebx	# lba sum
	xor	edi, edi	# index
	inc	ecx	# also print the final entry
0:	print " * pLBA "
	mov	edx, [esi + oofs_el_lba]
	call	printhex8
	print " ("
	pushcolor 7
	cmp	edx, ebx
	jz	2f
	color 12
2:	mov	edx, ebx
	call	printhex8
	popcolor
	print "), "
	mov	edx, [esi + oofs_el_sectors]
	call	printhex8
	print " sectors"

	cmp	ecx, 1	# last entry has no objects: free space
	jz	1f


	add	ebx, edx

	mov	edx, [eax + oofs_children]
	or	edx, edx
	jz	1f
	cmp	edi, [edx + array_index]
	jae	1f
	mov	edx, [edx + edi]
	or	edx, edx
	jz	1f
	print " obj: "
	call	printhex8
	call	printspace
	mov	edx, [edx + obj_class]
	call	printhex8
	call	printspace
	push	eax
	mov	eax, edx
	call	class_is_class
	pop	eax
	jc	91f
	pushd	[edx + class_name]
	call	_s_print
1:	call	newline
	add	esi, OOFS_EL_STRUCT_SIZE
	add	edi, 4
	dec ecx;jnz 0b#loop	0b
9:	pop_	ebx ecx edx esi edi
	ret
91:	printc 4, "invalid class"
	jmp 1b
