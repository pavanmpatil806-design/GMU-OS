; ==================================================================
; GMU OS 64 -- C compiler and bytecode virtual machine ("CC" command)
;
; CC FILE.C  compiles a C program (from any USB drive, USBn:FILE.C)
; to bytecode and runs it.  Supported C subset:
;   int / char / void, globals and locals, int arrays (with {..} init),
;   functions with parameters and recursion, if/else, while, for,
;   break, continue, return, all arithmetic / bitwise / logical /
;   comparison operators, ?:, ++ -- += -= *= /= %=, // and /* */
;   comments, #include lines (ignored), string literals for printf/puts.
;   Builtins: printf (%d %i %x %c %s %%, width e.g. %5d), putchar, puts,
;   getchar, exit.
; Not supported yet: pointers, structs, floats, switch, char arrays,
;   typedef, macros (#define), multiple files.
;
; Pipeline: lexer -> single-pass compiler (emits bytecode directly)
;           -> VM (interprets the bytecode with an operand stack).
; Bytecode: 1 opcode byte, then 0-2 immediate qwords (8 bytes each).
; ==================================================================

C_TAG		equ 0x4000000000000000	; marks string-literal values

TK_EOF		equ 0
TK_NUM		equ 1
TK_ID		equ 2
TK_KW		equ 3
TK_STR		equ 4
TK_OP		equ 5

KW_INT		equ 1
KW_VOID		equ 2
KW_CHAR		equ 3
KW_IF		equ 4
KW_ELSE		equ 5
KW_WHILE	equ 6
KW_FOR		equ 7
KW_RETURN	equ 8
KW_BREAK	equ 9
KW_CONTINUE	equ 10

; two-character operator tokens: first char | second char << 8
T2_EQ		equ '=' | ('=' << 8)
T2_NE		equ '!' | ('=' << 8)
T2_LE		equ '<' | ('=' << 8)
T2_GE		equ '>' | ('=' << 8)
T2_AND		equ '&' | ('&' << 8)
T2_OR		equ '|' | ('|' << 8)
T2_INC		equ '+' | ('+' << 8)
T2_DEC		equ '-' | ('-' << 8)
T2_ADDEQ	equ '+' | ('=' << 8)
T2_SUBEQ	equ '-' | ('=' << 8)
T2_MULEQ	equ '*' | ('=' << 8)
T2_DIVEQ	equ '/' | ('=' << 8)
T2_MODEQ	equ '%' | ('=' << 8)
T2_SHL		equ '<' | ('<' << 8)
T2_SHR		equ '>' | ('>' << 8)

; bytecode opcodes
OP_HALT		equ 0
OP_PUSH		equ 1		; imm
OP_POP		equ 2
OP_DUP		equ 3
OP_LDL		equ 4		; imm slot
OP_STL		equ 5		; imm slot
OP_LDG		equ 6		; imm slot
OP_STG		equ 7		; imm slot
OP_LDLI		equ 8		; imm base, imm size   (pop index, push value)
OP_STLI		equ 9		; imm base, imm size   (pop value, pop index, push value)
OP_LDGI		equ 10
OP_STGI		equ 11
OP_ADD		equ 12
OP_SUB		equ 13
OP_MUL		equ 14
OP_DIV		equ 15
OP_MOD		equ 16
OP_NEG		equ 17
OP_NOT		equ 18
OP_BNOT		equ 19
OP_LT		equ 20
OP_LE		equ 21
OP_GT		equ 22
OP_GE		equ 23
OP_EQ		equ 24
OP_NE		equ 25
OP_BAND		equ 26
OP_BOR		equ 27
OP_BXOR		equ 28
OP_SHL		equ 29
OP_SHR		equ 30
OP_JMP		equ 31		; imm addr
OP_JZ		equ 32		; imm addr
OP_JNZ		equ 33		; imm addr
OP_CALL		equ 34		; imm addr, imm nargs
OP_ENTER	equ 35		; imm nparams, imm nslots
OP_RET		equ 36
OP_BUILTIN	equ 37		; imm id, imm nargs

CC_MAXCODE	equ 65000

; ------------------------------------------------------------------
; cc_compile -- compile the source in c_src (zero terminated)
; OUT: carry clear on success (bytecode in c_code), set on error
; (the error message has already been printed)

cc_compile:
	mov [cc_rsp], rsp
	mov qword [code_len], 0
	mov qword [sym_count], 0
	mov qword [sym_globals], 0
	mov qword [g_count], 0
	mov qword [fn_count], 0
	mov qword [patch_count], 0
	mov qword [brk_count], 0
	mov qword [loop_depth], 0
	mov qword [lex_pos], 0
	mov qword [cur_line], 1
	mov qword [strs_top], 0
	mov qword [cur_nslots], 0
	; entry stub:  CALL main 0 ; HALT
	mov al, OP_CALL
	call cc_emit_b
	lea rsi, [rel s_main]
	call cc_find_or_add_fn
	mov rcx, rax
	mov rax, [code_len]
	xor edx, edx
	call cc_patch_add
	xor eax, eax
	call cc_emit_q
	xor eax, eax
	call cc_emit_q
	mov al, OP_HALT
	call cc_emit_b
	call lex_next
.top:
	cmp qword [tok_type], TK_EOF
	je .resolve
	call cc_parse_top
	jmp .top
.resolve:
	mov rcx, 0
.rl:
	cmp rcx, [patch_count]
	jae .ok
	mov [cc_tmp], rcx
	imul rbx, rcx, 24
	lea rdi, [rel c_patch]
	add rdi, rbx
	mov rax, [rdi+8]			; function index
	imul rbx, rax, 64
	lea rsi, [rel c_fns]
	add rsi, rbx				; function entry
	cmp qword [rsi+32], -1
	je .undef
	mov rdx, [rdi+16]			; nargs used
	cmp rdx, [rsi+40]
	jne .argc
	mov rax, [rsi+32]			; address
	mov rdx, [rdi]				; patch position
	lea rbx, [rel c_code]
	mov [rbx+rdx], rax
	mov rcx, [cc_tmp]
	inc rcx
	jmp .rl
.undef:
	lea rsi, [rel msg_undef]
	call os_print_string
	lea rsi, [rel c_fns]
	mov rax, [cc_tmp]
	mov rcx, [rdi+8]
	imul rbx, rcx, 64
	add rsi, rbx
	call os_print_string
	call os_print_newline
	mov rsp, [cc_rsp]
	stc
	ret
.argc:
	lea rsi, [rel msg_argc]
	call cc_error
.ok:
	clc
	ret

; ------------------------------------------------------------------
; cc_error -- print "CC: line N: message" and abort the compile
; IN: RSI = message.  Never returns to its caller (returns to cc_compile's caller)

cc_error:
	push rsi
	lea rsi, [rel cc_err_pre]
	call os_print_string
	mov rax, [cur_line]
	call os_int_to_string
	mov rsi, rax
	call os_print_string
	lea rsi, [rel cc_err_mid]
	call os_print_string
	pop rsi
	call os_print_string
	call os_print_newline
	mov rsp, [cc_rsp]
	stc
	ret

; ------------------------------------------------------------------
; emitting bytecode

cc_emit_b:				; AL = byte
	cmp qword [code_len], CC_MAXCODE
	jae .big
	lea rbx, [rel c_code]
	mov rdi, [code_len]
	mov [rbx+rdi], al
	inc qword [code_len]
	ret
.big:
	lea rsi, [rel msg_big]
	jmp cc_error

cc_emit_q:				; RAX = qword
	cmp qword [code_len], CC_MAXCODE
	jae .big
	lea rbx, [rel c_code]
	mov rdi, [code_len]
	mov [rbx+rdi], rax
	add qword [code_len], 8
	ret
.big:
	lea rsi, [rel msg_big]
	jmp cc_error

cc_emit_jump:				; AL = opcode -> RAX = position of its operand
	call cc_emit_b
	mov rax, [code_len]
	push rax
	xor eax, eax
	call cc_emit_q
	pop rax
	ret

cc_patch_here:				; RDX = operand position -> store current code_len there
	lea rbx, [rel c_code]
	mov rax, [code_len]
	mov [rbx+rdx], rax
	ret

; ------------------------------------------------------------------
; lexer

lex_next:
.again:
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	movzx eax, byte [rbx+rdx]
	test al, al
	jz .eof
	cmp al, 10
	jne .not_nl
	inc qword [cur_line]
	inc qword [lex_pos]
	jmp .again
.not_nl:
	cmp al, ' '
	je .skip1
	cmp al, 9
	je .skip1
	cmp al, 13
	je .skip1
	cmp al, '#'
	je .skipline
	cmp al, '/'
	jne .not_slash
	movzx ecx, byte [rbx+rdx+1]
	cmp cl, '/'
	je .skipline
	cmp cl, '*'
	je .blockc
.not_slash:
	cmp al, '_'
	je .ident
	cmp al, 'a'
	jb .not_lower
	cmp al, 'z'
	jbe .ident
.not_lower:
	cmp al, 'A'
	jb .not_upper
	cmp al, 'Z'
	jbe .ident
.not_upper:
	cmp al, '0'
	jb .not_digit
	cmp al, '9'
	jbe .number
.not_digit:
	cmp al, 39
	je .charlit
	cmp al, '"'
	je .strlit
	jmp .operator

.skip1:
	inc qword [lex_pos]
	jmp .again

.skipline:				; skip to end of line (not past the newline)
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
.sl:
	movzx eax, byte [rbx+rdx]
	test al, al
	jz .sl_end
	cmp al, 10
	je .sl_end
	inc rdx
	jmp .sl
.sl_end:
	mov [lex_pos], rdx
	jmp .again

.blockc:				; /* ... */
	add rdx, 2
.bc:
	movzx eax, byte [rbx+rdx]
	test al, al
	jz .bc_eof
	cmp al, '*'
	jne .bc_nostar
	cmp byte [rbx+rdx+1], '/'
	jne .bc_nostar
	add rdx, 2
	mov [lex_pos], rdx
	jmp .again
.bc_nostar:
	cmp al, 10
	jne .bc_next
	inc qword [cur_line]
.bc_next:
	inc rdx
	jmp .bc
.bc_eof:
	mov [lex_pos], rdx
.eof:
	mov qword [tok_type], TK_EOF
	mov qword [tok_val], 0
	ret

.ident:
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	lea rdi, [rel c_name]
	xor ecx, ecx
.idl:
	movzx eax, byte [rbx+rdx]
	cmp al, '_'
	je .idc
	cmp al, '0'
	jb .idend
	cmp al, '9'
	jbe .idc
	cmp al, 'A'
	jb .idend
	cmp al, 'Z'
	jbe .idc
	cmp al, 'a'
	jb .idend
	cmp al, 'z'
	jbe .idc
	jmp .idend
.idc:
	cmp ecx, 62
	jae .idskip
	mov [rdi+rcx], al
	inc ecx
.idskip:
	inc rdx
	jmp .idl
.idend:
	mov byte [rdi+rcx], 0
	mov [lex_pos], rdx
	lea rsi, [rel c_name]
	lea rdi, [rel kw_table]
	call cc_table_lookup
	test rax, rax
	jz .idplain
	mov [tok_val], rax
	mov qword [tok_type], TK_KW
	ret
.idplain:
	mov qword [tok_type], TK_ID
	mov qword [tok_val], 0
	ret

.number:
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	xor eax, eax
	movzx r8d, byte [rbx+rdx]
	cmp r8b, '0'
	jne .decl
	movzx r8d, byte [rbx+rdx+1]
	cmp r8b, 'x'
	jne .decl
	add rdx, 2
.hexl:
	movzx r8d, byte [rbx+rdx]
	cmp r8b, '0'
	jb .numend
	cmp r8b, '9'
	jbe .hexd
	or r8b, 0x20
	cmp r8b, 'a'
	jb .numend
	cmp r8b, 'f'
	ja .numend
	sub r8d, 'a' - 10
	jmp .hexacc
.hexd:
	sub r8d, '0'
.hexacc:
	shl rax, 4
	or rax, r8
	inc rdx
	jmp .hexl
.decl:
	movzx r8d, byte [rbx+rdx]
	cmp r8b, '0'
	jb .numend
	cmp r8b, '9'
	ja .numend
	imul rax, rax, 10
	sub r8d, '0'
	add rax, r8
	inc rdx
	jmp .decl
.numend:
	mov [lex_pos], rdx
	mov [tok_val], rax
	mov qword [tok_type], TK_NUM
	ret

.charlit:				; 'x' or '\n'
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	inc rdx
	movzx eax, byte [rbx+rdx]
	cmp al, 92
	jne .cplain
	inc rdx
	movzx eax, byte [rbx+rdx]
	call cc_unescape
.cplain:
	inc rdx
	inc rdx
	mov [lex_pos], rdx
	movzx eax, al
	mov [tok_val], rax
	mov qword [tok_type], TK_NUM
	ret

.strlit:
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	inc rdx
	lea r8, [rel c_strs]
	mov rdi, [strs_top]
	mov r9, rdi
.sl2:
	movzx eax, byte [rbx+rdx]
	test al, al
	jz .strerr
	cmp al, 10
	je .strerr
	cmp al, '"'
	je .sdone
	cmp al, 92
	jne .sput
	inc rdx
	movzx eax, byte [rbx+rdx]
	call cc_unescape
.sput:
	cmp rdi, 16000
	jae .strerr
	mov [r8+rdi], al
	inc rdi
	inc rdx
	jmp .sl2
.sdone:
	mov byte [r8+rdi], 0
	inc rdi
	inc rdx
	mov [strs_top], rdi
	mov [lex_pos], rdx
	mov [tok_val], r9
	mov qword [tok_type], TK_STR
	ret
.strerr:
	lea rsi, [rel msg_str]
	jmp cc_error

.operator:
	lea rbx, [rel c_src]
	mov rdx, [lex_pos]
	movzx eax, byte [rbx+rdx]
	movzx ecx, byte [rbx+rdx+1]
	lea rdi, [rel op2_table]
	mov r8d, 15
.o2:
	cmp al, [rdi]
	jne .o2n
	cmp cl, [rdi+1]
	je .two
.o2n:
	add rdi, 2
	dec r8d
	jnz .o2
	inc rdx
	mov [lex_pos], rdx
	mov [tok_val], rax
	mov qword [tok_type], TK_OP
	ret
.two:
	add rdx, 2
	mov [lex_pos], rdx
	shl rcx, 8
	or rax, rcx
	mov [tok_val], rax
	mov qword [tok_type], TK_OP
	ret

; cc_unescape -- AL = char after a backslash -> AL = the real character
cc_unescape:
	cmp al, 'n'
	jne .t
	mov al, 10
	ret
.t:
	cmp al, 't'
	jne .r
	mov al, 9
	ret
.r:
	cmp al, 'r'
	jne .z
	mov al, 13
	ret
.z:
	cmp al, '0'
	jne .x
	mov al, 0
.x:
	ret

; cc_table_lookup -- RSI = name, RDI = table of (name,0,id) entries ending with 0
; OUT: RAX = id, or 0 if the name is not in the table
cc_table_lookup:
	push rsi
	mov r9, rsi
.next:
	cmp byte [rdi], 0
	je .none
	mov rsi, r9
	push rdi
	call os_string_compare
	pop rdi
	jc .found
.skip:
	cmp byte [rdi], 0
	je .skipped
	inc rdi
	jmp .skip
.skipped:
	inc rdi
	inc rdi
	jmp .next
.found:
.fskip:
	cmp byte [rdi], 0
	je .fid
	inc rdi
	jmp .fskip
.fid:
	inc rdi
	movzx eax, byte [rdi]
	pop rsi
	ret
.none:
	xor eax, eax
	pop rsi
	ret

; ------------------------------------------------------------------
; symbols

; cc_sym_entry -- RAX = symbol index -> RBX = address of its 64-byte entry
cc_sym_entry:
	imul rbx, rax, 64
	lea rcx, [rel c_syms]
	add rbx, rcx
	ret

; cc_find_sym -- RSI = name -> RAX = index (searching newest first), or -1
cc_find_sym:
	mov r9, rsi
	mov rcx, [sym_count]
.l:
	test rcx, rcx
	jz .none
	dec rcx
	mov rax, rcx
	imul rax, rax, 64
	lea rdi, [rel c_syms]
	add rdi, rax
	mov rsi, r9
	push rcx
	call os_string_compare
	pop rcx
	jc .found
	jmp .l
.found:
	mov rax, rcx
	ret
.none:
	mov rax, -1
	ret

; cc_add_sym -- RSI = name, RAX = kind (1 scalar, 2 array), RDX = size, R8 = 1 global / 0 local
cc_add_sym:
	mov r9, rax
	mov r10, rdx
	mov rcx, [sym_count]
	cmp rcx, 512
	jae .full
	mov rbx, rcx
	imul rbx, rbx, 64
	lea rdi, [rel c_syms]
	add rdi, rbx
	xor ecx, ecx
.cp:
	cmp ecx, 31
	jae .cpd
	mov al, [rsi+rcx]
	test al, al
	jz .cpd
	mov [rdi+rcx], al
	inc ecx
	jmp .cp
.cpd:
	mov byte [rdi+rcx], 0
	mov [rdi+32], r9
	mov [rdi+48], r10
	mov [rdi+56], r8
	mov rax, 1
	cmp r9, 2
	jne .cnt
	mov rax, r10
.cnt:
	test r8, r8
	jz .local
	mov rdx, [g_count]
	mov [rdi+40], rdx
	add [g_count], rax
	jmp .added
.local:
	mov rdx, [cur_nslots]
	mov [rdi+40], rdx
	add [cur_nslots], rax
.added:
	inc qword [sym_count]
	test r8, r8
	jz .ret
	mov rax, [sym_count]
	mov [sym_globals], rax
.ret:
	ret
.full:
	lea rsi, [rel msg_toomany]
	jmp cc_error

; cc_find_or_add_fn -- RSI = name -> RAX = function index
cc_find_or_add_fn:
	mov r9, rsi
	xor ecx, ecx
.l:
	cmp rcx, [fn_count]
	jae .add
	mov rax, rcx
	imul rax, rax, 64
	lea rdi, [rel c_fns]
	add rdi, rax
	mov rsi, r9
	push rcx
	call os_string_compare
	pop rcx
	jc .found
	inc rcx
	jmp .l
.found:
	mov rax, rcx
	ret
.add:
	cmp qword [fn_count], 128
	jae .full
	mov rcx, [fn_count]
	mov rax, rcx
	imul rax, rax, 64
	lea rdi, [rel c_fns]
	add rdi, rax
	xor edx, edx
.cp:
	cmp edx, 31
	jae .cpd
	mov al, [r9+rdx]
	test al, al
	jz .cpd
	mov [rdi+rdx], al
	inc edx
	jmp .cp
.cpd:
	mov byte [rdi+rdx], 0
	mov qword [rdi+32], -1
	mov qword [rdi+40], 0
	inc qword [fn_count]
	mov rax, rcx
	ret
.full:
	lea rsi, [rel msg_toomany]
	jmp cc_error

; cc_patch_add -- RAX = operand position, RCX = function index, RDX = nargs
cc_patch_add:
	mov rbx, [patch_count]
	cmp rbx, 2048
	jae .full
	imul rdi, rbx, 24
	lea r8, [rel c_patch]
	mov [r8+rdi], rax
	mov [r8+rdi+8], rcx
	mov [r8+rdi+16], rdx
	inc qword [patch_count]
	ret
.full:
	lea rsi, [rel msg_toomany]
	jmp cc_error

; cc_table_lookup helpers for builtins
cc_builtin_id:				; RSI = name -> RAX = builtin id or 0
	lea rdi, [rel bi_table]
	jmp cc_table_lookup

; ------------------------------------------------------------------
; expressions  (precedence climbing with one function per level)

; cc_binops table: (level, token, vm opcode) triples, terminated by level 0xFF
; level 0 = ||, 1 = &&, 2 = |, 3 = ^, 4 = &, 5 = == !=, 6 = < <= > >=,
; 7 = << >>, 8 = + -, 9 = * / %
cc_find_op:				; RDI = level -> RAX = vm opcode (0xF0 &&, 0xF1 ||) or 0
	cmp qword [tok_type], TK_OP
	jne .none
	lea rbx, [rel cc_binops]
	mov rdx, [tok_val]
.scan:
	mov rax, [rbx]
	cmp rax, 0xFF
	je .none
	cmp rax, rdi
	jne .next
	cmp [rbx+8], rdx
	jne .next
	mov rax, [rbx+16]
	ret
.next:
	add rbx, 24
	jmp .scan
.none:
	xor eax, eax
	ret

cc_binops:
	dq 0, T2_OR, 0xF1
	dq 1, T2_AND, 0xF0
	dq 2, '|', OP_BOR
	dq 3, '^', OP_BXOR
	dq 4, '&', OP_BAND
	dq 5, T2_EQ, OP_EQ
	dq 5, T2_NE, OP_NE
	dq 6, '<', OP_LT
	dq 6, T2_LE, OP_LE
	dq 6, '>', OP_GT
	dq 6, T2_GE, OP_GE
	dq 7, T2_SHL, OP_SHL
	dq 7, T2_SHR, OP_SHR
	dq 8, '+', OP_ADD
	dq 8, '-', OP_SUB
	dq 9, '*', OP_MUL
	dq 9, '/', OP_DIV
	dq 9, '%', OP_MOD
	dq 0xFF, 0, 0

; cc_expr -- full expression including ?:
cc_expr:
	xor edi, edi
	call cc_bin
	cmp qword [tok_type], TK_OP
	jne .ret
	cmp qword [tok_val], '?'
	jne .ret
	call lex_next
	mov al, OP_JZ
	call cc_emit_jump
	push rax				; [rsp] = else position
	call cc_expr
	mov rax, ':'
	call cc_expect_op
	mov al, OP_JMP
	call cc_emit_jump
	push rax				; [rsp] = end position, [rsp+8] = else position
	mov rdx, [rsp+8]
	call cc_patch_here
	call cc_expr
	pop rdx
	call cc_patch_here
	pop rax
.ret:
	ret

; cc_expr_list -- expressions separated by commas (the comma operator);
; only used in statements and for-clauses, where ',' cannot be an argument separator
cc_expr_list:
	call cc_expr
.l:
	cmp qword [tok_type], TK_OP
	jne .r
	cmp qword [tok_val], ','
	jne .r
	mov al, OP_POP
	call cc_emit_b
	call lex_next
	call cc_expr
	jmp .l
.r:
	ret

; cc_bin -- binary operators of precedence level RDI and tighter
cc_bin:
	push rdi				; [rsp] = level
	cmp rdi, 10
	jb .lvl
	pop rdi
	jmp cc_unary
.lvl:
	inc rdi
	call cc_bin
.loop:
	mov rdi, [rsp]
	call cc_find_op
	test rax, rax
	jz .done
	push rax				; [rsp] = vm op, [rsp+8] = level
	call lex_next
	cmp qword [rsp], 0xF0
	je .logic
	cmp qword [rsp], 0xF1
	je .logic
	mov rdi, [rsp+8]
	inc rdi
	call cc_bin
	pop rax
	call cc_emit_b
	jmp .loop
.logic:
	mov rax, OP_JZ
	cmp qword [rsp], 0xF1
	jne .lj
	mov rax, OP_JNZ
.lj:
	call cc_emit_jump
	push rax				; [rsp] = pos1, [rsp+8] = vm op, [rsp+16] = level
	mov rdi, [rsp+16]
	inc rdi
	call cc_bin
	mov al, OP_NOT
	call cc_emit_b
	mov al, OP_NOT
	call cc_emit_b
	mov al, OP_JMP
	call cc_emit_jump
	push rax				; [rsp] = pos2, [rsp+8] = pos1, [rsp+16] = vm op
	mov rdx, [rsp+8]
	call cc_patch_here
	mov al, OP_PUSH
	call cc_emit_b
	xor eax, eax
	cmp qword [rsp+16], 0xF1
	jne .pv
	mov eax, 1
.pv:
	call cc_emit_q
	mov rdx, [rsp]
	call cc_patch_here
	pop rax
	pop rax
	pop rax
	jmp .loop
.done:
	pop rdi
	ret

; cc_unary -- prefix operators and primaries
cc_unary:
	cmp qword [tok_type], TK_OP
	jne .primary
	mov rax, [tok_val]
	cmp rax, '-'
	je .neg
	cmp rax, '!'
	je .not
	cmp rax, '~'
	je .bnot
	cmp rax, '+'
	je .plus
	cmp rax, T2_INC
	je .preinc
	cmp rax, T2_DEC
	je .predec
.primary:
	jmp cc_primary
.neg:
	call lex_next
	call cc_unary
	mov al, OP_NEG
	jmp cc_emit_b
.not:
	call lex_next
	call cc_unary
	mov al, OP_NOT
	jmp cc_emit_b
.bnot:
	call lex_next
	call cc_unary
	mov al, OP_BNOT
	jmp cc_emit_b
.plus:
	call lex_next
	jmp cc_unary
.preinc:
	call lex_next
	mov rcx, OP_ADD
	jmp cc_prefix_var
.predec:
	call lex_next
	mov rcx, OP_SUB
	jmp cc_prefix_var

; cc_prefix_var -- ++x / --x on a scalar variable (RCX = OP_ADD or OP_SUB)
cc_prefix_var:
	sub rsp, 16
	mov [rsp], rcx
	cmp qword [tok_type], TK_ID
	jne .bad
	lea rsi, [rel c_name]
	call cc_find_sym
	cmp rax, -1
	je .undef
	mov [rsp+8], rax
	call lex_next
	mov rax, [rsp+8]
	call cc_emit_load
	mov al, OP_PUSH
	call cc_emit_b
	mov eax, 1
	call cc_emit_q
	mov rax, [rsp]
	call cc_emit_b
	mov rax, [rsp+8]
	call cc_emit_store
	add rsp, 16
	ret
.bad:
	add rsp, 16
	lea rsi, [rel msg_expr]
	jmp cc_error
.undef:
	add rsp, 16
	lea rsi, [rel msg_undef_var]
	jmp cc_error

; cc_primary -- numbers, strings, parentheses, identifiers
cc_primary:
	mov rax, [tok_type]
	cmp rax, TK_NUM
	jne .notnum
	mov al, OP_PUSH
	call cc_emit_b
	mov rax, [tok_val]
	call cc_emit_q
	jmp lex_next
.notnum:
	cmp rax, TK_STR
	jne .notstr
	mov al, OP_PUSH
	call cc_emit_b
	mov rax, [tok_val]
	mov rcx, C_TAG
	or rax, rcx
	call cc_emit_q
	jmp lex_next
.notstr:
	cmp rax, TK_ID
	je cc_ident
	cmp rax, TK_OP
	jne .bad
	cmp qword [tok_val], '('
	jne .bad
	call lex_next
	call cc_expr
	mov rax, ')'
	jmp cc_expect_op
.bad:
	lea rsi, [rel msg_expr]
	jmp cc_error

; cc_ident -- a variable, an array element, an assignment, or a function call
; frame: [rsp] = name (64 bytes), [rsp+64] = symbol index,
;        [rsp+72] = function index (or 1000+builtin id), [rsp+80] = nargs,
;        [rsp+88] = saved operator
cc_ident:
	sub rsp, 96
	lea rsi, [rel c_name]
	mov rdi, rsp
	mov rcx, 64
	rep movsb
	mov rsi, rsp
	call cc_find_sym
	mov [rsp+64], rax
	call lex_next
	cmp qword [tok_type], TK_OP
	jne .var
	cmp qword [tok_val], '('
	je .call
.var:
	mov rax, [rsp+64]
	cmp rax, -1
	je .undef
	call cc_sym_entry
	cmp qword [rbx+32], 2
	je .arr
	; ---- scalar variable
	cmp qword [tok_type], TK_OP
	jne .sload
	mov rax, [tok_val]
	cmp rax, '='
	je .sassign
	cmp rax, T2_INC
	je .spost
	cmp rax, T2_DEC
	je .spost
	call cc_assign_op
	test rax, rax
	jnz .scomp
.sload:
	mov rax, [rsp+64]
	call cc_emit_load
	jmp .ret
.sassign:
	call lex_next
	call cc_expr
	mov rax, [rsp+64]
	call cc_emit_store
	jmp .ret
.scomp:
	mov [rsp+88], rax
	mov rax, [rsp+64]
	call cc_emit_load
	call lex_next
	call cc_expr
	mov rax, [rsp+88]
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_store
	jmp .ret
.spost:
	mov [rsp+88], rax
	call lex_next
	mov rax, [rsp+64]
	call cc_emit_load
	mov al, OP_DUP
	call cc_emit_b
	mov al, OP_PUSH
	call cc_emit_b
	mov eax, 1
	call cc_emit_q
	mov eax, OP_ADD
	cmp qword [rsp+88], T2_DEC
	jne .sp1
	mov eax, OP_SUB
.sp1:
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_store
	mov al, OP_POP
	call cc_emit_b
	jmp .ret
; ---- array element  name[index]
.arr:
	cmp qword [tok_type], TK_OP
	jne .arr_err
	cmp qword [tok_val], '['
	jne .arr_err
	call lex_next
	call cc_expr
	mov rax, ']'
	call cc_expect_op
	cmp qword [tok_type], TK_OP
	jne .aload
	mov rax, [tok_val]
	cmp rax, '='
	je .aassign
	cmp rax, T2_INC
	je .apost
	cmp rax, T2_DEC
	je .apost
	call cc_assign_op
	test rax, rax
	jnz .acomp
.aload:
	mov rax, [rsp+64]
	call cc_emit_aload
	jmp .ret
.aassign:
	call lex_next
	call cc_expr
	mov rax, [rsp+64]
	call cc_emit_astore
	jmp .ret
.acomp:
	mov [rsp+88], rax
	mov al, OP_DUP
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_aload
	call lex_next
	call cc_expr
	mov rax, [rsp+88]
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_astore
	jmp .ret
.apost:
	mov [rsp+88], rax
	call lex_next
	mov al, OP_DUP
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_aload
	mov al, OP_PUSH
	call cc_emit_b
	mov eax, 1
	call cc_emit_q
	mov eax, OP_ADD
	cmp qword [rsp+88], T2_DEC
	jne .ap1
	mov eax, OP_SUB
.ap1:
	call cc_emit_b
	mov rax, [rsp+64]
	call cc_emit_astore
	jmp .ret
; ---- function call or builtin
.call:
	call lex_next				; the '('
	lea rsi, [rsp]
	call cc_builtin_id
	test rax, rax
	jz .userfn
	add rax, 1000
	mov [rsp+72], rax
	jmp .args
.userfn:
	lea rsi, [rsp]
	call cc_find_or_add_fn
	mov [rsp+72], rax
.args:
	mov qword [rsp+80], 0
	cmp qword [tok_type], TK_OP
	jne .argloop
	cmp qword [tok_val], ')'
	je .argsdone
.argloop:
	call cc_expr
	inc qword [rsp+80]
	cmp qword [tok_type], TK_OP
	jne .argsdone
	cmp qword [tok_val], ','
	jne .argsdone
	call lex_next
	jmp .argloop
.argsdone:
	mov rax, ')'
	call cc_expect_op
	mov rax, [rsp+72]
	cmp rax, 1000
	jae .builtin
	mov al, OP_CALL
	call cc_emit_b
	mov rax, [code_len]
	mov rcx, [rsp+72]
	mov rdx, [rsp+80]
	call cc_patch_add
	xor eax, eax
	call cc_emit_q
	mov rax, [rsp+80]
	call cc_emit_q
	jmp .ret
.builtin:
	sub rax, 1000
	mov [rsp+72], rax
	mov al, OP_BUILTIN
	call cc_emit_b
	mov rax, [rsp+72]
	call cc_emit_q
	mov rax, [rsp+80]
	call cc_emit_q
	jmp .ret
.undef:
	add rsp, 96
	lea rsi, [rel msg_undef_var]
	jmp cc_error
.arr_err:
	lea rsi, [rel msg_noindex]
	jmp cc_error
.ret:
	add rsp, 96
	ret

; error for an array name used without an index

; cc_assign_op -- RAX = token -> RAX = VM opcode for op= or 0
cc_assign_op:
	cmp rax, T2_ADDEQ
	jne .a
	mov eax, OP_ADD
	ret
.a:
	cmp rax, T2_SUBEQ
	jne .b
	mov eax, OP_SUB
	ret
.b:
	cmp rax, T2_MULEQ
	jne .c
	mov eax, OP_MUL
	ret
.c:
	cmp rax, T2_DIVEQ
	jne .d
	mov eax, OP_DIV
	ret
.d:
	cmp rax, T2_MODEQ
	jne .e
	mov eax, OP_MOD
	ret
.e:
	xor eax, eax
	ret

; cc_expect_op -- RAX = required operator token; consumes it or errors
cc_expect_op:
	mov rcx, rax
	cmp qword [tok_type], TK_OP
	jne .bad
	cmp [tok_val], rcx
	jne .bad
	jmp lex_next
.bad:
	lea rsi, [rel msg_syntax]
	jmp cc_error

; ------------------------------------------------------------------
; code generation helpers for variables

cc_emit_load:				; RAX = symbol index
	call cc_sym_entry
	mov r8, [rbx+40]
	mov eax, OP_LDL
	cmp qword [rbx+56], 0
	je .l
	mov eax, OP_LDG
.l:
	call cc_emit_b
	mov rax, r8
	jmp cc_emit_q

cc_emit_store:				; RAX = symbol index
	call cc_sym_entry
	mov r8, [rbx+40]
	mov eax, OP_STL
	cmp qword [rbx+56], 0
	je .l
	mov eax, OP_STG
.l:
	call cc_emit_b
	mov rax, r8
	jmp cc_emit_q

cc_emit_aload:				; RAX = symbol index (array)
	call cc_sym_entry
	mov r8, [rbx+40]
	mov r9, [rbx+48]
	mov eax, OP_LDLI
	cmp qword [rbx+56], 0
	je .l
	mov eax, OP_LDGI
.l:
	call cc_emit_b
	mov rax, r8
	call cc_emit_q
	mov rax, r9
	jmp cc_emit_q

cc_emit_astore:				; RAX = symbol index (array)
	call cc_sym_entry
	mov r8, [rbx+40]
	mov r9, [rbx+48]
	mov eax, OP_STLI
	cmp qword [rbx+56], 0
	je .l
	mov eax, OP_STGI
.l:
	call cc_emit_b
	mov rax, r8
	call cc_emit_q
	mov rax, r9
	jmp cc_emit_q

; ------------------------------------------------------------------
; statements

; cc_block -- '{' statements '}' with its own variable scope
cc_block:
	mov rax, '{'
	call cc_expect_op
	push qword [sym_count]
.stmts:
	cmp qword [tok_type], TK_EOF
	je .eof
	cmp qword [tok_type], TK_OP
	jne .stmt
	cmp qword [tok_val], '}'
	je .end
.stmt:
	call cc_stmt
	jmp .stmts
.end:
	call lex_next
	pop qword [sym_count]
	ret
.eof:
	lea rsi, [rel msg_eof]
	jmp cc_error

cc_stmt:
	cmp qword [tok_type], TK_KW
	je .kw
	cmp qword [tok_type], TK_OP
	jne .expr
	mov rax, [tok_val]
	cmp rax, '{'
	je cc_block
	cmp rax, ';'
	je .semi
.expr:
	call cc_expr_list
	mov al, OP_POP
	call cc_emit_b
	mov rax, ';'
	jmp cc_expect_op
.semi:
	jmp lex_next
.kw:
	mov rax, [tok_val]
	cmp rax, KW_INT
	je cc_local_decl
	cmp rax, KW_CHAR
	je cc_local_decl
	cmp rax, KW_IF
	je .if
	cmp rax, KW_WHILE
	je .while
	cmp rax, KW_FOR
	je .for
	cmp rax, KW_RETURN
	je .return
	cmp rax, KW_BREAK
	je .break
	cmp rax, KW_CONTINUE
	je .continue
	jmp .expr

.if:
	call lex_next
	mov rax, '('
	call cc_expect_op
	call cc_expr
	mov rax, ')'
	call cc_expect_op
	mov al, OP_JZ
	call cc_emit_jump
	push rax				; [rsp] = else position
	call cc_stmt
	cmp qword [tok_type], TK_KW
	jne .if_noelse
	cmp qword [tok_val], KW_ELSE
	jne .if_noelse
	mov al, OP_JMP
	call cc_emit_jump
	push rax				; [rsp] = end position, [rsp+8] = else position
	mov rdx, [rsp+8]
	call cc_patch_here
	call lex_next
	call cc_stmt
	pop rdx
	call cc_patch_here
	pop rax
	ret
.if_noelse:
	pop rdx
	call cc_patch_here
	ret

.while:
	call lex_next
	mov rax, [code_len]
	push rax				; [rsp] = loop start
	mov rax, '('
	call cc_expect_op
	call cc_expr
	mov rax, ')'
	call cc_expect_op
	mov al, OP_JZ
	call cc_emit_jump
	push rax				; [rsp] = exit position, [rsp+8] = loop start
	mov rdi, [rsp+8]
	call cc_loop_enter
	call cc_stmt
	mov al, OP_JMP
	call cc_emit_b
	mov rax, [rsp+8]
	call cc_emit_q
	pop rdx
	call cc_patch_here
	call cc_loop_exit
	pop rax
	ret

.for:
	call lex_next
	mov rax, '('
	call cc_expect_op
	cmp qword [tok_type], TK_KW
	jne .for_init_expr
	mov rax, [tok_val]
	cmp rax, KW_INT
	je .for_init_decl
	cmp rax, KW_CHAR
	je .for_init_decl
.for_init_expr:
	cmp qword [tok_type], TK_OP
	jne .for_init_e
	cmp qword [tok_val], ';'
	je .for_init_skip
.for_init_e:
	call cc_expr_list
	mov al, OP_POP
	call cc_emit_b
	mov rax, ';'
	call cc_expect_op
	jmp .for_cond
.for_init_skip:
	call lex_next
	jmp .for_cond
.for_init_decl:
	call cc_local_decl
.for_cond:
	mov rax, [code_len]
	push rax				; [rsp] = cond start
	cmp qword [tok_type], TK_OP
	jne .fc_expr
	cmp qword [tok_val], ';'
	jne .fc_expr
	mov al, OP_PUSH
	call cc_emit_b
	mov eax, 1
	call cc_emit_q
	jmp .fc_semi
.fc_expr:
	call cc_expr
.fc_semi:
	mov rax, ';'
	call cc_expect_op
	mov al, OP_JZ
	call cc_emit_jump
	push rax				; [rsp] = exit pos, [rsp+8] = cond start
	mov al, OP_JMP
	call cc_emit_jump
	push rax				; [rsp] = body-jump pos, [rsp+8] = exit pos, [rsp+16] = cond start
	mov rax, [code_len]
	mov rdi, rax
	push rax				; [rsp] = increment start, ...
	call cc_loop_enter_inc
	cmp qword [tok_type], TK_OP
	jne .fi_expr
	cmp qword [tok_val], ')'
	je .fi_none
.fi_expr:
	call cc_expr_list
	mov al, OP_POP
	call cc_emit_b
.fi_none:
	mov rax, ')'
	call cc_expect_op
	mov al, OP_JMP
	call cc_emit_b
	mov rax, [rsp+24]
	call cc_emit_q
	mov rdx, [rsp+8]
	call cc_patch_here
	call cc_stmt
	mov al, OP_JMP
	call cc_emit_b
	mov rax, [rsp]
	call cc_emit_q
	mov rdx, [rsp+16]
	call cc_patch_here
	call cc_loop_exit
	add rsp, 32
	ret

.return:
	call lex_next
	cmp qword [tok_type], TK_OP
	jne .ret_expr
	cmp qword [tok_val], ';'
	jne .ret_expr
	mov al, OP_PUSH
	call cc_emit_b
	xor eax, eax
	call cc_emit_q
	jmp .ret_end
.ret_expr:
	call cc_expr
.ret_end:
	mov rax, ';'
	call cc_expect_op
	mov al, OP_RET
	jmp cc_emit_b

.break:
	call lex_next
	mov rax, ';'
	call cc_expect_op
	cmp qword [loop_depth], 0
	je .brk_err
	mov al, OP_JMP
	call cc_emit_jump
	mov rcx, [loop_depth]
	call cc_brk_add
	ret
.brk_err:
	lea rsi, [rel msg_brk]
	jmp cc_error

.continue:
	call lex_next
	mov rax, ';'
	call cc_expect_op
	cmp qword [loop_depth], 0
	je .cont_err
	mov rax, [loop_depth]
	dec rax
	lea rbx, [rel loop_cont]
	mov r8, [rbx+rax*8]
	mov al, OP_JMP
	call cc_emit_b
	mov rax, r8
	jmp cc_emit_q
.cont_err:
	lea rsi, [rel msg_cont]
	jmp cc_error

; loops: continue targets are kept in loop_cont[depth]; breaks are in c_brk
cc_loop_enter:				; RDI = continue address
	mov rax, [loop_depth]
	lea rbx, [rel loop_cont]
	mov [rbx+rax*8], rdi
	inc qword [loop_depth]
	ret

cc_loop_enter_inc:			; RDI = increment address (same as cc_loop_enter)
	jmp cc_loop_enter

cc_loop_exit:				; patch pending breaks of this loop to here, leave the loop
	lea r8, [rel c_brk]
.l:
	cmp qword [brk_count], 0
	je .d
	mov rdi, [brk_count]
	dec rdi
	shl rdi, 1
	mov rcx, [r8+rdi*8+8]
	cmp rcx, [loop_depth]
	jne .d
	mov rdx, [r8+rdi*8]
	call cc_patch_here
	dec qword [brk_count]
	jmp .l
.d:
	dec qword [loop_depth]
	ret

cc_brk_add:				; RAX = operand position, RCX = depth
	mov rbx, [brk_count]
	cmp rbx, 256
	jae .full
	mov rdi, rbx
	shl rdi, 1
	lea r8, [rel c_brk]
	mov [r8+rdi*8], rax
	mov [r8+rdi*8+8], rcx
	inc qword [brk_count]
	ret
.full:
	lea rsi, [rel msg_toomany]
	jmp cc_error

; cc_local_decl -- int a, b = 1, c[10] = {1,2}; (consumes the ';')
cc_local_decl:
	call lex_next
.dl:
	cmp qword [tok_type], TK_ID
	jne .dl_err
	sub rsp, 80				; [rsp] = name, [rsp+64] = size, [rsp+72] = kind
	lea rsi, [rel c_name]
	mov rdi, rsp
	mov rcx, 64
	rep movsb
	call lex_next
	mov qword [rsp+64], 0
	mov qword [rsp+72], 1
	cmp qword [tok_type], TK_OP
	jne .dl_add
	cmp qword [tok_val], '['
	jne .dl_add
	call lex_next
	cmp qword [tok_type], TK_NUM
	jne .dl_err
	mov rax, [tok_val]
	mov [rsp+64], rax
	mov qword [rsp+72], 2
	call lex_next
	mov rax, ']'
	call cc_expect_op
.dl_add:
	mov rsi, rsp
	mov rax, [rsp+72]
	mov rdx, [rsp+64]
	xor r8d, r8d
	call cc_add_sym
	cmp qword [tok_type], TK_OP
	jne .dl_done
	cmp qword [tok_val], '='
	jne .dl_done
	call lex_next
	cmp qword [rsp+72], 2
	je .dl_arrinit
	call cc_expr
	mov rax, [sym_count]
	dec rax
	call cc_emit_store
	mov al, OP_POP
	call cc_emit_b
	jmp .dl_done
.dl_arrinit:
	mov rax, '{'
	call cc_expect_op
	push qword 0				; [rsp] = element index
.ai:
	cmp qword [tok_type], TK_OP
	jne .ai_end
	cmp qword [tok_val], '}'
	je .ai_end
	mov al, OP_PUSH
	call cc_emit_b
	mov rax, [rsp]
	call cc_emit_q
	call cc_expr
	mov rax, [sym_count]
	dec rax
	call cc_emit_astore
	mov al, OP_POP
	call cc_emit_b
	inc qword [rsp]
	cmp qword [tok_type], TK_OP
	jne .ai_end
	cmp qword [tok_val], ','
	jne .ai_end
	call lex_next
	jmp .ai
.ai_end:
	mov rax, '}'
	call cc_expect_op
	add rsp, 8
.dl_done:
	add rsp, 80
	cmp qword [tok_type], TK_OP
	jne .dl_err
	cmp qword [tok_val], ','
	jne .dl_end
	call lex_next
	jmp .dl
.dl_end:
	mov rax, ';'
	jmp cc_expect_op
.dl_err:
	lea rsi, [rel msg_decl]
	jmp cc_error

; ------------------------------------------------------------------
; top level

cc_parse_top:
	cmp qword [tok_type], TK_KW
	jne .bad
	mov rax, [tok_val]
	cmp rax, KW_INT
	je .ok
	cmp rax, KW_CHAR
	je .ok
	cmp rax, KW_VOID
	jne .bad
.ok:
	call lex_next
	cmp qword [tok_type], TK_ID
	jne .bad
	sub rsp, 96
	lea rsi, [rel c_name]
	mov rdi, rsp
	mov rcx, 64
	rep movsb
	call lex_next
	cmp qword [tok_type], TK_OP
	jne .global
	cmp qword [tok_val], '('
	je .function
.global:
	mov rsi, rsp
	call cc_global_decl
	add rsp, 96
	ret
.function:
	mov rsi, rsp
	call cc_function
	add rsp, 96
	ret
.bad:
	lea rsi, [rel msg_top]
	jmp cc_error

; cc_global_decl -- RSI = name (the rest of the declaration follows)
cc_global_decl:
	sub rsp, 80				; [rsp] = name, [rsp+64] = size, [rsp+72] = kind
	mov rcx, 64
	mov rdi, rsp
	rep movsb
.gloop:
	mov qword [rsp+64], 0
	mov qword [rsp+72], 1
	cmp qword [tok_type], TK_OP
	jne .gadd
	cmp qword [tok_val], '['
	jne .gadd
	call lex_next
	cmp qword [tok_type], TK_NUM
	jne .gerr
	mov rax, [tok_val]
	mov [rsp+64], rax
	mov qword [rsp+72], 2
	call lex_next
	mov rax, ']'
	call cc_expect_op
.gadd:
	mov rsi, rsp
	mov rax, [rsp+72]
	mov rdx, [rsp+64]
	mov r8d, 1
	call cc_add_sym
	cmp qword [tok_type], TK_OP
	jne .gend
	cmp qword [tok_val], '='
	jne .gend
	call lex_next
	mov rax, [sym_count]
	dec rax
	call cc_global_init
.gend:
	cmp qword [tok_type], TK_OP
	jne .gerr
	cmp qword [tok_val], ','
	jne .gsemi
	call lex_next
	cmp qword [tok_type], TK_ID
	jne .gerr
	lea rsi, [rel c_name]
	mov rdi, rsp
	mov rcx, 64
	rep movsb
	call lex_next
	jmp .gloop
.gsemi:
	mov rax, ';'
	call cc_expect_op
	add rsp, 80
	ret
.gerr:
	lea rsi, [rel msg_decl]
	jmp cc_error

; cc_global_init -- RAX = symbol index; initializer is a constant or {c, c, ...}
cc_global_init:
	push rax				; [rsp] = symbol index
	call cc_sym_entry
	mov rax, [rbx+40]
	push rax				; [rsp] = slot, [rsp+8] = symbol index
	cmp qword [tok_type], TK_OP
	jne .single
	cmp qword [tok_val], '{'
	jne .single
	call lex_next
	push qword 0				; [rsp] = i, [rsp+8] = slot
.el:
	call cc_const
	mov rdx, [rsp]
	add rdx, [rsp+8]
	lea rbx, [rel c_glob]
	mov [rbx+rdx*8], rax
	inc qword [rsp]
	cmp qword [tok_type], TK_OP
	jne .eend
	cmp qword [tok_val], ','
	jne .eend
	call lex_next
	jmp .el
.eend:
	mov rax, '}'
	call cc_expect_op
	add rsp, 24
	ret
.single:
	call cc_const
	mov rdx, [rsp]
	lea rbx, [rel c_glob]
	mov [rbx+rdx*8], rax
	add rsp, 16
	ret

; cc_const -- an optionally negated number -> RAX
cc_const:
	xor ecx, ecx
	cmp qword [tok_type], TK_OP
	jne .num
	cmp qword [tok_val], '-'
	jne .num
	mov ecx, 1
	call lex_next
.num:
	cmp qword [tok_type], TK_NUM
	jne .bad
	mov rax, [tok_val]
	test rcx, rcx
	jz .pos
	neg rax
.pos:
	push rax
	call lex_next
	pop rax
	ret
.bad:
	lea rsi, [rel msg_const]
	jmp cc_error

; cc_function -- RSI = name; current token is '('
cc_function:
	call cc_find_or_add_fn
	mov [cur_fn], rax
	call cc_fn_entry
	mov rdx, [code_len]
	mov [rbx+32], rdx
	mov qword [cur_nslots], 0
	call lex_next				; '('
	sub rsp, 16				; [rsp] = nparams, [rsp+8] = ENTER operand position
	mov qword [rsp], 0
.pl:
	cmp qword [tok_type], TK_OP
	je .pdone
	cmp qword [tok_type], TK_KW
	jne .perr
	mov rax, [tok_val]
	cmp rax, KW_VOID
	je .pvoid
	cmp rax, KW_INT
	je .ptype
	cmp rax, KW_CHAR
	je .ptype
	jmp .perr
.pvoid:
	call lex_next
	jmp .pdone
.ptype:
	call lex_next
	cmp qword [tok_type], TK_ID
	jne .perr
	lea rsi, [rel c_name]
	mov rax, 1
	xor edx, edx
	xor r8d, r8d
	call cc_add_sym
	inc qword [rsp]
	call lex_next
	cmp qword [tok_type], TK_OP
	jne .pdone
	cmp qword [tok_val], ','
	jne .pdone
	call lex_next
	jmp .pl
.pdone:
	mov rax, ')'
	call cc_expect_op
	mov al, OP_ENTER
	call cc_emit_b
	mov rax, [rsp]
	call cc_emit_q
	mov rax, [code_len]
	mov [rsp+8], rax
	xor eax, eax
	call cc_emit_q
	mov rax, [cur_fn]
	call cc_fn_entry
	mov rdx, [rsp]
	mov [rbx+40], rdx
	call cc_block
	mov al, OP_PUSH
	call cc_emit_b
	xor eax, eax
	call cc_emit_q
	mov al, OP_RET
	call cc_emit_b
	lea rbx, [rel c_code]
	mov rdx, [rsp+8]
	mov rax, [cur_nslots]
	mov [rbx+rdx], rax
	mov rax, [sym_globals]
	mov [sym_count], rax
	add rsp, 16
	ret
.perr:
	lea rsi, [rel msg_param]
	jmp cc_error

; cc_fn_entry -- RAX = function index -> RBX = address of its entry
cc_fn_entry:
	imul rbx, rax, 64
	lea rcx, [rel c_fns]
	add rbx, rcx
	ret

; ------------------------------------------------------------------
; the CC command

cc_command:
	cmp qword [param_list], 0
	je c_editor				; CC alone: open the editor
.have:
	mov rsi, [param_list]
	call os_string_parse
	mov [cc_name_ptr], rax
	call os_get_file_size
	jc .nf
	cmp rbx, CC_MAXCODE
	ja .big
	mov [cc_fsize], rbx
	mov rax, [cc_name_ptr]
	lea rcx, [rel c_src]
	call os_load_file
	jc .nf
	lea rbx, [rel c_src]
	mov rdi, [cc_fsize]
	mov byte [rbx+rdi], 0
	call cc_compile
	jc .out
	call vm_run
.out:
	jmp get_cmd
.nf:
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd
.big:
	lea rsi, [rel cc_big_msg]
	call os_print_string
	jmp get_cmd

; ==================================================================
; VIRTUAL MACHINE
; State lives in memory (vm_pc, vm_sp, vm_fp, vm_lsp, vm_csp) so that
; the system calls used by the instructions can clobber registers.
; ==================================================================

vm_run:
	mov [vm_rsp], rsp
	mov qword [vm_pc], 0
	mov qword [vm_sp], 0
	mov qword [vm_fp], 0
	mov qword [vm_lsp], 0
	mov qword [vm_csp], 0
	mov qword [vm_exitcode], 0
	jmp vm_next

vm_done:
	mov rsp, [vm_rsp]
	clc
	ret

vm_err:					; RSI = message
	push rsi
	lea rsi, [rel vm_err_pre]
	call os_print_string
	pop rsi
	call os_print_string
	call os_print_newline
	mov rsp, [vm_rsp]
	stc
	ret

; read one opcode and dispatch to its handler
vm_next:
	mov rdi, [vm_pc]
	lea rbx, [rel c_code]
	movzx eax, byte [rbx+rdi]
	inc qword [vm_pc]
	lea rbx, [rel vm_tab]
	movsxd rcx, dword [rbx+rax*4]
	add rbx, rcx
	jmp rbx

; RAX = next immediate qword of the code
vm_imm:
	mov rdi, [vm_pc]
	lea rbx, [rel c_code]
	mov rax, [rbx+rdi]
	add qword [vm_pc], 8
	ret

vm_push:				; RAX -> operand stack
	mov rdi, [vm_sp]
	cmp rdi, 4000
	jae .ovf
	lea rbx, [rel c_stk]
	mov [rbx+rdi*8], rax
	inc qword [vm_sp]
	ret
.ovf:
	lea rsi, [rel vm_m_stack]
	jmp vm_err

vm_pop:					; operand stack -> RAX (clobbers RDI, RBX)
	cmp qword [vm_sp], 0
	je .unf
	dec qword [vm_sp]
	mov rdi, [vm_sp]
	lea rbx, [rel c_stk]
	mov rax, [rbx+rdi*8]
	ret
.unf:
	lea rsi, [rel vm_m_stack]
	jmp vm_err

vm_pop2:				; RAX = second (a), RCX = top (b)
	call vm_pop
	mov rcx, rax
	call vm_pop
	ret

; ---- handlers --------------------------------------------------------
op_halt:
	jmp vm_done

op_push:
	call vm_imm
	call vm_push
	jmp vm_next

op_pop:
	call vm_pop
	jmp vm_next

op_dup:
	cmp qword [vm_sp], 0
	je .unf
	mov rdi, [vm_sp]
	dec rdi
	lea rbx, [rel c_stk]
	mov rax, [rbx+rdi*8]
	call vm_push
	jmp vm_next
.unf:
	lea rsi, [rel vm_m_stack]
	jmp vm_err

op_ldl:
	call vm_imm
	add rax, [vm_fp]
	lea rbx, [rel c_lstk]
	mov rax, [rbx+rax*8]
	call vm_push
	jmp vm_next

op_stl:
	call vm_imm
	mov rdx, rax
	call vm_pop
	add rdx, [vm_fp]
	lea rbx, [rel c_lstk]
	mov [rbx+rdx*8], rax
	call vm_push
	jmp vm_next

op_ldg:
	call vm_imm
	lea rbx, [rel c_glob]
	mov rax, [rbx+rax*8]
	call vm_push
	jmp vm_next

op_stg:
	call vm_imm
	mov rdx, rax
	call vm_pop
	lea rbx, [rel c_glob]
	mov [rbx+rdx*8], rax
	call vm_push
	jmp vm_next

op_ldli:
	call vm_imm
	mov r8, rax				; base
	call vm_imm
	mov r9, rax				; size
	call vm_pop				; index
	cmp rax, r9
	jae vm_index_err
	add rax, r8
	add rax, [vm_fp]
	lea rbx, [rel c_lstk]
	mov rax, [rbx+rax*8]
	call vm_push
	jmp vm_next

op_stli:
	call vm_imm
	mov r8, rax
	call vm_imm
	mov r9, rax
	call vm_pop				; value
	mov rdx, rax
	call vm_pop				; index
	cmp rax, r9
	jae vm_index_err
	add rax, r8
	add rax, [vm_fp]
	lea rbx, [rel c_lstk]
	mov [rbx+rax*8], rdx
	mov rax, rdx
	call vm_push
	jmp vm_next

op_ldgi:
	call vm_imm
	mov r8, rax
	call vm_imm
	mov r9, rax
	call vm_pop
	cmp rax, r9
	jae vm_index_err
	add rax, r8
	lea rbx, [rel c_glob]
	mov rax, [rbx+rax*8]
	call vm_push
	jmp vm_next

op_stgi:
	call vm_imm
	mov r8, rax
	call vm_imm
	mov r9, rax
	call vm_pop
	mov rdx, rax
	call vm_pop
	cmp rax, r9
	jae vm_index_err
	add rax, r8
	lea rbx, [rel c_glob]
	mov [rbx+rax*8], rdx
	mov rax, rdx
	call vm_push
	jmp vm_next

op_add:
	call vm_pop2
	add rax, rcx
	call vm_push
	jmp vm_next

op_sub:
	call vm_pop2
	sub rax, rcx
	call vm_push
	jmp vm_next

op_mul:
	call vm_pop2
	imul rax, rcx
	call vm_push
	jmp vm_next

op_div:
	call vm_pop2
	test rcx, rcx
	jz vm_divzero
	cqo
	idiv rcx
	call vm_push
	jmp vm_next

op_mod:
	call vm_pop2
	test rcx, rcx
	jz vm_divzero
	cqo
	idiv rcx
	mov rax, rdx
	call vm_push
	jmp vm_next

op_neg:
	call vm_pop
	neg rax
	call vm_push
	jmp vm_next

op_not:
	call vm_pop
	test rax, rax
	sete al
	movzx eax, al
	call vm_push
	jmp vm_next

op_bnot:
	call vm_pop
	not rax
	call vm_push
	jmp vm_next

op_lt:
	call vm_pop2
	cmp rax, rcx
	setl al
	movzx eax, al
	call vm_push
	jmp vm_next

op_le:
	call vm_pop2
	cmp rax, rcx
	setle al
	movzx eax, al
	call vm_push
	jmp vm_next

op_gt:
	call vm_pop2
	cmp rax, rcx
	setg al
	movzx eax, al
	call vm_push
	jmp vm_next

op_ge:
	call vm_pop2
	cmp rax, rcx
	setge al
	movzx eax, al
	call vm_push
	jmp vm_next

op_eq:
	call vm_pop2
	cmp rax, rcx
	sete al
	movzx eax, al
	call vm_push
	jmp vm_next

op_ne:
	call vm_pop2
	cmp rax, rcx
	setne al
	movzx eax, al
	call vm_push
	jmp vm_next

op_band:
	call vm_pop2
	and rax, rcx
	call vm_push
	jmp vm_next

op_bor:
	call vm_pop2
	or rax, rcx
	call vm_push
	jmp vm_next

op_bxor:
	call vm_pop2
	xor rax, rcx
	call vm_push
	jmp vm_next

op_shl:
	call vm_pop2
	shl rax, cl
	call vm_push
	jmp vm_next

op_shr:
	call vm_pop2
	sar rax, cl
	call vm_push
	jmp vm_next

op_jmp:
	call vm_imm
	mov [vm_pc], rax
	jmp vm_next

op_jz:
	call vm_imm
	mov rdx, rax
	call vm_pop
	test rax, rax
	jnz vm_next
	mov [vm_pc], rdx
	jmp vm_next

op_jnz:
	call vm_imm
	mov rdx, rax
	call vm_pop
	test rax, rax
	jz vm_next
	mov [vm_pc], rdx
	jmp vm_next

op_call:
	call vm_imm
	mov rdx, rax				; target
	call vm_imm				; number of arguments (checked at compile time)
	mov rdi, [vm_csp]
	cmp rdi, 1000
	jae .ovf
	shl rdi, 1
	lea rbx, [rel c_cstk]
	mov rax, [vm_pc]
	mov [rbx+rdi*8], rax
	mov rax, [vm_fp]
	mov [rbx+rdi*8+8], rax
	inc qword [vm_csp]
	mov rax, [vm_lsp]
	mov [vm_fp], rax
	mov [vm_pc], rdx
	jmp vm_next
.ovf:
	lea rsi, [rel vm_m_calls]
	jmp vm_err

op_enter:
	call vm_imm
	mov r8, rax				; nparams
	call vm_imm
	mov r9, rax				; nslots
	mov rcx, r8
.pa:
	test rcx, rcx
	jz .zero
	dec rcx
	call vm_pop
	mov rdx, [vm_fp]
	add rdx, rcx
	lea rbx, [rel c_lstk]
	mov [rbx+rdx*8], rax
	jmp .pa
.zero:
	mov rcx, r8
.zl:
	cmp rcx, r9
	jae .zdone
	mov rdx, [vm_fp]
	add rdx, rcx
	lea rbx, [rel c_lstk]
	mov qword [rbx+rdx*8], 0
	inc rcx
	jmp .zl
.zdone:
	mov rax, [vm_fp]
	add rax, r9
	cmp rax, 16000
	jae .ovf
	mov [vm_lsp], rax
	jmp vm_next
.ovf:
	lea rsi, [rel vm_m_locals]
	jmp vm_err

op_ret:
	call vm_pop
	mov rdx, [vm_fp]
	mov [vm_lsp], rdx
	dec qword [vm_csp]
	mov rdi, [vm_csp]
	shl rdi, 1
	lea rbx, [rel c_cstk]
	mov rcx, [rbx+rdi*8]
	mov rdx, [rbx+rdi*8+8]
	mov [vm_pc], rcx
	mov [vm_fp], rdx
	call vm_push
	jmp vm_next

op_builtin:
	call vm_imm
	mov [bi_id], rax
	call vm_imm
	mov [bi_nargs], rax
	mov rdi, [vm_sp]
	sub rdi, rax
	mov [bi_base], rdi
	mov rax, [bi_id]
	cmp rax, 1
	je bi_printf
	cmp rax, 2
	je bi_putchar
	cmp rax, 3
	je bi_puts
	cmp rax, 4
	je bi_getchar
	cmp rax, 5
	je bi_exit
	jmp vm_bad_builtin

; store RAX as the result of a builtin (replacing its arguments)
bi_finish:
	mov rdi, [bi_base]
	mov [vm_sp], rdi
	call vm_push
	jmp vm_next

bi_arg0:				; RAX = first argument of the builtin
	cmp qword [bi_nargs], 0
	je vm_no_args
	mov rdi, [bi_base]
	lea rbx, [rel c_stk]
	mov rax, [rbx+rdi*8]
	ret

bi_putchar:
	call bi_arg0
	mov [bi_val], rax
	call vm_putc
	mov rax, [bi_val]
	jmp bi_finish

bi_puts:
	call bi_arg0
	mov rcx, rax
	shr rcx, 62
	cmp rcx, 1
	jne vm_not_string
	btr rax, 62
	lea rsi, [rel c_strs]
	add rsi, rax
	call os_print_string
	call os_print_newline
	xor eax, eax
	jmp bi_finish

bi_getchar:
	call os_wait_for_key
	movzx eax, al
	jmp bi_finish

bi_exit:
	call bi_arg0
	mov [vm_exitcode], rax
	jmp vm_done

; printf(format, args...): %d %i %x %c %s %% with an optional width
bi_printf:
	call bi_arg0
	mov rcx, rax
	shr rcx, 62
	cmp rcx, 1
	jne vm_not_string
	btr rax, 62
	mov [pf_pos], rax
	mov qword [pf_k], 1
.loop:
	lea rbx, [rel c_strs]
	mov rdi, [pf_pos]
	movzx eax, byte [rbx+rdi]
	inc qword [pf_pos]
	test al, al
	jz .done
	cmp al, '%'
	je .conv
	call vm_putc
	jmp .loop
.conv:
	mov qword [pf_w], 0
.wd:
	lea rbx, [rel c_strs]
	mov rdi, [pf_pos]
	movzx eax, byte [rbx+rdi]
	cmp al, '0'
	jb .wdone
	cmp al, '9'
	ja .wdone
	imul rcx, [pf_w], 10
	sub eax, '0'
	add rcx, rax
	mov [pf_w], rcx
	inc qword [pf_pos]
	jmp .wd
.wdone:
	inc qword [pf_pos]
	mov [pf_conv], al
	cmp al, '%'
	jne .arg
	mov al, '%'
	call os_putc
	jmp .loop
.arg:
	mov rax, [pf_k]
	cmp rax, [bi_nargs]
	jae vm_fmt_noarg
	inc qword [pf_k]
	add rax, [bi_base]
	lea rbx, [rel c_stk]
	mov rax, [rbx+rax*8]
	mov [pf_v], rax
	mov al, [pf_conv]
	cmp al, 'd'
	je .dec
	cmp al, 'i'
	je .dec
	cmp al, 'x'
	je .hex
	cmp al, 'c'
	je .chr
	cmp al, 's'
	je .str
	lea rsi, [rel vm_m_conv]
	jmp vm_err
.dec:
	mov rax, [pf_v]
	call os_sint_to_string
	mov rsi, rax
	call pf_pad_print
	jmp .loop
.hex:
	lea rdi, [rel c_numbuf]
	mov rax, [pf_v]
	mov rbx, 16
	call os_long_int_to_string
	lea rax, [rel c_numbuf]
	call os_string_lowercase
	lea rsi, [rel c_numbuf]
	call pf_pad_print
	jmp .loop
.chr:
	mov rax, [pf_v]
	call vm_putc
	jmp .loop
.str:
	mov rax, [pf_v]
	mov rcx, rax
	shr rcx, 62
	cmp rcx, 1
	jne .loop
	btr rax, 62
	lea rsi, [rel c_strs]
	add rsi, rax
	call pf_pad_print
	jmp .loop
.done:
	xor eax, eax
	jmp bi_finish

; vm_putc -- AL = character to print (LF also returns the cursor to column 0)
vm_putc:
	cmp al, 10
	jne .one
	push rax
	mov al, 13
	call os_putc
	pop rax
.one:
	call os_putc
	ret

; pf_pad_print -- RSI = string; prints it right-aligned in pf_w columns
pf_pad_print:
	mov [pf_str], rsi
	mov rax, rsi
	call os_string_length
	mov rcx, [pf_w]
	sub rcx, rax
.pad:
	cmp rcx, 0
	jle .out
	push rcx
	mov al, ' '
	call os_putc
	pop rcx
	dec rcx
	jmp .pad
.out:
	mov rsi, [pf_str]
	call os_print_string
	ret

; ---- run-time error messages
vm_index_err:
	lea rsi, [rel vm_m_index]
	jmp vm_err
vm_divzero:
	lea rsi, [rel vm_m_div]
	jmp vm_err
vm_bad_builtin:
	lea rsi, [rel vm_m_builtin]
	jmp vm_err
vm_no_args:
	lea rsi, [rel vm_m_noargs]
	jmp vm_err
vm_not_string:
	lea rsi, [rel vm_m_notstr]
	jmp vm_err
vm_fmt_noarg:
	lea rsi, [rel vm_m_fewargs]
	jmp vm_err

; ==================================================================
; DATA
; ==================================================================

vm_tab:
	dd op_halt - vm_tab
	dd op_push - vm_tab
	dd op_pop - vm_tab
	dd op_dup - vm_tab
	dd op_ldl - vm_tab
	dd op_stl - vm_tab
	dd op_ldg - vm_tab
	dd op_stg - vm_tab
	dd op_ldli - vm_tab
	dd op_stli - vm_tab
	dd op_ldgi - vm_tab
	dd op_stgi - vm_tab
	dd op_add - vm_tab
	dd op_sub - vm_tab
	dd op_mul - vm_tab
	dd op_div - vm_tab
	dd op_mod - vm_tab
	dd op_neg - vm_tab
	dd op_not - vm_tab
	dd op_bnot - vm_tab
	dd op_lt - vm_tab
	dd op_le - vm_tab
	dd op_gt - vm_tab
	dd op_ge - vm_tab
	dd op_eq - vm_tab
	dd op_ne - vm_tab
	dd op_band - vm_tab
	dd op_bor - vm_tab
	dd op_bxor - vm_tab
	dd op_shl - vm_tab
	dd op_shr - vm_tab
	dd op_jmp - vm_tab
	dd op_jz - vm_tab
	dd op_jnz - vm_tab
	dd op_call - vm_tab
	dd op_enter - vm_tab
	dd op_ret - vm_tab
	dd op_builtin - vm_tab

kw_table:
	db 'int', 0, KW_INT
	db 'void', 0, KW_VOID
	db 'char', 0, KW_CHAR
	db 'if', 0, KW_IF
	db 'else', 0, KW_ELSE
	db 'while', 0, KW_WHILE
	db 'for', 0, KW_FOR
	db 'return', 0, KW_RETURN
	db 'break', 0, KW_BREAK
	db 'continue', 0, KW_CONTINUE
	db 0

bi_table:
	db 'printf', 0, 1
	db 'putchar', 0, 2
	db 'puts', 0, 3
	db 'getchar', 0, 4
	db 'exit', 0, 5
	db 0

op2_table:
	db '=', '=', '!', '=', '<', '=', '>', '=', '&', '&', '|', '|'
	db '+', '+', '-', '-', '+', '=', '-', '=', '*', '=', '/', '='
	db '%', '=', '<', '<', '>', '>'

cc_string	db 'CC', 0
c_string	db 'C', 0
s_main		db 'main', 0
cc_usage	db 'Usage: CC FILE.C   (compiles and runs a C program)', 13, 10, 0
cc_big_msg	db 'C source file is too large (max 64 KB)', 13, 10, 0
cc_err_pre	db 'CC: line ', 0
cc_err_mid	db ': ', 0
msg_undef	db 'CC: undefined function: ', 0
msg_argc	db 'wrong number of arguments to a function', 0
msg_noindex	db 'array used without an index', 0
msg_big		db 'program too large', 0
msg_str		db 'bad string literal (missing quote or too long)', 0
msg_toomany	db 'too many variables or functions', 0
msg_undef_var	db 'undefined variable', 0
msg_expr	db 'expected an expression', 0
msg_syntax	db 'syntax error', 0
msg_decl	db 'bad declaration', 0
msg_top		db 'expected a function or variable declaration', 0
msg_param	db 'bad parameter list', 0
msg_eof		db 'missing } at end of file', 0
msg_brk		db 'break outside a loop', 0
msg_cont	db 'continue outside a loop', 0
msg_const	db 'global initializer must be a number', 0
vm_err_pre	db 'RUNTIME ERROR: ', 0
vm_m_stack	db 'operand stack error', 0
vm_m_calls	db 'too many nested calls', 0
vm_m_locals	db 'too many local variables', 0
vm_m_index	db 'array index out of range', 0
vm_m_div	db 'division by zero', 0
vm_m_builtin	db 'unknown builtin', 0
vm_m_noargs	db 'builtin needs an argument', 0
vm_m_notstr	db 'expected a string literal', 0
vm_m_fewargs	db 'printf: not enough arguments', 0
vm_m_conv	db 'printf: unknown %-conversion (use %d %i %x %c %s %%)', 0

; compiler state
code_len	dq 0
strs_top	dq 0
lex_pos		dq 0
cur_line	dq 1
tok_type	dq 0
tok_val		dq 0
sym_count	dq 0
sym_globals	dq 0
g_count		dq 0
fn_count	dq 0
patch_count	dq 0
brk_count	dq 0
loop_depth	dq 0
cur_nslots	dq 0
cur_fn		dq 0
cc_rsp		dq 0
cc_tmp		dq 0
cc_fsize	dq 0
cc_name_ptr	dq 0

; virtual machine state
vm_rsp		dq 0
vm_pc		dq 0
vm_sp		dq 0
vm_fp		dq 0
vm_lsp		dq 0
vm_csp		dq 0
vm_exitcode	dq 0
bi_id		dq 0
bi_base		dq 0
bi_nargs	dq 0
bi_val		dq 0
pf_pos		dq 0
pf_k		dq 0
pf_w		dq 0
pf_v		dq 0
pf_str		dq 0
pf_conv		db 0

; ==================================================================
