; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2019 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition: GM University, Davanagere, 2026
;
; SCREEN HANDLING SYSTEM CALLS  (64-bit UEFI version)
;
; BIOS INT 10h is gone in 64-bit UEFI, so every routine here talks
; to the firmware text console (EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL).
; The register interface of every os_* routine is unchanged:
;   AL/AH/BL/DL/DH keep their meaning, while pointers (SI, DI, AX when
;   it is a string location...) are now full 64-bit registers.
;
; Colours: BIOS attribute bytes are still used by callers. UEFI only
; has 8 background colours, so bit 7 (bright/blink) is dropped.
; ==================================================================


; ------------------------------------------------------------------
; efi_thunk -- Call an EFI function with the Microsoft x64 ABI
; IN: RAX = function, RCX/RDX/R8/R9 = args 1-4, R10 = arg 5
; OUT: RAX = EFI_STATUS. Clobbers RAX, RCX, RDX, R8-R11 (as the ABI says)
; Keeps the stack 16-byte aligned and provides the shadow space no
; matter how deep the kernel's own stack is at this point.

efi_thunk:
	push rbp
	mov rbp, rsp
	sub rsp, 48
	and rsp, -16
	mov [rsp + 32], r10
	mov [rsp + 40], r11			; 6th argument (ignored by calls with fewer)
	call rax
	mov rsp, rbp
	pop rbp
	ret

; efi_thunk7 -- like efi_thunk for 7 arguments: R10 = arg5, R11 = arg6, [thunk_a7] = arg7
efi_thunk7:
	push rbp
	mov rbp, rsp
	sub rsp, 64
	and rsp, -16
	mov [rsp + 32], r10
	mov [rsp + 40], r11
	mov r10, [rel thunk_a7]
	mov [rsp + 48], r10
	call rax
	mov rsp, rbp
	pop rbp
	ret

thunk_a7	dq 0


; ------------------------------------------------------------------
; os_apply_attr -- (internal) make the console use the colour in cur_attr
; Clobbers RAX, RCX, RDX, R8-R11

os_apply_attr:
	movzx edx, byte [cur_attr]
	cmp dl, [hw_attr]
	je .same
	mov [hw_attr], dl
	and edx, 0x7F			; UEFI: foreground 0-15, background 0-7
	PCALL con_out, COUT_SETATTR
.same:
	ret


; ------------------------------------------------------------------
; os_print_string -- Displays text
; IN: SI = message location (zero-terminated string)
; OUT: Nothing (registers preserved)

os_print_string:
	pushall
	lea rdi, [rel strbuf]
	xor ecx, ecx
.repeat:
	lodsb				; Get character from string
	test al, al			; End of string?
	jz .flush_last
	movzx eax, al
	mov [rdi + rcx*2], ax		; ASCII -> UCS-2
	inc ecx
	cmp ecx, 200
	jb .repeat
	mov word [rdi + rcx*2], 0
	call .flush
	xor ecx, ecx
	jmp .repeat
.flush_last:
	test ecx, ecx
	jz .done
	mov word [rdi + rcx*2], 0
	call .flush
.done:
	popall
	ret
.flush:
	call os_apply_attr
	lea rdx, [rel strbuf]
	PCALL con_out, COUT_OUTSTR
	ret


; ------------------------------------------------------------------
; os_putc -- Print one character at the cursor (replaces INT 10h / AH=0Eh)
; IN: AL = character; OUT: Nothing (registers preserved)

os_putc:
	pushall
	movzx eax, al
	mov [wchar_buf], ax
	mov word [wchar_buf + 2], 0
	call os_apply_attr
	lea rdx, [rel wchar_buf]
	PCALL con_out, COUT_OUTSTR
	popall
	ret


; ------------------------------------------------------------------
; os_clear_screen -- Clears the screen to background
; IN/OUT: Nothing (registers preserved)

os_clear_screen:
	pushall
	mov byte [cur_attr], 0x07	; Grey on black
	call os_apply_attr
	PCALL con_out, COUT_CLEAR
	xor esi, esi				; some firmware only repaints cells it thinks changed:
.rows:					; paint every row explicitly
	mov eax, esi
	mov dh, al
	mov dl, 0
	call os_move_cursor
	mov bl, 0x07
	mov ecx, 80
	call os_fill_cells
	inc esi
	cmp esi, 25
	jb .rows
	xor edx, edx
	xor r8d, r8d
	PCALL con_out, COUT_SETCUR
	popall
	ret


; ------------------------------------------------------------------
; os_move_cursor -- Moves cursor in text mode
; IN: DH, DL = row, column; OUT: Nothing (registers preserved)

os_move_cursor:
	pushall
	mov r8d, edx
	shr r8d, 8
	and r8d, 0xFF			; R8 = row
	and edx, 0xFF			; RDX = column
	PCALL con_out, COUT_SETCUR
	popall
	ret


; ------------------------------------------------------------------
; os_get_cursor_pos -- Return position of text cursor
; OUT: DH, DL = row, column (other registers preserved)

os_get_cursor_pos:
	push rax
	push rcx
	mov rax, [con_out]
	mov rax, [rax + COUT_MODE]
	mov ecx, [rax + 12]		; CursorColumn
	mov eax, [rax + 16]		; CursorRow
	xor edx, edx
	mov dl, cl
	mov dh, al
	pop rcx
	pop rax
	ret


; ------------------------------------------------------------------
; os_print_horiz_line -- Draw a horizontal line on the screen
; IN: AX = line type (1 for double (=), otherwise single (-))
; OUT: Nothing (registers preserved)

os_print_horiz_line:
	pushall
	mov ecx, 0x2500			; UCS-2 box drawing: single line
	cmp eax, 1			; Was double-line specified in AX?
	jne .ready
	mov ecx, 0x2550			; If so, here's the code
.ready:
	lea rdi, [rel strbuf]
	xor eax, eax
.fill:
	mov [rdi + rax*2], cx
	inc eax
	cmp eax, 80			; Drawn 80 chars yet?
	jb .fill
	mov word [rdi + rax*2], 0
	call os_apply_attr
	lea rdx, [rel strbuf]
	PCALL con_out, COUT_OUTSTR
	popall
	ret


; ------------------------------------------------------------------
; os_show_cursor -- Turns on cursor in text mode
; IN/OUT: Nothing

os_show_cursor:
	pushall
	mov edx, 1
	PCALL con_out, COUT_ENCUR
	popall
	ret


; ------------------------------------------------------------------
; os_hide_cursor -- Turns off cursor in text mode
; IN/OUT: Nothing

os_hide_cursor:
	pushall
	xor edx, edx
	PCALL con_out, COUT_ENCUR
	popall
	ret


; ------------------------------------------------------------------
; os_fill_cells -- (internal) Paint RCX blank cells in colour BL at the
; cursor, like BIOS INT 10h AH=09h. The cursor is put back afterwards.
; The very last screen cell is never written (it would scroll the screen).

os_fill_cells:
	pushall
	mov rsi, rcx			; RSI = number of cells
	movzx ebx, bl			; RBX = attribute
	test rsi, rsi
	jz .out
	cmp rsi, 200
	jbe .counted
	mov esi, 200
.counted:
	call os_get_cursor_pos
	movzx edi, dl			; RDI = column
	movzx ebp, dh			; RBP = row
	cmp ebp, 24			; Bottom row? Stop before cell (79,24)
	jne .go
	lea eax, [rdi + rsi]
	cmp eax, 80
	jb .go
	mov esi, 79
	sub esi, edi
	jle .restore
.go:
	movzx eax, byte [cur_attr]
	push rax
	mov [cur_attr], bl
	call os_apply_attr
	lea rdx, [rel strbuf]
	xor ecx, ecx
.blank:
	mov word [rdx + rcx*2], 0x20
	inc ecx
	cmp ecx, esi
	jb .blank
	mov word [rdx + rcx*2], 0
	PCALL con_out, COUT_OUTSTR
	pop rax
	mov [cur_attr], al
	call os_apply_attr
.restore:
	mov edx, edi
	mov r8d, ebp
	PCALL con_out, COUT_SETCUR
.out:
	popall
	ret


; ------------------------------------------------------------------
; os_draw_block -- Render block of specified colour
; IN: BL/DL/DH/SI/DI = colour/start X pos/start Y pos/width/finish Y pos

os_draw_block:
	pushall
.more:
	call os_move_cursor		; Move to block starting position
	mov rcx, rsi
	call os_fill_cells		; Draw colour section
	inc dh				; Get ready for next line
	movzx eax, dh			; Get current Y position into AX
	cmp rax, rdi			; Reached finishing point (DI)?
	jne .more			; If not, keep drawing
	popall
	ret


; ------------------------------------------------------------------
; os_file_selector -- Show a file selection dialog
; IN: Nothing
; OUT: AX = location of filename string (or carry set if Esc pressed)

os_file_selector:
	pushall
	mov byte [.filename], 0		; Terminate string in case user leaves without choosing
	lea rax, [rel file_sel_buf]	; Get comma-separated list of filenames
	call os_get_file_list
	lea rax, [rel file_sel_buf]	; Show those filenames in a list dialog box
	lea rbx, [rel .help_msg1]
	lea rcx, [rel .help_msg2]
	call os_list_dialog
	jc .esc_pressed
	dec eax				; Result from os_list_box starts from 1, but
					; for our file list offset we want to start from 0
	mov ecx, eax
	xor ebx, ebx
	lea rsi, [rel file_sel_buf]	; Get our filename from the list
.loop1:
	cmp ebx, ecx
	je .got_our_filename
	lodsb
	test al, al
	jz .got_our_filename		; (safety: ran off the end of the list)
	cmp al, ','
	je .comma_found
	jmp .loop1
.comma_found:
	inc ebx
	jmp .loop1
.got_our_filename:			; Now copy the filename string
	lea rdi, [rel .filename]
.loop2:
	lodsb
	cmp al, ','
	je .finished_copying
	test al, al
	je .finished_copying
	stosb
	jmp .loop2
.finished_copying:
	mov byte [rdi], 0		; Zero terminate the filename string
	popall
	lea rax, [rel .filename]
	clc
	ret
.esc_pressed:				; Set carry flag if Escape was pressed
	popall
	stc
	ret

	.help_msg1	db 'Please select a file using the cursor', 0
	.help_msg2	db 'keys from the list below...', 0
	.filename	times 40 db 0


; ------------------------------------------------------------------
; os_list_dialog -- Show a dialog with a list of options
; IN: AX = comma-separated list of strings to show (zero-terminated),
;     BX = first help string, CX = second help string
; OUT: AX = number (starts from 1) of entry selected; carry set if Esc pressed

os_list_dialog:
	pushall
	mov r8b, [cur_attr]
	mov [.saved_attr], r8b
	push rax			; Store string list for now
	push rcx			; And help strings
	push rbx
	call os_hide_cursor
	xor ecx, ecx			; Count the number of entries in the list
	mov rsi, rax
.count_loop:
	lodsb
	test al, al
	jz .done_count
	cmp al, ','
	jne .count_loop
	inc cl
	jmp .count_loop
.done_count:
	inc cl
	mov [.num_of_entries], cl
	mov bl, 01001111b		; White on red
	mov dl, 20			; Start X position
	mov dh, 2			; Start Y position
	mov esi, 40			; Width
	mov edi, 23			; Finish Y position
	call os_draw_block		; Draw option selector window
	mov byte [cur_attr], 01001111b
	mov dl, 21			; Show first line of help text...
	mov dh, 3
	call os_move_cursor
	pop rsi				; Get back first string
	call os_print_string
	inc dh				; ...and the second
	call os_move_cursor
	pop rsi
	call os_print_string
	pop rsi				; SI = location of option list string (pushed earlier)
	mov [.list_string], rsi

	; Now that we've drawn the list, highlight the currently selected
	; entry and let the user move up and down using the cursor keys

	mov byte [.skip_num], 0		; Not skipping any lines at first showing
	mov dl, 25			; Set up starting position for selector
	mov dh, 7
	call os_move_cursor

.more_select:
	pushall
	mov bl, 11110000b		; Black on white for option list box
	mov dl, 21
	mov dh, 6
	mov esi, 38
	mov edi, 22
	call os_draw_block
	popall
	mov [.sel_row], dh
	call .draw_black_bar
	mov rsi, [.list_string]
	call .draw_list

.another_key:
	call os_wait_for_key		; Move / select option
	cmp ah, 48h			; Up pressed?
	je .go_up
	cmp ah, 50h			; Down pressed?
	je .go_down
	cmp al, 13			; Enter pressed?
	je .option_selected
	cmp al, 27			; Esc pressed?
	je .esc_pressed
	jmp .more_select		; If not, wait for another key

.go_up:
	cmp dh, 7			; Already at top?
	jle .hit_top
	call .draw_white_bar
	mov dl, 25
	call os_move_cursor
	dec dh				; Row to select (increasing down)
	jmp .more_select

.go_down:				; Already at bottom of list?
	cmp dh, 20
	je .hit_bottom
	movzx ecx, dh
	sub ecx, 7
	inc ecx
	movzx eax, byte [.skip_num]
	add ecx, eax
	movzx eax, byte [.num_of_entries]
	cmp ecx, eax
	je .another_key
	call .draw_white_bar
	mov dl, 25
	call os_move_cursor
	inc dh
	jmp .more_select

.hit_top:
	mov cl, [.skip_num]		; Any lines to scroll up?
	test cl, cl
	jz .another_key			; If not, wait for another key
	dec byte [.skip_num]		; If so, decrement lines to skip
	jmp .more_select

.hit_bottom:				; See if there's more to scroll
	movzx ecx, dh
	sub ecx, 7
	inc ecx
	movzx eax, byte [.skip_num]
	add ecx, eax
	movzx eax, byte [.num_of_entries]
	cmp ecx, eax
	je .another_key
	inc byte [.skip_num]		; If so, increment lines to skip
	jmp .more_select

.option_selected:
	call os_show_cursor
	sub dh, 7
	movzx eax, dh
	inc eax				; Options start from 1
	movzx ecx, byte [.skip_num]
	add eax, ecx			; Add any lines skipped from scrolling
	mov [.tmp], rax			; Store option number before restoring all other regs
	mov al, [.saved_attr]
	mov [cur_attr], al
	popall
	mov rax, [.tmp]
	clc				; Clear carry as Esc wasn't pressed
	ret

.esc_pressed:
	call os_show_cursor
	mov al, [.saved_attr]
	mov [cur_attr], al
	popall
	stc				; Set carry for Esc
	ret


.draw_list:
	pushall
	mov dl, 23			; Get into position for option list text
	mov dh, 7
	call os_move_cursor
	movzx ecx, byte [.skip_num]	; Skip lines scrolled off the top of the dialog
.skip_loop:
	test ecx, ecx
	jz .skip_loop_finished
.more_lodsb:
	lodsb
	cmp al, ','
	jne .more_lodsb
	dec ecx
	jmp .skip_loop
.skip_loop_finished:
	xor ebx, ebx			; Counter for total number of options
	call .set_row_attr
.more:
	lodsb				; Get next character in file name, increment pointer
	test al, al			; End of string?
	jz .done_list
	cmp al, ','			; Next option? (String is comma-separated)
	je .newline
	call os_putc
	jmp .more
.newline:
	mov dl, 23			; Go back to starting X position
	inc dh				; But jump down a line
	call os_move_cursor
	call .set_row_attr
	inc ebx				; Update the number-of-options counter
	cmp ebx, 14			; Limit to one screen of options
	jl .more
.done_list:
	popall
	call os_move_cursor
	ret

.set_row_attr:				; Selected row = white on black, others black on white
	mov byte [cur_attr], 11110000b
	cmp dh, [.sel_row]
	jne .sra_done
	mov byte [cur_attr], 00001111b
.sra_done:
	ret

.draw_black_bar:
	pushall
	mov dl, 22
	call os_move_cursor
	mov bl, 00001111b		; White text on black background
	mov ecx, 36
	call os_fill_cells
	popall
	ret

.draw_white_bar:
	pushall
	mov dl, 22
	call os_move_cursor
	mov bl, 11110000b		; Black text on white background
	mov ecx, 36
	call os_fill_cells
	popall
	ret

	.tmp			dq 0
	.num_of_entries		db 0
	.skip_num		db 0
	.sel_row		db 0
	.saved_attr		db 0
	.list_string		dq 0


; ------------------------------------------------------------------
; os_draw_background -- Clear screen with white top and bottom bars
; containing text, and a coloured middle section.
; IN: AX/BX = top/bottom string locations, CX = colour

os_draw_background:
	pushall
	push rax			; Store params to pop out later
	push rbx
	push rcx
	mov byte [cur_attr], 0x07
	call os_apply_attr
	PCALL con_out, COUT_CLEAR	; Start from a clean screen
	mov dl, 0
	mov dh, 0
	call os_move_cursor
	mov bl, 01110000b		; Draw white bar at top
	mov ecx, 80
	call os_fill_cells
	mov dh, 1
	mov dl, 0
	pop rbx				; Get colour param (originally in CX)
	mov [.colour], bl
.rows:
	call os_move_cursor		; Draw colour section, row by row
	mov bl, [.colour]
	mov ecx, 80
	call os_fill_cells
	inc dh
	cmp dh, 24
	jne .rows
	mov dh, 24
	mov dl, 0
	call os_move_cursor
	mov bl, 01110000b		; Draw white bar at bottom
	mov ecx, 80
	call os_fill_cells
	mov byte [cur_attr], 01110000b	; Text on the bars: black on white
	mov dh, 24
	mov dl, 1
	call os_move_cursor
	pop rbx				; Get bottom string param
	mov rsi, rbx
	call os_print_string
	mov dh, 0
	mov dl, 1
	call os_move_cursor
	pop rax				; Get top string param
	mov rsi, rax
	call os_print_string
	mov al, [.colour]		; Application text uses the colour section
	mov [cur_attr], al
	mov dh, 1			; Ready for app text
	mov dl, 0
	call os_move_cursor
	popall
	ret

	.colour		db 0


; ------------------------------------------------------------------
; os_print_newline -- Reset cursor to start of next line
; IN/OUT: Nothing (registers preserved)

os_print_newline:
	push rsi
	lea rsi, [rel .crlf]
	call os_print_string
	pop rsi
	ret

	.crlf	db 13, 10, 0


; ------------------------------------------------------------------
; os_input_dialog -- Get text string from user via a dialog box
; IN: AX = string location, BX = message to show; OUT: AX = string location

os_input_dialog:
	pushall
	push rax			; Save string location
	push rbx			; Save message to show
	movzx eax, byte [cur_attr]
	mov [.saved_attr], al
	mov dh, 10			; First, draw red background box
	mov dl, 12
.redbox:				; Loop to draw all lines of box
	call os_move_cursor
	mov bl, 01001111b		; White on red
	mov ecx, 55
	call os_fill_cells
	inc dh
	cmp dh, 16
	jne .redbox
	mov byte [cur_attr], 01001111b
	mov dl, 14
	mov dh, 11
	call os_move_cursor
	pop rbx				; Get message back and display it
	mov rsi, rbx
	call os_print_string
	mov dl, 14
	mov dh, 13
	call os_move_cursor
	pop rax				; Get input string back
	mov ebx, 50
	call os_input_string
	mov al, [.saved_attr]
	mov [cur_attr], al
	popall
	ret

	.saved_attr	db 0


; ------------------------------------------------------------------
; os_dialog_box -- Print dialog box in middle of screen, with button(s)
; IN: AX, BX, CX = string locations (set registers to 0 for no display)
; IN: DX = 0 for single 'OK' dialog, 1 for two-button 'OK' and 'Cancel'
; OUT: If two-button mode, AX = 0 for OK and 1 for cancel
; NOTE: Each string is limited to 40 characters

os_dialog_box:
	pushall
	mov [.tmp], rdx
	mov [.s1], rax
	mov [.s2], rbx
	mov [.s3], rcx
	mov r8b, [cur_attr]
	mov [.saved_attr], r8b
	call os_hide_cursor
	mov dh, 9			; First, draw red background box
	mov dl, 19
.redbox:				; Loop to draw all lines of box
	call os_move_cursor
	mov bl, 01001111b		; White on red
	mov ecx, 42
	call os_fill_cells
	inc dh
	cmp dh, 16
	jne .redbox
	mov byte [cur_attr], 01001111b
	mov rsi, [.s1]
	test rsi, rsi			; Skip string params if zero
	jz .no_first_string
	mov dl, 20
	mov dh, 10
	call os_move_cursor
	call os_print_string		; First string
.no_first_string:
	mov rsi, [.s2]
	test rsi, rsi
	jz .no_second_string
	mov dl, 20
	mov dh, 11
	call os_move_cursor
	call os_print_string		; Second string
.no_second_string:
	mov rsi, [.s3]
	test rsi, rsi
	jz .no_third_string
	mov dl, 20
	mov dh, 12
	call os_move_cursor
	call os_print_string		; Third string
.no_third_string:
	cmp qword [.tmp], 0
	jne .two_button

.one_button:
	mov bl, 11110000b		; Black on white
	mov dh, 14
	mov dl, 35
	mov esi, 8
	mov edi, 15
	call os_draw_block
	mov byte [cur_attr], 11110000b
	mov dl, 38			; OK button, centred at bottom of box
	mov dh, 14
	call os_move_cursor
	lea rsi, [rel .ok_button_string]
	call os_print_string
.one_button_wait:
	call os_wait_for_key
	cmp al, 13			; Wait for enter key (13) to be pressed
	jne .one_button_wait
	call os_show_cursor
	mov al, [.saved_attr]
	mov [cur_attr], al
	popall
	ret

.two_button:
	mov byte [.sel], 0		; Default button = OK
.two_draw:
	mov bl, 11110000b		; OK button: selected = black on white
	cmp byte [.sel], 0
	je .ok_colour
	mov bl, 01001111b		; not selected = white on red
.ok_colour:
	mov dh, 14
	mov dl, 27
	mov esi, 8
	mov edi, 15
	call os_draw_block
	mov [cur_attr], bl
	mov dl, 30			; OK button
	mov dh, 14
	call os_move_cursor
	lea rsi, [rel .ok_button_string]
	call os_print_string
	mov bl, 11110000b		; Cancel button
	cmp byte [.sel], 1
	je .cancel_colour
	mov bl, 01001111b
.cancel_colour:
	mov dh, 14
	mov dl, 43
	mov esi, 8
	mov edi, 15
	call os_draw_block
	mov [cur_attr], bl
	mov dl, 44			; Cancel button
	mov dh, 14
	call os_move_cursor
	lea rsi, [rel .cancel_button_string]
	call os_print_string
.two_button_wait:
	call os_wait_for_key
	cmp ah, 75			; Left cursor key pressed?
	jne .noleft
	mov byte [.sel], 0
	jmp .two_draw
.noleft:
	cmp ah, 77			; Right cursor key pressed?
	jne .noright
	mov byte [.sel], 1
	jmp .two_draw
.noright:
	cmp al, 13			; Wait for enter key (13) to be pressed
	jne .two_button_wait
	call os_show_cursor
	movzx eax, byte [.sel]
	mov [.tmp], rax
	mov al, [.saved_attr]
	mov [cur_attr], al
	popall
	mov rax, [.tmp]			; Return result in AX
	ret

	.ok_button_string	db 'OK', 0
	.cancel_button_string	db 'Cancel', 0
	.tmp			dq 0
	.s1			dq 0
	.s2			dq 0
	.s3			dq 0
	.sel			db 0
	.saved_attr		db 0


; ------------------------------------------------------------------
; os_print_space -- Print a space to the screen
; IN/OUT: Nothing

os_print_space:
	push rax
	mov al, ' '
	call os_putc
	pop rax
	ret


; ------------------------------------------------------------------
; os_print_digit -- Displays contents of AX as a single digit
; Works up to base 37, ie digits 0-Z
; IN: AX = "digit" to format and print

os_print_digit:
	push rax
	cmp al, 9			; There is a break in ASCII table between 9 and A
	jle .digit_format
	add al, 'A'-'9'-1		; Correct for the skipped punctuation
.digit_format:
	add al, '0'			; 0 will display as '0', etc.
	call os_putc
	pop rax
	ret


; ------------------------------------------------------------------
; os_print_1hex -- Displays low nibble of AL in hex format
; IN: AL = number to format and print

os_print_1hex:
	push rax
	and al, 0Fh			; Mask off data to display
	call os_print_digit
	pop rax
	ret


; ------------------------------------------------------------------
; os_print_2hex -- Displays AL in hex format
; IN: AL = number to format and print

os_print_2hex:
	push rax
	shr al, 4			; Output high nibble
	call os_print_1hex
	pop rax
	push rax
	call os_print_1hex		; Output low nibble
	pop rax
	ret


; ------------------------------------------------------------------
; os_print_4hex -- Displays AX in hex format
; IN: AX = number to format and print

os_print_4hex:
	push rax
	mov al, ah			; Output high byte
	call os_print_2hex
	pop rax
	push rax
	call os_print_2hex		; Output low byte
	pop rax
	ret


; ------------------------------------------------------------------
; os_input_string -- Get a string from keyboard input
; IN: AX = address to store the string; BX = max size (incl. terminator)
; OUT: Nothing (the string is stored at AX)

os_input_string:
	pushall

	; If the character count is zero, don't do anything.
	test ebx, ebx
	je .done

	mov rdi, rax			; DI = Current position in buffer
	mov [.start], rax
	dec ebx				; BX = Maximum characters in string
	mov [.max], ebx
	mov ecx, ebx			; CX = Remaining character count
	mov eax, [hist_count]		; History browsing starts at 'new line'
	mov [hist_pos], eax

.get_char:
	call os_wait_for_key

	cmp byte [hist_enable], 0	; Command history (used by the CLI)
	je .no_hist
	cmp ah, 48h			; Up arrow: older command
	je .hist_up
	cmp ah, 50h			; Down arrow: newer command
	je .hist_down
.no_hist:

	cmp al, 8
	je .backspace

	cmp al, 13			; The ENTER key ends the prompt
	je .end_string

	; Do not add any characters if the maximum size has been reached.
	test ecx, ecx
	jz .get_char

	; Only add printable characters (ASCII Values 32-126)
	cmp al, ' '
	jb .get_char
	cmp al, 126
	ja .get_char

	call .add_char
	dec ecx
	jmp .get_char

.end_string:
	mov al, 0
	stosb

.done:
	popall
	ret

.backspace:
	; Check if there are any characters to backspace
	cmp ecx, ebx
	jae .get_char

	inc ecx				; Increase characters remaining
	call .reverse_cursor		; Move back to the previous character
	mov al, ' '			; Print a space on the character
	call .add_char
	call .reverse_cursor		; Now move the cursor back again
	jmp .get_char

.reverse_cursor:
	dec rdi				; Move the output pointer backwards
	call os_get_cursor_pos
	cmp dl, 0			; Is the cursor at the start of line?
	je .back_line
	dec dl				; If not, just decrease the column
	call os_move_cursor
	ret

.back_line:
	dec dh				; Otherwise, move the cursor to the end
	mov dl, 79			; of the previous line.
	call os_move_cursor
	ret

.add_char:
	stosb
	call os_putc
	ret

.hist_up:
	mov eax, [hist_pos]
	test eax, eax
	jz .get_char
	dec eax
	jmp .hist_load
.hist_down:
	mov eax, [hist_pos]
	cmp eax, [hist_count]
	jae .get_char
	inc eax
.hist_load:
	mov [hist_pos], eax
	mov r8, rdi			; Erase the text typed so far
	sub r8, [.start]
	jz .erased
	call os_get_cursor_pos
	cmp dl, r8b
	jae .col_ok
	mov r8b, dl			; (never move before column 0)
.col_ok:
	sub dl, r8b
	call os_move_cursor
	mov r9, r8
.blank:
	mov al, ' '
	call os_putc
	dec r9
	jnz .blank
	call os_get_cursor_pos
	sub dl, r8b
	call os_move_cursor
.erased:
	mov rdi, [.start]
	mov ecx, [.max]
	mov eax, [hist_pos]
	cmp eax, [hist_count]
	jae .get_char			; Past the newest entry = empty line
	shl eax, 6
	lea rsi, [rel hist_buf]
	add rsi, rax
.recall:
	lodsb
	test al, al
	jz .get_char
	test ecx, ecx
	jz .get_char
	call .add_char
	dec ecx
	jmp .recall

	.start	dq 0
	.max	dd 0


; ==================================================================
