#############################################################################
.intel_syntax noprefix
#
# persistent lib/mem_handle.s
#

OOFS_ALLOC_DEBUG = 0

.global class_oofs_alloc
.global oofs_alloc_api_alloc	# in: ecx = sectors; out: ebx=handle
.global oofs_alloc_api_free	# in: ebx = handle
.global oofs_alloc_api_txtab_get# in: edx = classdef ptr
.global oofs_alloc_api_txtab_save
.global oofs_alloc_api_handle_get # in: ebx = handle index
.global oofs_alloc_api_handle_load# in: ebx = handle index, edx = instance
.global oofs_alloc_api_handle_save# in: ebx = handle index, edx = instance

.if HANDLE_STRUCT_SIZE == 32
HANDLE_STRUCT_SIZE_SHIFT = 5
.else
.error "HANDLE_STRUCT_SIZE != 32 unimplemented"
.endif

RESERVE_HANDLES = 16

HANDLE_FLAG_DIRTY = 256	# 2nd byte of flags; first byte reserved by handles.s

####################################################
# Idea: the first sector will contain the linked list information.
# One of the linked list elements (handle will be the handles array itself, the same
# as for mem.
# The first sector will contain the LBA of the handles.
# Each handle will represent a contiguous region.
# 
# Three approaches:
# 1) add translation table (FAT: numbers->sectors)
# 2) allow large files to be split over multiple handles. Make a file
#    a linked list of blocks.
# 3) Use staging area/journalling, reserving some space for new files.
#    When the size #    exceeds the space reserved by the handle, allocate a
#    larger space and copy the contents.
#    This can be combined with 2, where open files use a linked list,
#    whereafter they are consolidated.
#
# For now, this class is the same as mem.s except for diskspace.
# Managing file growth will have to be done elsewhere.
# This class then effectively implements a FAT or sector-lookup-table,
# with variable block length.
#
# IMPLEMENTATION
#
# The handles will be allocated similarly to memory handles, and be flat data.
# When a region can grow, by merging it with the succeeding free region,
# data will not have to be copied on disk.
# When the next region is not free, the handles data will have to be copied,
# marking the old handle region on disk as free.
#
# The persistence of the handles array is handled in this class.
# The first sector is reserved to contain the handles structure containing
# the linked list edges and the index to the handles handle.
#
# Each handle will contain an address and a size; the address will be the LBA
# relative to the oofs_alloc region on disk, and be within it.
#
# Upon load, the reserved sector is read, the location of the handles array
# established, and loaded using custom code.  Loading this secondary data
# is not done using the oofs_persistence since the data is flat and will not
# be represented as an object - for now. (Tried that, but it gets too complex).
#
#
# SPECIAL HANDLES
#
# Handles are guaranteed to maintain their index UNLESS they are resized.
#
# To allow for variable-length data to be stored and retrieved, the handle
# referring to this data must be stored in a fixed position: the reserved
# sector.
#
# 1) Handles handle
#
# The first requirement is to store an arbitrary number of handles. This means
# that the handle array itself is variable length.
#
# A handle is reserved for the purpose of keeping track of the handles,
# and it's index stored in the reserved sector. 
#
# 2) Translation / lookup table
#
# The purpose of this second handle is to provide an extensible base to assign
# semantics to the handles.
# Since this class is only concerned with allocation, and not meant to be
# changed any time the filesystem adds a new feature, it offers to keep track
# of a single handle. This single handle itself is variable length and thus
# can serve as a translation or lookup table for other layers/aspects of
# the file system.
#
# It will not by itself load or store the handle contents, but only keep
# track of it's number. Another way to say this is that this class allows
# a user of this class to record a single attribute/dword.
#
# One utility method is provided: get_txtab. This takes edx=classdef ptr,
# a subclass of oofs_persistent,
# and will instantiate the class and call it's constructor passing along
# the LBA and SIZE for the custom handle.
#
#
# HANDLE USAGE
#
# Upon allocating a handle pointing to diskspace, the content of this space
# is undefined. To prevent having to overwrite the sectors upon allocation,
# like mallocz, the handle_caller field, a dword, can represent the size,
# in bytes or sectors, of the initialized data. This will then initially
# be set to 0, whereupon a load method will know how much data to actually
# load, and how much to initialize with zeroes.
# 
####################################################
DECLARE_CLASS_BEGIN oofs_alloc, oofs_persistent

#### Volatile
oofs_alloc_txtab:	.long 0	# txtab instance
oofs_alloc_handles_hash:.long 0 # key = handle index, value = instance ptr

###### begin handles struct fields
oofs_alloc_handles: # the handles struct
oofs_handles_ptr:	.long 0
oofs_alloc_handles_method_alloc:.long 0 # handles_method_alloc: alloc_handles$ static method

#### Persistent
oofs_alloc_persistent:
.long 0	# handles_num
.long 0 # handles_max
.long 0 # handles_idx
oofs_alloc_ll:		# part of handles struct (lib/handles.s)
oofs_alloc_addr_first:	.long 0	# linked-list
oofs_alloc_addr_last:	.long 0	# linked-list
oofs_alloc_size_first:	.long 0	# linked-list
oofs_alloc_size_last:	.long 0	# linked-list
oofs_alloc_hndl_first:	.long 0	# linked-list
oofs_alloc_hndl_last:	.long 0	# linked-list
###### end handles struct

# store the LBA and sectors of the handles handle (i.e. the disk address for the
# linked list itself)
oofs_alloc_handles_lba:		.long 0
oofs_alloc_handles_sectors:	.long 0

# handle lookup table: provide fixed indices to variable handle indices.
oofs_alloc_txtab_idx:		.long 0
# TODO: keep track of this handle:
# - add oofs_alloc_index_resize


DECLARE_CLASS_METHOD oofs_api_init, oofs_alloc_init, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_child_moved, oofs_alloc_child_moved, OVERRIDE
DECLARE_CLASS_METHOD oofs_api_print, oofs_alloc_print, OVERRIDE

DECLARE_CLASS_METHOD oofs_persistent_api_save, oofs_alloc_save, OVERRIDE
DECLARE_CLASS_METHOD oofs_persistent_api_load, oofs_alloc_load, OVERRIDE

DECLARE_CLASS_METHOD oofs_alloc_api_alloc, oofs_alloc_alloc
DECLARE_CLASS_METHOD oofs_alloc_api_free, oofs_alloc_free
DECLARE_CLASS_METHOD oofs_alloc_api_txtab_get, oofs_alloc_txtab_get
DECLARE_CLASS_METHOD oofs_alloc_api_txtab_save, oofs_alloc_txtab_save

DECLARE_CLASS_METHOD oofs_alloc_api_handle_get,  oofs_alloc_handle_get
DECLARE_CLASS_METHOD oofs_alloc_api_handle_load, oofs_alloc_handle_load
DECLARE_CLASS_METHOD oofs_alloc_api_handle_save, oofs_alloc_handle_save

DECLARE_CLASS_END oofs_alloc
#################################################
.text32
# in: eax = instance
# in: edx = parent (instance of class_oofs)
# in: ebx = LBA
# in: ecx = reserved size
oofs_alloc_init:
	.if OOFS_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_alloc_init"
		printc 9, " LBA="; push ebx; call _s_printhex8
		printc 9, " size="; push ecx; call _s_printhex8
		call	newline
	.endif

	call	oofs_persistent_init	# super.init()

	push_	ebx ecx edx esi edi

	# allocate hash
	mov	edx, eax
	mov	eax, 16
	call	ptr_hash_new
	jc	92f
	xchg	eax, edx
	mov	[eax + oofs_alloc_handles_hash], edx

	# clear linked list
	push_	eax 
	lea	edi, [eax + oofs_alloc_ll]
	mov	eax, -1
	mov	ecx, 2 * 3
	rep	stosd
	pop_	eax

	# satisfy handles struct:
	lea	esi, [eax + oofs_alloc_handles]

	mov	[esi + handles_ptr], dword ptr 0
	mov	[esi + handles_num], dword ptr 0
	mov	[esi + handles_max], dword ptr 0
	mov	[esi + handles_method_alloc], dword ptr offset oofs_alloc_handles$

	# initialize

	# add handle for handles.
	call	oofs_alloc_handle_alloc	# out:ebx
	jc	91f

	mov	[esi + handles_idx], ebx	# remember the handles handle index

	mov	edi, [esi + handles_ptr]
	mov	edx, [esi + handles_max]
	shl	edx, HANDLE_STRUCT_SIZE_SHIFT
	add	edx, 511
	shr	edx, 9
	mov	[edi + ebx + handle_size], edx
	mov	[edi + ebx + handle_base], dword ptr 0	# LBA 0 (relative)
	ord	[edi + ebx + handle_flags], MEM_FLAG_HANDLE|HANDLE_FLAG_DIRTY
	# TODO: insert into LL's?
	mov	ecx, [esi + handles_max]	# bounded loop
	lea	edi, [esi + handles_ll_fa]
	mov	esi, [esi + handles_ptr]
	add	esi, offset handle_ll_el_addr
	call	ll_insert_sorted$

	# add handle for free space
	call	oofs_alloc_handle_alloc
	jc	91f

	mov	edi, [eax + oofs_alloc_handles + handles_ptr]
	mov	ecx, [eax + oofs_sectors]
	dec	ecx
	mov	[edi + ebx + handle_size], ecx
	mov	[edi + ebx + handle_base], edx	# size of handles handle
	mov	[edi + ebx + handle_flags], dword ptr 0	# free space
#	# insert into address list, to maintain address space contiguousness
#	lea	edi, [esi + handles_ll_fa]
#	mov	esi, [esi + handles_ptr]
#	add	esi, offset handle_ll_el_addr
#	call	ll_insert_sorted$
	# insert into size list (free)
	lea	esi, [eax + oofs_alloc_handles]
	lea	edi, [esi + handles_ll_fs]
	mov	esi, [esi + handles_ptr]
	add	esi, offset handle_ll_el_size
	call	ll_insert_sorted$

	### Base init done.


	# Allocate a lookup table.

	mov	ecx, 1
	call	[eax + oofs_alloc_api_alloc]
	jc	9f
	mov	[eax + oofs_alloc_txtab_idx], ebx

9:	pop_	edi esi edx ecx ebx
	STACKTRACE 0
	ret

91:	printlnc 4, "oofs_alloc: error getting handle"
	stc
	jmp	9b

92:	printlnc 4, "oofs_alloc: error allocating hash"
	stc
	jmp	9b



# in: eax = this
# in: edx = handle instance
# in: ebx = handle index
oofs_alloc_handle_register:
	.if OOFS_ALLOC_DEBUG
		PRINT_CLASS
		printc 14, ".handle_register"
		printc 9, " handle="; push ebx; call _s_printhex8
		printc 9, " instance="; PRINT_CLASS edx
	.endif

	push_	eax
	mov	eax, [eax + oofs_alloc_handles_hash]
	call	ptr_hash_put
	pop_	eax

	.if OOFS_ALLOC_DEBUG > 1
	jc	9f

		push_	esi edi ecx edx
		mov	esi, [eax + oofs_alloc_handles_hash]
		DEBUG_DWORD esi, "ptr_hash"
		mov	edi, [esi + 4]	# v
		mov	esi, [esi + 0]	# k
		DEBUG_DWORD esi, "keys"
		DEBUG_DWORD [esi + array_index], "#keys"
		DEBUG_DWORD [esi + array_capacity], "/"
		DEBUG_DWORD edi, "values"
		DEBUG_DWORD [edi + array_index], "#values"
		DEBUG_DWORD [edi + array_capacity], "/"
		call	newline
		mov	ecx, [esi + array_index]
		shr	ecx, 2
		jz	1f
	0:	mov	edx, [esi]
		call	printhex8
		call	printspace
		mov	edx, [edi]
		call	printhex8
		call	newline
		add	esi, 4
		add	edi, 4
		loop	0b
	1:	pop_	edx ecx edi esi
	.endif

9:	STACKTRACE 0
	ret

# in: eax = this
# in: ebx = handle index
# out: eax = cached instance
# out: CF
oofs_alloc_handle_get:
	mov	eax, [eax + oofs_alloc_handles_hash]
	push	edx
	call	ptr_hash_get
	mov	eax, edx
	pop	edx
	ret

# method called by handles.s when handles region is too small
# in: esi = handles struct
# in: ebx = minimum handles offset to accommodate (thus, size must be ebx+HANDLE_STRUCT_SIZE)
oofs_alloc_handles$:
	.if OOFS_ALLOC_DEBUG
		PRINT_CLASS
		printc 14, "oofs_alloc_handles$"
	.endif
	push_	eax ebx ecx edx
	mov	eax, [esi + handles_ptr]
	or	eax, eax
	jz	61f

0:	mov	edx, [esi + handles_max]
	add	edx, RESERVE_HANDLES
	cmp	ebx, edx
	jbe	0b	# shouldn't happen

	mov	ecx, edx	# backup

	shl	edx, HANDLE_STRUCT_SIZE_SHIFT
	call	mreallocz
	jc	91f

	mov	[esi + handles_ptr], eax
	mov	[esi + handles_max], ecx

	clc
9:	pop_	edx ecx ebx eax
	STACKTRACE 0
	ret

# exceptional condition: first time init
61:
	.if OOFS_ALLOC_DEBUG
		DEBUG "no handles, instantiating"
	.endif
	# first time alloc
	mov	eax, RESERVE_HANDLES * HANDLE_STRUCT_SIZE
	call	mallocz
	jc	91f
	mov	[esi + handles_ptr], eax
	mov	[esi + handles_max], dword ptr RESERVE_HANDLES
	mov	[esi + handles_num], dword ptr 0
	clc
	jmp	9b


91:	printlnc 4, "oofs_alloc_handles: malloc error"
	stc
	jmp	9b


# in: eax = this
oofs_alloc_save:
	push_	ebx ecx edx esi
# DISABLED:
#
# We don't have the volatile data for each handle.
#
#	# save the handles that need saving
#	mov	edx, [eax + oofs_alloc_handles + handles_ptr]
#	mov	ecx, [eax + oofs_alloc_handles + handles_num]
#0:	testd	[edx + handle_flags], HANDLE_FLAG_DIRTY
#	jz	1f
#
#		mov	ebx, [eax + oofs_lba]
#		add	ebx, [edx + handle_base]
#		mov	ecx, [edx + handle_size]
#		mov	esi, 
#
#
#
#
#1:	add	edx, HANDLE_STRUCT_SIZE
#	loop	0b


#	Save the handles handle

	mov	esi, [eax + oofs_alloc_handles + handles_ptr]
	add	esi, [eax + oofs_alloc_handles + handles_idx]

	mov	ebx, [esi + handle_base]
	mov	[eax + oofs_alloc_handles_lba], ebx	# save in reserved sector
	add	ebx, [eax + oofs_lba]
	mov	ecx, [esi + handle_size]
	inc	ebx	# skip the reserved sector
	mov	[eax + oofs_alloc_handles_sectors], ecx	# save in reserved sector
	shl	ecx, 9	# sectors->bytes

	mov	edx, eax
	mov	eax, [edx + oofs_persistence]
	mov	esi, [edx + oofs_alloc_handles + handles_ptr]
	call	[eax + fs_obj_api_write]
	mov	eax, edx

	# save the reserved sector
	mov	edx, offset oofs_alloc_persistent
	lea	esi, [eax + edx]
	mov	ecx, 1	# 1 byte, will write 1 sector
	call	[eax + oofs_persistent_api_write]

	pop_	esi edx ecx ebx
	STACKTRACE 0
	ret


oofs_alloc_load:
	push_	ebx ecx edx edi
	# load reserved sector
	mov	edx, offset oofs_alloc_persistent
	lea	edi, [eax + edx]
	mov	ecx, 512	# load full sector
	call	[eax + oofs_persistent_api_read]	# might change eax
	jc	9f

	# load handles handle
	mov	ebx, [eax + oofs_alloc_handles_lba]
	inc	ebx	# skip reserved sector
	mov	ecx, [eax + oofs_alloc_handles_sectors]
	add	ebx, [eax + oofs_lba]
	.if OOFS_ALLOC_DEBUG
		DEBUG "loaded reserved sector"
		DEBUG_DWORD ebx, "handles.lba"
		DEBUG_DWORD ecx, "handles.sectors"
	.endif
	shl	ecx, 9
	jz	9f

	mov	edi, eax	# backup
	mov	eax, ecx
	call	mallocz
	xchg	eax, edi
	jc	91f
	mov	[eax + oofs_alloc_handles + handles_ptr], edi

	.if OOFS_ALLOC_DEBUG
		DEBUG_DWORD [eax+oofs_lba]
		DEBUG_DWORD ebx
	.endif

	mov	edx, eax
	mov	eax, [edx + oofs_persistence]
	.if OOFS_ALLOC_DEBUG
		DEBUG_CLASS eax
		DEBUG_CLASS edx
		DEBUG_DWORD ebx,"LBA"
		DEBUG_DWORD ecx, "bytes"
	.endif
	call	[eax + fs_obj_api_read]
	mov	eax, edx	# restore this

9:	STACKTRACE 0
	pop_	edi edx ecx ebx
	ret
91:	printlnc 4, "oofs_alloc_load: mallocz error"
	stc
	jmp	9b



# in: eax= this
# out: ebx = handle index
oofs_alloc_handle_alloc:
	push	esi
	lea	esi, [eax + oofs_alloc_handles]
	call	handle_get
	pop	esi
	STACKTRACE 0
	ret

# in: eax = this
# in: ecx = sectors
# out: ebx = handle index
oofs_alloc_alloc:
	push_	esi eax
	lea	esi, [eax + oofs_alloc_handles]
	mov	eax, ecx
	call	handle_find	# should succeed if free space
	jc	91f

	mov	esi, [esi + handles_ptr]
	mov	[esi + ebx + handle_caller], dword ptr 0 # initialized size

9:	pop_	eax esi
	STACKTRACE 0
	ret
91:	printlnc 4, "oofs_alloc_alloc: region full"
	stc
	jmp	9b


oofs_alloc_free:
	push_	esi eax
	lea	esi, [eax + oofs_alloc_handles]
	mov	eax, ebx
	call	handle_free
	pop_	eax esi
	ret


# in: eax = this
oofs_alloc_txtab_save:
	push_	ebx edx
	mov	edx, [eax + oofs_alloc_txtab]
	mov	ebx, [eax + oofs_alloc_txtab_idx]
	call	oofs_alloc_handle_save
	pop_	edx ebx
	STACKTRACE 0
	ret

# in: eax = this
# in: edx = classdef ptr extends oofs_persistent
# out: eax = loaded instance
oofs_alloc_txtab_get:
	push_	edx ecx ebx
	mov	ecx, eax	# backup

	mov	eax, [eax + oofs_alloc_txtab]
	or	eax, eax
	jnz	9f
	mov	eax, ecx

	mov	ebx, [eax + oofs_alloc_txtab_idx]
	call	oofs_alloc_handle_load	# in: ebx, edx
	jc	91f
	mov	[ecx + oofs_alloc_txtab], eax	# remember child

9:	pop_	edx ecx ebx
	STACKTRACE 0
	ret

91:	printlnc 4, "oofs_alloc_txtab_get: txtab load error"
	stc
	jmp	9b

# since we instantiate with us as parent in txtab_get, we must implement
# the child_moved event. 
#
# in: eax = this
# in: edx = old child ptr
# in: ebx = new child ptr
oofs_alloc_child_moved:
	# only child we know is txtab:
	cmp	edx, [eax + oofs_alloc_txtab]
	jnz	1f
	mov	[eax + oofs_alloc_txtab], ebx

9:	STACKTRACE 0
	ret

1:	push_	eax ebx ecx esi edi
	mov	esi, [eax + oofs_alloc_handles_hash]
	mov	edi, [esi + 4]	# values
	mov	ecx, [edi + array_index]
	shr	ecx, 2
	jz	1f
	mov	eax, edx
	repnz	scasd
	jnz	1f
	mov	[edi - 4], ebx	# update value
	# might loop here in general case, but handle->instance=1:1.
1:	pop_	edi esi ecx ebx eax
	jz	9b

91:	printc 4, "oofs_alloc_child_moved: unknown child: "
	PRINT_CLASS edx
	call	newline
	stc
	jmp	9b


# Utility method, similar to oofs_vol.load_entry.
#
# in: eax = this
# in: ebx = handle index
# in: edx = instance of oofs_handle - constructor will be called
#         OR: edx = class ptr: will be instantiated
# out: eax (?edx?) = object, constructor called.
oofs_alloc_handle_load:
# ALT: handle_apply;
	# TODO: assert
	.if OOFS_ALLOC_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_alloc_handle_load"
		printc 9, " handle_idx="
		push	ebx
		call	_s_printhex8
		STACKTRACE 0,0
	.endif

	push_	ebp esi ebx ecx edx eax

	# assert edx is instance of oofs_handle

	# allow to instantiate the class
	xchg	eax, edx
	call	class_is_class
	jc	1f
	call	class_newinstance
	xchg	eax, edx
	jc	93f

###	# call constructor
	mov	esi, ebx	# backup handle in case ebx becomes lba

	xchg	eax, edx

	push	edx
	mov	edx, offset class_oofs_handle
	call	class_instanceof
	pop	edx
	jz	2f

	# if the object is oofs_persistent, have ebx = lba, ecx=size
	push	edx
	mov	edx, offset class_oofs_persistent
	call	class_instanceof
	pop	edx
	jc	94f
	# set up ebx, ecx
	add	ebx, [edx + oofs_alloc_handles + handles_ptr]
	mov	ecx, [ebx + handle_size]
	mov	ebx, [ebx + handle_base]
	inc	ebx	# skip reserved sector
	add	ebx, [edx + oofs_lba]

2:
	# if the object is an oofs_handle, have ebx = handle
	# in: ebx = handle
	# in: edx = oofs_alloc
	INVOKEVIRTUAL oofs init
	mov	ebx, esi
	jc	91f
###

1:
	# edx=this
	# eax=instance
	# change the onload handler:
	pushd	[eax + oofs_persistent_api_onload]
	mov	[eax + oofs_persistent_api_onload], dword ptr offset oofs_alloc_onload_proxy$
	mov	ebp, esp	# onload_proxy$ in: ebp = orig onload handler
	# NOTE: the load method must not modify ebp!
	call	[eax + oofs_persistent_api_load]
	popd	[eax + oofs_persistent_api_onload]	# restore
	mov	[esp], eax	# set return value
	jc	92f

9:	pop_	eax edx ecx ebx esi ebp
	STACKTRACE 0
	ret

91:	printlnc 12, "oofs_alloc_handle_load: error calling persistent.init"
	stc
	jmp	9b

92:	printlnc 12, "oofs_alloc_handle_load: error calling persistent.load"
	stc
	jmp	9b

93:	printlnc 12, "oofs_alloc_handle_load: instantiation error"
	stc
	jmp	9b

94:	printlnc 12, "oofs_alloc_handle_load: object not oofs_persistent"
	stc
	jmp	9b

95:	printlnc 12, "oofs_alloc_handle_load: object not oofs_handle"
	stc
	jmp	9b

# [ebp +  0] = original onload
# [ebp +  4] = eax = oofs_alloc instance
# [ebp + 16] = ebx = handle index
# edi = data pointer
# eax = oofs_persistent subclass instance
# ecx = bytes loaded
oofs_alloc_onload_proxy$:
	# zero out uninitialized data
	.if OOFS_ALLOC_DEBUG
		DEBUG_CLASS
		printc 14, ".onload_proxy$"
		DEBUG_DWORD eax
		DEBUG_DWORD edi,"dataptr"
		DEBUG_DWORD ecx
		call	newline
	.endif

	push_	edi esi ecx ebx eax
	mov	esi, [ebp + 4]
	mov	ebx, [ebp + 16]
	add	ebx, [esi + oofs_alloc_handles + handles_ptr]

	mov	ebx, [ebx + handle_caller]
	shl	ebx, 9

	add	ecx, 511
	and	ecx, ~511	# edi + ecx = assured allocated size
	sub	ecx, ebx
	jbe	1f	# make sure to not write after allocated size

	.if OOFS_ALLOC_DEBUG
		DEBUG_DWORD ebx, "keep"
		DEBUG_DWORD ecx, "clear"
	.endif

	add	edi, ebx

	xor	eax, eax
	mov	bl, cl
	shr	ecx, 2
	rep	stosd
	mov	cl, bl
	and	cl, 3
	rep	stosb
1:	pop_	eax ebx ecx esi edi

	call	[ebp]	# call original onload method
	ret


# in: eax = this
# in: ebx = handle index
# in: edx = instance (oofs_persistent subclass)
oofs_alloc_handle_save:
	.if OOFS_ALLOC_DEBUG
		DEBUG_CLASS
		printc 14, ".oofs_alloc_handle_save"
		printc 9, " instance: "
		DEBUG_CLASS edx
	.endif

	# verify if the size will fit
	push	ecx
	mov	ecx, [edx + oofs_handle_handle]
	pop	ecx


	xchg	eax, edx
	call	[eax + oofs_persistent_api_save]
	xchg	eax, edx
	jc	9f

	# update handle
	push	esi
	mov	esi, [eax + oofs_alloc_handles + handles_ptr]
	mov	[esi + ebx + handle_caller], dword ptr 1 # XXX FIXME TODO
	pop	esi
9:	STACKTRACE 0
	ret


oofs_alloc_print:
	STACKTRACE 0,0
	call	oofs_persistent_print

	printc 11, "handles: "
	pushd	[eax + oofs_alloc_handles + handles_num]
	call	_s_printhex8
	printcharc 11, '/'
	pushd	[eax + oofs_alloc_handles + handles_max]
	call	_s_printhex8
	printc 11, " rLBA "
	pushd	[eax + oofs_alloc_handles_lba]
	call	_s_printhex8
	printc 11, " rSectors "
	pushd	[eax + oofs_alloc_handles_sectors]
	call	_s_printhex8
	call	newline

	printc 11, "Handles handle: idx "
	pushd	[eax + oofs_alloc_handles + handles_idx]
	call	_s_printhex8

	printc 11, " rLBA "
	push	esi
	mov	esi, [eax + oofs_alloc_handles + handles_ptr]
	add	esi, [eax + oofs_alloc_handles + handles_idx]
	pushd	[esi + handle_base]
	call	_s_printhex8
	printc 11, " sectors "
	pushd	[esi + handle_size]
	call	_s_printhex8
	call	newline

	printc 11, "txtab handle number: "
	push	edx
	mov	edx, [eax + oofs_alloc_txtab_idx]
	shr	edx, HANDLE_STRUCT_SIZE_SHIFT
	call	printdec32
	pop	edx
	call	newline

	#

	lea	esi, [eax + oofs_alloc_handles]
	call	handles_print

	#

	call	newline
	printc 11, "txtab: "
	push	eax
	mov	eax, [eax + oofs_alloc_txtab]
	or	eax, eax
	jz	1f
	call	[eax + oofs_api_print]

1:	call	newline
	pop	eax
	pop	esi
	ret

