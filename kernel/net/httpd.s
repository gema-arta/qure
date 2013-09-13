#######################################################################
# HTTP Server
#
.intel_syntax noprefix
.text32

NET_HTTP_DEBUG = 1		# 1: log requests; 2: more verbose


cmd_httpd:
	I "Starting HTTP Daemon"
	PUSH_TXT "httpd"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset net_service_httpd_main
	KAPI_CALL schedule_task
	jc	9f
	OK
9:	ret

net_service_httpd_main:
	xor	eax, eax
	mov	edx, IP_PROTOCOL_TCP<<16 | 80
	mov	ebx, SOCK_LISTEN
	KAPI_CALL socket_open
	jc	9f
	printc 11, "HTTP listening on "
	KAPI_CALL socket_print
	call	newline

0:	mov	ecx, 10000
	KAPI_CALL socket_accept
	jc	0b

	push	eax
	mov	eax, edx
	.if NET_HTTP_DEBUG
		printc 11, "HTTP "
		KAPI_CALL socket_print
		call	printspace
	.endif

	.if 0
	call	httpd_sched_client # some es problem
	.else
	call	httpd_handle_client
	.endif
	pop	eax
	jmp	0b

	ret
9:	printlnc 4, "httpd: failed to open socket"
	ret

httpd_sched_client:
	call	SEL_kernelCall:0
	PUSH_TXT "httpc-"
	push	dword ptr TASK_FLAG_TASK | TASK_FLAG_RING_SERVICE
	push	cs
	push	dword ptr offset httpd_handle_client
	KAPI_CALL schedule_task
	ret

# in: eax = socket
# postcondition: socket closed.
httpd_handle_client:
	mov	edx, 6	# minimum request size: "GET /\n"
0:	mov	ecx, 10000
	KAPI_CALL socket_peek
	jc	9f

	lea	edx, [ecx + 1]	# new minimum request size

	push	eax
	push	edx
	call	http_check_request_complete
	pop	edx
	pop	eax
	jc	4f	# invalid request
	jnz	0b	# incomplete

	call	net_service_tcp_http	# takes care of socket_close
	ret

9:	printlnc 4, "httpd: timeout, closing connection"
	LOAD_TXT "HTTP/1.1 408 Request timeout\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write
1:	KAPI_CALL socket_flush
	KAPI_CALL socket_close
0:	ret

4:	LOAD_TXT "HTTP/1.1 400 Bad request\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write
	jmp	1b

# out: CF = 1: invalid request (request might be incomplete but complete enough
#  to determine the error, i.e., first line received)
# out: [CF=0] ZF = 1: have a complete request; 0: request incomplete
# out: edi: end of request
http_check_request_complete:
	push	ecx
	mov	edi, esi
0:	mov	al, '\n'
	repnz	scasb
	jnz	91f	# incomplete
########
	# Check for simple request (GET uri \n):
	mov	ecx, [esp]
	mov	edi, esi
	mov	al, ' '
	repnz	scasb	# scan method uri separator
	jnz	99f	# no space: invalid request (request complete)
	repnz	scasb	# check for second space
	jnz	90f	# no second space, thus simple (one-line) request
	# have second space, check for HTTP
	cmp	ecx, 8	# check if sizeof("HTTP/x.x") is at least present
	jb	99f	# invalid (complete) request

	cmp	dword ptr [edi], 'H'|'T'<<8|'T'<<16|'P'<<24
	jnz	99f	# invalid (complete) request
	cmp	byte ptr [edi + 4], '/'
	jnz	99f	# invalid (complete) request
	# check version
	add	edi, 5
	sub	ecx, 5

	call	10f	# expect at least 1 digit:
	jc	99f
	inc	edi
	dec	ecx	# 6
	# check for '.' or digit
4:	cmp	[edi], byte ptr '.'
	jz	3f
	call	10f
	jc	99f
	inc	edi
	loop	4b
	jmp	99f

3:	inc	edi	# got '.'
	dec	ecx
	jz	99f
	call	10f	# check minor version
	jc	99f
	dec	ecx
	jz	99f	# invalid
	# so far we've matched "HTTP/\d+\.\d"
	# now, expect \r|\n|\d
3:	inc	edi
	cmp	[edi], byte ptr '\r'
	jz	1f
	cmp	[edi], byte ptr '\n'
	jz	2f
	call	10f
	jc	99f
	loop	3b
	jmp	99f	# invalid

	# full request line complete
	# check for \n\n (or \r\n\r\n)

2:	# char trailing HTTP version is '\n', so check if next char is also \n.
	cmp	ecx, 2
	jb	91f	# incomplete: no room
	cmp	byte ptr [edi+1], '\n'
	jz	90f	# complete
	add	edi, 2
	sub	ecx, 2
	jle	91f	# incomplete
	# check for a double \n:
	mov	al, '\n'
2:	repnz	scasb
	jnz	91f	# incomplete
	scasb
	jz	90f
	dec	ecx
	jnle	2b
	jmp	91f	# incomplete


1:	# char trailing HTTP version is \r, check for (\r)\n\r\n:
	cmp	ecx, 4
	jb	91f	# incomplete: no room for two CRLF's
	mov	eax, '\r'|'\n'<<8|'\r'<<16|'\n'<<24
	cmp	[edi], eax
	jz	90f	# complete!
	inc	edi
	dec	ecx
	jle	91f

1:	repnz	scasb
	jnz	91f
	cmp	[edi -1], eax
	jz	90f
	jecxz	91f
	jmp	1b

	# incomplete
########
91:	or	edi, edi	# ZF = 0, CF = 0: incomplete
	pop	ecx
	ret

99:	stc			# ZF = ?, CF = 1: invalid request
	pop	ecx
	ret

90:	xor	cl, cl		# ZF = 1, CF = 0: complete
	pop	ecx
	ret

# check for digit
10:	mov	al, [edi]
	cmp	al, '0'
	jb	9f
	cmp	al, '9'
	ja	9f
	clc
	ret
9:	stc
	ret



# in: eax = socket index
# in: esi = request data (complete)
# in: ecx = request data len
net_service_tcp_http:
	call	http_parse_header	# in: esi,ecx; out: edx=uri, ebx=host

	mov	esi, offset www_code_400$
	jc	www_err_response

	# Send a response
	cmp	edx, -1	# no GET / found in headers
	jz	www_err_response

	.if NET_HTTP_DEBUG
		pushcolor 13
		cmp	ebx, -1
		jz	1f
		mov	esi, ebx
		call	print
		call	printspace

	1:	color	14
		mov	esi, edx
		call	print
		call	printspace
		popcolor
	.endif

	cmp	word ptr [edx], '/' | 'C'<<8
	jnz	1f
		call	www_send_screen
		ret
###################################################

1:
	# serve custom file:
	.data SECTION_DATA_STRINGS
	www_docroot$: .asciz "/c/www/"
	WWW_DOCROOT_STR_LEN = . - www_docroot$
	.data SECTION_DATA_BSS
	www_content$: .long 0
	www_file$: .space MAX_PATH_LEN
	.text32
	push	eax
	movzx	eax, byte ptr [boot_drive]
	add	al, 'a'
	mov	[www_docroot$ + 1], al
	pop	eax

	xor	ecx, ecx
	cmp	ebx, -1
	jz	1f	# no host
	mov	esi, ebx
	call	strlen_
	inc	ecx
1:
	mov	esi, edx
	push	ecx
	call	strlen_
	add	ecx, [esp]
	add	esp, 4
	cmp	ecx, MAX_PATH_LEN - WWW_DOCROOT_STR_LEN -1
	mov	esi, offset www_code_414$
	jae	www_err_response

	# calculate path
0:	mov	edi, offset www_file$
	mov	esi, offset www_docroot$
	mov	ecx, WWW_DOCROOT_STR_LEN
	rep	movsb

	# append hostname, if any
	cmp	ebx, -1
	jz	1f
	mov	edi, offset www_file$
	mov	esi, ebx
	call	fs_update_path
	mov	word ptr [edi - 1], '/'
	push	eax
	mov	eax, offset www_file$
	KAPI_CALL fs_stat
	pop	eax
	jnc	1f
	# unknown host
	mov	ebx, -1
	jmp	0b
1:

FS_DIRENT_ATTR_DIR=0x10

	mov	edi, offset www_file$
	mov	esi, edx
	inc	esi	# skip leading /
	call	fs_update_path	# edi=base/output, esi=rel

	# check whether path is still in docroot:
	mov	esi, offset www_docroot$
	mov	edi, offset www_file$
	mov	ecx, WWW_DOCROOT_STR_LEN - 1 # skip null terminator
	repz	cmpsb
	mov	esi, offset www_code_404$
	jnz	www_err_response

	# now, if it is a directory, append index.html
	push	eax
	mov	eax, offset www_file$
	KAPI_CALL fs_stat
	jc	2f	# takes care of pop eax
	test	al, offset FS_DIRENT_ATTR_DIR
	pop	eax
	jz	1f

	mov	edi, offset www_file$
	LOAD_TXT "./index.html"
	call	fs_update_path
	# no need to check escape from docroot.
1:

	.if NET_HTTP_DEBUG
		printc 13, "Serving file: '"
		mov	esi, offset www_file$
		call	print
		printc 13, "' "
	.endif

	push	eax	# preserve socket
	push	edx
	mov	eax, offset www_file$
	xor	edx, edx	# fs_open flags argument
	KAPI_CALL fs_open
	pop	edx
	jc	2f

	push	eax
	mov	eax, ecx
	add	eax, 2047
	and	eax, ~2047
	call	mallocz
	mov	edi, eax
	mov	esi, eax
	pop	eax
	jnc 1f; printc 4, "mallocz error"; 1:
#TODO:	jc	

	KAPI_CALL fs_read	# in: edi,ecx,eax
	jnc 1f; printc 4, "fs_read error"; 1:
#TODO:	jc
	
	pushf
	KAPI_CALL fs_close
	popf
	pop	eax
	jnc	1f

	push	eax
	mov	eax, edi
	call	mfree
2:	pop	eax
	mov	esi, offset www_code_404$
	jmp	www_err_response

########
1:	# esi, ecx = file contents
	mov	esi, edi
	.if NET_HTTP_DEBUG
		printlnc 10, "200 "
	.endif
	push	ebp
	mov	ebp, esp
	push	eax	# [ebp - 4]  tcp conn
	push	esi	# [ebp - 8]  orig buf
	push	ecx	# [ebp - 12] orig buflen

	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: "
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_file$
	call	http_get_mime	# out: esi
	call	strlen_
	KAPI_CALL socket_write

	LOAD_TXT "\r\nConnection: close\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write

	mov	ebx, [ebp - 8]	# buf

1:	mov	edi, ebx
	mov	ecx, [ebp - 12]	# buflen
	call	www_findexpr	# in: edi, ecx; out: edi,ecx
	jc	1f
# preserve edi,ecx
	# edi, ecx = expression
	lea	edx, [edi - 2]	# start of expression string
	sub	edx, ebx	# len of unsent data
	jz	2f
	mov	esi, ebx	# start of unsent data
	lea	ebx, [edi + ecx + 1]	# end of expr = new start of unsent data
	sub	[ebp - 12], edx	# update remaining source len

	push	ecx
	mov	ecx, edx
	KAPI_CALL socket_write
	pop	ecx
2:
# use edi,ecx
	lea	edx, [ecx + 3]
	sub	[ebp - 12], edx	# update remaining source len

	call	www_expr_handle

	jmp	1b
##################################

1:	mov	ecx, [ebp - 12]
	mov	esi, ebx
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close

	mov	eax, [ebp - 8]
	call	mfree
########
9:	mov	esp, ebp
	pop	ebp
	ret

.data SECTION_DATA_STRINGS
_mime_text_html$:	.asciz "text/html"
_mime_text_css$:	.asciz "text/css"
_mime_text_javascript$:	.asciz "text/javascript"
_mime_image_jpeg$:	.asciz "image/jpeg"
_mime_image_png$:	.asciz "image/png"
_mime_image_gif$:	.asciz "image/gif"
_mime_application_unknown$: .asciz "application/unknown"

.data
mime_table:
	STRINGPTR "html";	.long _mime_text_html$
	STRINGPTR "css";	.long _mime_text_css$
	STRINGPTR "js";		.long _mime_text_javascript$
	STRINGPTR "png";	.long _mime_image_png$
	STRINGPTR "jpg";	.long _mime_image_jpeg$
	STRINGPTR "jpeg";	.long _mime_image_jpeg$
	STRINGPTR "gif";	.long _mime_image_gif$
	.long 0;		.long _mime_application_unknown$
.text32

# in: esi
# out: esi
http_get_mime:
	push_	edi eax ecx edx
	call	strlen_
	mov	edx, ecx

	lea	edi, [esi + ecx]
	mov	al, '.'
	std
	repnz	scasb
	cld
	jnz	9f

	add	edi, 2
	add	ecx, 2

	mov	esi, edi
	sub	edx, ecx	# edx = len of filename extension

	mov	eax, offset mime_table
0:	mov	esi, [eax]
	or	esi, esi
	jz	9f
	push	edi
	mov	ecx, edx
	repz	cmpsb
	pop	edi
	jz	1f
	add	eax, 8
	jmp	0b
1:	mov	esi, [eax + 4]

0:	pop_	edx ecx eax edi
	ret
9:	mov	esi, offset _mime_application_unknown$
	jmp	0b

# in: esi = header
# in: ecx = header len
# out: ebx = host ptr (in header), if any
# out: edx = -1 or resource name (GET /x -> /x)
http_parse_header:
	push	eax
	push	edi
	mov	edx, -1		# the file to serve
	mov	ebx, -1		# the hostname
	mov	edi, esi	# mark beginning
0:	lodsb
	cmp	al, '\r'
	jz	1f
	cmp	al, '\n'
	jnz	2f
	.if NET_HTTP_DEBUG > 1
		call	newline
	.endif
	call	http_parse_header_line$	# update edx if GET /..., ebx if Host:..
	mov	edi, esi	# mark new line beginning
	jc	9f
	jmp	1f

2:;	.if NET_HTTP_DEBUG > 1
		call	printchar
	.endif

1:	loop	0b
	.if NET_HTTP_DEBUG > 1
		call	newline
		clc
	.endif

9:	pop	edi
	pop	eax
	ret


# Parses the header, and zero-terminates the lines if there is a match
# for a GET / or Host: header.
# in: edi = start of header line
# in: esi = end of header line
# in: edx = known value (-1) to compare against
# out: edx = resource identifier (if request match): 0 for root, etc.
http_parse_header_line$:
	push_	edi esi ecx
	mov	ecx, esi
	sub	ecx, edi
	mov	esi, edi

	.if NET_HTTP_DEBUG > 1#2
		pushcolor 15
		push esi
		push ecx
		printchar '<'
		call nprint
		printchar '>'
		pop ecx
		pop esi
		popcolor
	.endif

	LOAD_TXT "GET /", edi
	push	ecx
	push	esi
	mov	ecx, 5
	repz	cmpsb
	pop	esi
	pop	ecx
		mov	edi, esi	# for debug print
	jz	1f

	LOAD_TXT "Host: ", edi
	push	ecx
	push	esi
	mov	ecx, 5
	repz	cmpsb
	pop	esi
	pop	ecx
	jz	2f

	LOAD_TXT "Referer: ", edi
	push_	ecx esi
	mov	ecx, 9
	repz	cmpsb
	pop_	esi ecx
	clc
	jnz	9f

	# found referer header:
	add	esi, 9
	sub	ecx, 9
	.if 1
		push_	ecx eax esi
		mov	edi, esi
		mov	al, '\n'
		repnz	scasb
		jnz	3f
		printc 14, "Referer: "
		mov	ecx, edi
		sub	ecx, esi
		call	nprint
		jmp	4f
	3:	printc 4, "referer: no eol"
	4:	pop_	esi eax ecx
	.endif
	jmp	0f


2:	# found Host header line
	cmp	ebx, -1
	jz	2f
	printc 4, "Duplicate 'Host:' header: "
	call	nprintln
	stc
	jmp	9f
2:	add	esi, 6		# skip "Host: "
	sub	ecx, 6
	mov	ebx, esi	# start of hostname

	.if NET_HTTP_DEBUG > 1
		mov	edi, esi
		printc 9, "Host: <"
	.endif

	jmp	0f

1:	# found GET header line
	add	esi, 4		# preserve the leading /
	sub	ecx, 4
	jle	9f
	mov	edx, esi	# start of resource
	.if NET_HTTP_DEBUG > 1
		printc 9, "GET: <"
		mov	edi, esi
	.endif

0:	lodsb
	cmp	al, ' '
	jz	0f
	cmp	al, '\n'
	jz	0f
	cmp	al, '\r'
	jz	0f
	loop	0b
	# hmmm

	.if NET_HTTP_DEBUG > 1
		printc 9, "Resource: <"
	.endif


0:	mov	[esi - 1], byte ptr 0

	.if NET_HTTP_DEBUG > 1
		# mov ecx, esi; sub ecx, ebx; mov esi, ebx; call nprint
		mov	esi, edi
		call	print
		printlnc 9, ">"
	.endif
	clc

9:	pop_	ecx esi edi
	ret



# in: edi = data to scan
# in: ecx = data len
# out: edi, ecx: expression string
www_findexpr:
	push	esi
	push	eax

	mov	al, '$'
	repnz	scasb
	jnz	1f	# no expressions
	cmp	[edi], byte ptr '{'
	jnz	1f
	inc	edi

	# parse expression
	mov	esi, edi	# start of expr
0:	dec	ecx
	jle	1f
	lodsb
	cmp	al, ' '
	jz	1f
	cmp	al, '\n'
	jz	1f
	cmp	al, '}'
	jnz	0b

	mov	ecx, esi
	dec	ecx	# dont count closing '}'
	sub	ecx, edi
	clc

9:	pop	eax
	pop	esi
	ret
1:	stc
	jmp	9b


expr_h_unknown:
	ret
expr_h_const:
	mov	eax, edx
	xor	edx, edx
	ret
expr_h_mem:
	mov	eax, [edx]
	xor	edx, edx
	ret
expr_h_call:
	call	edx
	ret

kernel_get_uptime:
	push	edi
	call	get_time_ms_40_24
	call	sprint_time_ms_40_24
	mov	ecx, edi
	pop	edi
	sub	ecx, edi
	ret
.data
www_expr:

# first byte: handler type:
# 1 = const
# 2 = mem
# 3 = call
# Second byte: data type:
# 1 = size   (out: edx:eax)
# 2 = string (in: esi,ecx)
# 3 = decimal32 (out: edx)

.long (99f - .)/10
STRINGPTR "kernel.revision";	.byte 1,3;.long KERNEL_REVISION
STRINGPTR "kernel.uptime";	.byte 3,2;.long kernel_get_uptime
.if 1
STRINGPTR "kernel.size";	.byte 3,1;.long expr_krnl_get_size
STRINGPTR "kernel.code.size";	.byte 3,1;.long expr_krnl_get_code_size
STRINGPTR "kernel.data.size";	.byte 3,1;.long expr_krnl_get_data_size
STRINGPTR "mem.heap.size";	.byte 2,1;.long mem_heap_size
.else
STRINGPTR "kernel.size";	.byte 1,1;#.long kernel_end - kernel_start
	.long kernel_code_end - kernel_code_start + kernel_end - data_0_start
STRINGPTR "kernel.code.size";	.byte 1,1;.long kernel_code_end - kernel_code_start
STRINGPTR "kernel.data.size";	.byte 1,1;.long kernel_end - data_0_start
STRINGPTR "mem.heap.size";	.byte 2,1;.long mem_heap_size
.endif
STRINGPTR "mem.heap.allocated";	.byte 3,1;.long mem_get_used
STRINGPTR "mem.heap.reserved";	.byte 3,1;.long mem_get_reserved
STRINGPTR "mem.heap.free";	.byte 3,1;.long mem_get_free
STRINGPTR "cluster.kernel.revision";	.byte 3,2;.long cluster_get_kernel_revision
STRINGPTR "cluster.status";	.byte 3,2;.long cluster_get_status
STRINGPTR "cluster.status.list";.byte 3,2;.long cluster_get_status_list
99:
www_expr_handlers:
	.long expr_h_unknown
	.long expr_h_const
	.long expr_h_mem
	.long expr_h_call
NUM_EXPR_HANDLERS = (.-www_expr_handlers)/4
.text32
expr_krnl_get_size:
	xor	edx, edx
	mov	eax, offset KERNEL_SIZE
#	mov	eax, offset kernel_code_end
#	sub	eax, offset kernel_code_start
#	add	eax, offset kernel_end
#	sub	eax, offset data_0_start
	ret
expr_krnl_get_code_size:
	xor	edx, edx
	mov	eax, offset KERNEL_CODE32_SIZE
	add	eax, offset KERNEL_CODE16_SIZE
	ret
expr_krnl_get_data_size:
	xor	edx, edx
	mov	eax, offset KERNEL_DATA_SIZE
	ret



# in: eax = tcp conn
# in: edi = expressoin
# in: ecx = expression len
# free to use: edx, esi
www_expr_handle:
	push	ebx
	push	ecx
	push	edi
	push	eax

	mov	byte ptr [edi + ecx], 0	# '}' -> 0
	inc	ecx	# include 0 terminator for rep cmpsb

	.if 0
		mov	esi, edi
		call	nprint
	.endif

	# find expression info
	mov	edx, [www_expr]
	mov	ebx, offset www_expr + 4
0:	mov	esi, [ebx]
	push	ecx
	push	edi
	repz	cmpsb
	pop	edi
	pop	ecx
	jz	1f	# found

	add	ebx, 10	# struct size
	dec	edx
	jg	0b
		DEBUG "no matches"
	# not found
	jmp	9f

1:	
	movzx	edx, byte ptr [ebx + 4]	# type
	cmp	edx, NUM_EXPR_HANDLERS
	jae	9f
	mov	al, byte ptr [ebx + 5]	# data type
	cmp	al, 1
	jz	1f	# size
	cmp	al, 2	# buffer arg
	jnz	1f

1:	push	eax
	mov	edi, offset _tmp_expr_buf$ # for stringput types
	mov	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)/4
	xor	eax, eax
	rep	stosd
	mov	edi, offset _tmp_expr_buf$ # for stringput types
	mov	ecx, offset _tmp_expr_buf_end$-_tmp_expr_buf$

	mov	eax, edx
	mov	edx, [ebx + 6]		# arg2

	call	www_expr_handlers[eax * 4]
	pop	ebx
	cmp	bl, 2	# string
	jnz	1f
	mov	edi, offset _tmp_fmt$
	mov	esi, offset _tmp_expr_buf$
	cmp	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)
	jb	2f
	mov	ecx, (offset _tmp_expr_buf_end$-_tmp_expr_buf$)-1
	jmp	2f


1:	cmp	bl, 3	# decimal32
	jnz	1f
	mov	edx, eax
	call	sprintdec32
	jmp	3f

1:	cmp	bl, 4	# hex8
	jnz	1f
	mov	edx, eax
	call	sprinthex8
	jmp	3f


1:	# default: 1 = size
	# data type: size: edx:eax
	# todo: format
	.data SECTION_DATA_BSS
	_tmp_fmt$: .space 32
	_tmp_expr_buf$: .space 1024
	_tmp_expr_buf_end$:
	.text32
	call	sprint_size
3:	mov	ecx, edi
	mov	esi, offset _tmp_fmt$
	sub	ecx, esi

2:
	.if 0
		DEBUG "EXPR VAL:"
		call nprint
		call newline
	.endif

	mov	eax, [esp]
	KAPI_CALL socket_write

9:	pop	eax
	pop	edi
	pop	ecx
	pop	ebx
	ret

.data SECTION_DATA_STRINGS
www_h$:		.asciz "HTTP/1.1 "
www_h2$:	.ascii "\r\nContent-Type: text/html; charset=UTF-8\r\n"
		.asciz "Connection: Close\r\n\r\n"
www_code_400$:	.asciz "400 Bad Request"
www_code_404$:	.asciz "404 Not Found"
www_code_414$:	.asciz "414 Request URI too long"
www_code_500$:	.asciz "500 Internal Server Error"
www_content1$:	.asciz "<html><body>"
www_content2$:	.asciz "</body></html>\r\n"
.text32
www_err_response:
	.if NET_HTTP_DEBUG
		mov	ecx, 4
		pushcolor 12
		call	nprintln
		popcolor
	.endif

	mov	edx, esi

	mov	esi, offset www_h$
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, edx
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_h2$
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_content1$
	call	strlen_
	KAPI_CALL socket_write

	lea	esi, [edx + 4]
	call	strlen_
	KAPI_CALL socket_write

	mov	esi, offset www_content2$
	call	strlen_
	KAPI_CALL socket_write

	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret


# in: eax = tcp conn
www_send_screen:
	LOAD_TXT "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"
	call	strlen_
	KAPI_CALL socket_write

.data SECTION_DATA_STRINGS
_color_css$:
.ascii "<html><head><style type='text/css'>"
.ascii "pre {background-color: black}\n"
.ascii ".a{color:black}\n.ba{background-color:black}\n"
.ascii ".b{color:darkblue}\n.bb{background-color:darkblue}\n"
.ascii ".c{color:green}\n.bc{background-color:green}\n"
.ascii ".d{color:darkcyan}\n.bd{background-color:cyan}\n"
.ascii ".e{color:darkred}\n.be{background-color:darkred}\n"
.ascii ".f{color:darkmagenta}\n.bf{background-color:darkmagenta}\n"
.ascii ".g{color:brown}\n.bg{background-color:brown}\n"
.ascii ".h{color:lightgray}\n.bh{background-color:lightgray}\n"
.ascii ".i{color:darkgray}\n.bi{background-color:darkgray}\n"
.ascii ".j{color:#0000ff}\n.bj{background-color:blue}\n"
.ascii ".k{color:lime}\n.bk{background-color:lime}\n"
.ascii ".l{color:cyan}\n.bl{background-color:cyan}\n"
.ascii ".m{color:red}\n.bm{background-color:red}\n"
.ascii ".n{color:magenta}\n.bn{background-color:magenta}\n"
.ascii ".o{color:yellow}\n.bo{background-color:yellow}\n"
.ascii ".p{color:white}\n.bp{background-color:white}\n"
.asciz "</style></head><body><pre>\n"
.text32

	mov	esi, offset _color_css$
	call	strlen_
	KAPI_CALL socket_write

SEND_BUFFER = 1
	push	fs
.if SEND_BUFFER
	mov	ebx, ds
	mov	fs, ebx
	push	eax
	call	console_get
	mov	ebx, [eax + console_screen_buf]
	pop	eax
	mov	ecx, 25 * SCREEN_BUF_PAGES
.else
	mov	ebx, SEL_vid_txt
	mov	fs, ebx
	xor	ebx, ebx
	mov	ecx, 25
.endif
0:	push	ecx
#######
	mov	ecx, 80
	.data SECTION_DATA_BSS
	_www_scr$: .space 80 * 32 # 13
	.text32
	mov	edi, offset _www_scr$
	push	eax
	xor	dl, dl	# cur color
1:	mov	ax, fs:[ebx]
	cmp	dl, ah
	jz	2f
	or	dl, dl
	jz	3f
	mov	[edi], dword ptr ('<'|'/'<<8|'s'<<16|'p'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'n'<<8|'>'<<16)
	add	edi, 3

3:
	mov	[edi], dword ptr ('<'|'s'<<8|'p'<<16|'a'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('n'|' '<<8|'c'<<16|'l'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'s'<<8|'s'<<16|'='<<24)
	add	edi, 4
	mov	[edi], byte ptr '\''
	inc	edi

	mov	dl, ah

	and	ah, 0x0f
	add	ah, 'a'
	mov	[edi], ah
	inc	edi

	mov	[edi], word ptr ' '|'b'<<8
	add	edi, 2
	mov	ah, dl
	shr	ah, 4
	add	ah, 'a'
	mov	[edi], ah
	inc	edi

	mov	[edi], word ptr '\'' | '>' << 8
	add	edi, 2

2:	stosb
	add	ebx, 2
	loop	1b
	# close the span; TODO FIXME: check whether one is open!
	# (however better than now where EOL's are not closed!)
	mov	[edi], dword ptr ('<'|'/'<<8|'s'<<16|'p'<<24)
	add	edi, 4
	mov	[edi], dword ptr ('a'|'n'<<8|'>'<<16)
	add	edi, 3

	mov	[edi], byte ptr '\n'
	inc	edi
	pop	eax
#######
	mov	esi, offset _www_scr$
	mov	ecx, edi
	sub	ecx, esi
	KAPI_CALL socket_write
	pop	ecx
	dec	ecx
	jnz	0b

	pop	fs

	LOAD_TXT "</pre></body></html>\n"
	call	strlen_
	KAPI_CALL socket_write
	KAPI_CALL socket_flush
	KAPI_CALL socket_close
	ret
