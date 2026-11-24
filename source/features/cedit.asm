; ==================================================================
; GMU OS 64 -- full-screen C editor  (commands: C, CC with no file)
;
;   Type C code.   Enter = compile and run the program
;                  Shift+Enter = new line (with auto-indent)
;   Esc = leave the editor (the text is kept for the next time)
;   F2 = save to a file     F3 = new (clear everything)
;   Arrows, Home, End, PgUp, PgDn, Backspace, Delete work as usual.
;   Without the extended keyboard protocol Tab is the new-line key.
;
; The program text lives in c_src (NUL terminated, lines end with LF).
; ==================================================================

ED_MAX		equ 60000

; ------------------------------------------------------------------
; c_command -- "C" or "C FILE.C": open the editor (optionally with a file)

c_command:
	cmp qword [param_list], 0
	je c_editor
	mov rsi, [param_list]
	call os_string_parse
	mov [cc_name_ptr], rax
	call os_get_file_size
	jc .nf
	cmp rbx, ED_MAX
	ja .big
	mov [cc_fsize], rbx
	mov rax, [cc_name_ptr]
	lea rcx, [rel c_src]
	call os_load_file
	jc .nf
	lea rsi, [rel c_src]
	mov rdi, [cc_fsize]
	mov byte [rsi + rdi], 0
	; drop CR characters of Windows line endings
	mov rdx, rsi				; write pointer
.cr:
	mov al, [rsi]
	test al, al
	jz .crdone
	inc rsi
	cmp al, 13
	je .cr
	mov [rdx], al
	inc rdx
	jmp .cr
.crdone:
	mov byte [rdx], 0
	jmp c_editor
.nf:
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd
.big:
	lea rsi, [rel cc_big_msg]
	call os_print_string
	jmp get_cmd

; ------------------------------------------------------------------
c_editor:
	lea rax, [rel c_src]
	call os_string_length
	mov [ed_len], rax
	mov [ed_pos], rax
	mov qword [ed_top], 0
	mov qword [ed_msg], 0
	call os_clear_screen
	call os_show_cursor
	call ed_redraw

.key:
	call os_wait_for_key_ex
	mov qword [ed_msg], 0
	cmp al, 13
	je .enter
	cmp al, 27
	je .esc
	cmp al, 8
	je .backspace
	cmp al, 9
	je .tab
	cmp al, ' '
	jb .special
	cmp al, 126
	ja .special
	cmp al, '}'
	jne .plain
	call ed_dedent				; a '}' on an indented line steps back 4 spaces
	mov al, '}'
.plain:
	call ed_insert
	jmp .redraw

.special:
	cmp ah, 4Bh
	je .left
	cmp ah, 4Dh
	je .right
	cmp ah, 48h
	je .up
	cmp ah, 50h
	je .down
	cmp ah, 47h
	je .home
	cmp ah, 4Fh
	je .end
	cmp ah, 53h
	je .delete
	cmp ah, 49h
	je .pgup
	cmp ah, 51h
	je .pgdn
	cmp ah, 3Ch
	je .save
	cmp ah, 3Dh
	je .new
	jmp .key

.redraw:
	call ed_redraw
	jmp .key

.enter:
	cmp byte [key_shift], 0
	jne .newline
	jmp .run

.tab:
	cmp qword [con_in_ex], 0		; no Shift information: Tab = new line
	je .newline
	mov ecx, 4				; otherwise 4 spaces
.tabl:
	push rcx
	mov al, ' '
	call ed_insert
	pop rcx
	dec ecx
	jnz .tabl
	jmp .redraw

.newline:
	call ed_newline
	jmp .redraw

.backspace:
	cmp qword [ed_pos], 0
	je .key
	dec qword [ed_pos]
	call ed_delete
	jmp .redraw

.delete:
	mov rax, [ed_pos]
	cmp rax, [ed_len]
	jae .key
	call ed_delete
	jmp .redraw

.left:
	cmp qword [ed_pos], 0
	je .key
	dec qword [ed_pos]
	jmp .redraw
.right:
	mov rax, [ed_pos]
	cmp rax, [ed_len]
	jae .key
	inc qword [ed_pos]
	jmp .redraw
.up:
	call ed_up
	jmp .redraw
.down:
	call ed_down
	jmp .redraw
.pgup:
	mov ecx, 20
.pu:
	push rcx
	call ed_up
	pop rcx
	dec ecx
	jnz .pu
	jmp .redraw
.pgdn:
	mov ecx, 20
.pd:
	push rcx
	call ed_down
	pop rcx
	dec ecx
	jnz .pd
	jmp .redraw
.home:
	call ed_locate
	mov rax, [ed_col]
	sub [ed_pos], rax
	jmp .redraw
.end:
	call ed_locate
	mov rax, [ed_pos]
	sub rax, [ed_col]			; start of line
	call ed_line_len
	add rax, rcx
	mov [ed_pos], rax
	jmp .redraw

.esc:
	call os_clear_screen
	jmp get_cmd

; ---- run the program
.run:
	call os_clear_screen
	lea rbx, [rel c_src]
	mov rdi, [ed_len]
	mov byte [rbx + rdi], 0
	call cc_compile
	jc .after
	call vm_run
.after:
	lea rsi, [rel ed_after_msg]
	call os_print_string
	call os_wait_for_key
	call os_clear_screen
	call ed_redraw
	jmp .key

; ---- F2: save
.save:
	mov byte [cur_attr], 0x70
	mov dh, 24
	mov dl, 0
	call os_move_cursor
	lea rsi, [rel ed_save_prompt]
	call os_print_string
	mov ecx, 78
	call ed_pad_to
	mov dh, 24
	mov dl, 9
	call os_move_cursor
	mov byte [ed_name], 0
	lea rax, [rel ed_name]
	mov ebx, 40
	call os_input_string
	mov byte [cur_attr], 0x07
	cmp byte [ed_name], 0
	je .redraw
	lea rax, [rel ed_name]
	lea rbx, [rel c_src]
	mov rcx, [ed_len]
	call os_write_file
	jc .save_fail
	lea rax, [rel ed_saved_msg]
	lea rbx, [rel ed_name]
	lea rcx, [rel ed_msgbuf]
	call os_string_join
	lea rax, [rel ed_msgbuf]
	mov [ed_msg], rax
	jmp .redraw
.save_fail:
	lea rax, [rel ed_savefail_msg]
	mov [ed_msg], rax
	jmp .redraw

; ---- F3: new program
.new:
	mov byte [cur_attr], 0x70
	mov dh, 24
	mov dl, 0
	call os_move_cursor
	lea rsi, [rel ed_clear_prompt]
	call os_print_string
	mov ecx, 78
	call ed_pad_to
	mov byte [cur_attr], 0x07
	call os_wait_for_key
	or al, 20h
	cmp al, 'y'
	jne .redraw
	mov qword [ed_len], 0
	mov qword [ed_pos], 0
	mov qword [ed_top], 0
	mov byte [c_src], 0
	call os_clear_screen
	jmp .redraw

; ------------------------------------------------------------------
; buffer operations

; ed_insert -- AL = character inserted at the cursor (ignored if the buffer is full)
ed_insert:
	push rbx
	push rcx
	push rdx
	push rsi
	mov rcx, [ed_len]
	cmp rcx, ED_MAX
	jae .out
	lea rsi, [rel c_src]
	mov rdx, [ed_pos]
	lea rbx, [rcx + 1]			; move the text (and its NUL) up by one
.sh:
	cmp rbx, rdx
	jbe .put
	mov cl, [rsi + rbx - 1]
	mov [rsi + rbx], cl
	dec rbx
	jmp .sh
.put:
	mov [rsi + rdx], al
	inc qword [ed_len]
	inc qword [ed_pos]
.out:
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	ret

; ed_dedent -- if only spaces precede the cursor on this line, delete up to 4 of them
ed_dedent:
	push rax
	push rcx
	push rsi
	call ed_locate
	mov rcx, [ed_col]
	test rcx, rcx
	jz .out
	lea rsi, [rel c_src]
	mov rax, [ed_pos]
	sub rax, rcx				; start of line
.chk:
	cmp rax, [ed_pos]
	jae .ok
	cmp byte [rsi + rax], ' '
	jne .out
	inc rax
	jmp .chk
.ok:
	mov ecx, 4
.del:
	cmp qword [ed_col], 0
	je .out
	dec qword [ed_pos]
	call ed_delete
	dec qword [ed_col]
	dec ecx
	jnz .del
.out:
	pop rsi
	pop rcx
	pop rax
	ret

; ed_delete -- remove the character at the cursor position
ed_delete:
	push rax
	push rcx
	push rsi
	lea rsi, [rel c_src]
	mov rcx, [ed_pos]
.sh:
	cmp rcx, [ed_len]
	jae .done
	mov al, [rsi + rcx + 1]
	mov [rsi + rcx], al
	inc rcx
	jmp .sh
.done:
	dec qword [ed_len]
	mov rcx, [ed_len]
	mov byte [rsi + rcx], 0
	pop rsi
	pop rcx
	pop rax
	ret

; ed_newline -- LF plus the indentation of the current line (+4 after '{')
ed_newline:
	call ed_locate
	mov rax, [ed_pos]
	sub rax, [ed_col]			; start of the current line
	lea rsi, [rel c_src]
	xor ecx, ecx				; indentation
.ind:
	cmp rax, [ed_pos]
	jae .indone
	cmp byte [rsi + rax], ' '
	jne .indone
	inc ecx
	inc rax
	jmp .ind
.indone:
	mov [ed_indent], rcx
	mov rax, [ed_pos]
	test rax, rax
	jz .lf
	cmp byte [rsi + rax - 1], '{'
	jne .lf
	add qword [ed_indent], 4
.lf:
	mov al, 10
	call ed_insert
	mov rcx, [ed_indent]
.sp:
	test rcx, rcx
	jz .done
	push rcx
	mov al, ' '
	call ed_insert
	pop rcx
	dec rcx
	jmp .sp
.done:
	ret

; ed_locate -- ed_line / ed_col of the cursor
ed_locate:
	lea rsi, [rel c_src]
	xor ecx, ecx				; line
	xor edx, edx				; start offset of the line
	xor eax, eax
.l:
	cmp rax, [ed_pos]
	jae .done
	cmp byte [rsi + rax], 10
	jne .n
	inc rcx
	lea rdx, [rax + 1]
.n:
	inc rax
	jmp .l
.done:
	mov [ed_line], rcx
	mov rax, [ed_pos]
	sub rax, rdx
	mov [ed_col], rax
	ret

; ed_line_offset -- RDX = line number -> RAX = offset of its first character
ed_line_offset:
	lea rsi, [rel c_src]
	xor eax, eax
.l:
	test rdx, rdx
	jz .done
.s:
	cmp rax, [ed_len]
	jae .done
	cmp byte [rsi + rax], 10
	je .nl
	inc rax
	jmp .s
.nl:
	inc rax
	dec rdx
	jmp .l
.done:
	ret

; ed_line_len -- RAX = offset of a line start -> RCX = its length
ed_line_len:
	lea rsi, [rel c_src]
	xor ecx, ecx
.l:
	lea rdx, [rax + rcx]
	cmp rdx, [ed_len]
	jae .done
	cmp byte [rsi + rdx], 10
	je .done
	inc rcx
	jmp .l
.done:
	ret

ed_up:
	call ed_locate
	mov rdx, [ed_line]
	test rdx, rdx
	jz .out
	dec rdx
	call ed_line_offset			; RAX = start of the previous line
	push rax
	call ed_line_len
	pop rax
	mov rdx, [ed_col]
	cmp rdx, rcx
	jbe .c
	mov rdx, rcx
.c:
	add rax, rdx
	mov [ed_pos], rax
.out:
	ret

ed_down:
	call ed_locate
	mov rax, [ed_pos]
	sub rax, [ed_col]			; start of this line
	call ed_line_len
	add rax, rcx				; offset of the end of this line
	cmp rax, [ed_len]
	jae .out				; last line: nothing below
	inc rax					; start of the next line
	push rax
	call ed_line_len
	pop rax
	mov rdx, [ed_col]
	cmp rdx, rcx
	jbe .c
	mov rdx, rcx
.c:
	add rax, rdx
	mov [ed_pos], rax
.out:
	ret

; ------------------------------------------------------------------
; screen

; ed_pad_to -- print spaces until the cursor is in column ECX
ed_pad_to:
	call os_get_cursor_pos
.l:
	movzx eax, dl
	cmp eax, ecx
	jae .d
	mov al, ' '
	call os_putc
	inc dl
	jmp .l
.d:
	ret

ed_redraw:
	pushall
	call ed_locate
	mov rax, [ed_line]			; keep the cursor line on screen
	cmp rax, [ed_top]
	jae .a
	mov [ed_top], rax
.a:
	mov rcx, [ed_top]
	add rcx, 22
	cmp rax, rcx
	jbe .b
	sub rax, 22
	mov [ed_top], rax
.b:
	call os_hide_cursor
	mov byte [cur_attr], 0x70		; title bar
	mov dh, 0
	mov dl, 0
	call os_move_cursor
	lea rsi, [rel ed_title]
	call os_print_string
	mov ecx, 79
	call ed_pad_to
	mov byte [cur_attr], 0x07

	mov rdx, [ed_top]			; first visible line
	call ed_line_offset
	lea r10, [rel c_src]
	add r10, rax				; R10 = source pointer
	xor r9d, r9d				; 1 once the end of the text is reached
	mov r8d, 1				; screen row
.row:
	cmp r8d, 23
	ja .rows_done
	lea rdi, [rel ed_lbuf]
	xor ecx, ecx
	test r9d, r9d
	jnz .pad
.cp:
	mov al, [r10]
	test al, al
	jz .eof
	cmp al, 10
	je .eol
	inc r10
	cmp ecx, 79
	jae .cp
	mov [rdi + rcx], al
	inc ecx
	jmp .cp
.eol:
	inc r10
	jmp .pad
.eof:
	mov r9d, 1
.pad:
	cmp ecx, 79
	jae .out
	mov byte [rdi + rcx], ' '
	inc ecx
	jmp .pad
.out:
	mov byte [rdi + 79], 0
	mov eax, r8d
	mov dh, al
	mov dl, 0
	call os_move_cursor
	lea rsi, [rel ed_lbuf]
	call os_print_string			; (preserves R8-R10)
	inc r8d
	jmp .row
.rows_done:
	; status bar
	mov byte [cur_attr], 0x70
	mov dh, 24
	mov dl, 0
	call os_move_cursor
	cmp qword [ed_msg], 0
	je .hints
	mov rsi, [ed_msg]
	call os_print_string
	jmp .spad
.hints:
	lea rsi, [rel st_ln]
	call os_print_string
	mov rax, [ed_line]
	inc rax
	call os_int_to_string
	mov rsi, rax
	call os_print_string
	lea rsi, [rel st_col]
	call os_print_string
	mov rax, [ed_col]
	inc rax
	call os_int_to_string
	mov rsi, rax
	call os_print_string
	lea rsi, [rel st_hint]
	cmp qword [con_in_ex], 0
	jne .ph
	lea rsi, [rel st_hint_noex]
.ph:
	call os_print_string
.spad:
	mov ecx, 78
	call ed_pad_to
	mov byte [cur_attr], 0x07
	mov rax, [ed_line]
	sub rax, [ed_top]
	inc eax
	mov dh, al
	mov rax, [ed_col]
	cmp rax, 78
	jbe .col
	mov eax, 78
.col:
	mov dl, al
	call os_move_cursor
	call os_show_cursor
	popall
	ret

; ------------------------------------------------------------------
; data

ed_len		dq 0
ed_pos		dq 0
ed_top		dq 0
ed_line		dq 0
ed_col		dq 0
ed_indent	dq 0
ed_msg		dq 0
ed_name		times 48 db 0
ed_msgbuf	times 96 db 0
ed_lbuf		times 96 db 0
ed_title	db ' GMU OS C Editor   Enter = run   Shift+Enter = new line   Esc = exit', 0
st_ln		db ' Ln ', 0
st_col		db ', Col ', 0
st_hint		db '   Enter:run  Shift+Enter:new line  F2:save  F3:new  Esc:exit', 0
st_hint_noex	db '   Enter:run  Tab:new line  F2:save  F3:new  Esc:exit', 0
ed_after_msg	db 13, 10, '--- press a key to return to the editor ---', 0
ed_save_prompt	db ' Save as: ', 0
ed_saved_msg	db ' Saved as ', 0
ed_savefail_msg	db ' Could not save the file (write protected or bad name)', 0
ed_clear_prompt	db ' Clear all text? Press Y to confirm, any other key to cancel', 0

; ==================================================================
