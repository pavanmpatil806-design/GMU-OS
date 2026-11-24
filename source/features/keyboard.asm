; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2019 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition: GM University, Davanagere, 2026
;
; KEYBOARD HANDLING ROUTINES  (64-bit UEFI version)
;
; INT 16h is replaced by EFI_SIMPLE_TEXT_INPUT_PROTOCOL.  Keys are
; translated back to the BIOS convention so callers don't change:
;   AL = ASCII code, AH = BIOS scan code for cursor/function keys
;   (Up 48h, Down 50h, Left 4Bh, Right 4Dh, Home 47h, End 4Fh, ...)
; ==================================================================


; ------------------------------------------------------------------
; os_wait_for_key -- Waits for keypress and returns key
; IN: Nothing; OUT: AX = key pressed, other regs preserved

os_wait_for_key:
	push rcx
	push rdx
	push r8
	push r9
	push r10
	push r11
.retry:
	lea rdx, [rel key_buf]
	PCALL con_in, CIN_READKEY
	test rax, rax			; EFI_SUCCESS?
	jz .got_key
	mov rax, [con_in]		; Nothing pressed yet: sleep until a key arrives
	lea rdx, [rax + CIN_WAITKEY]
	lea r8, [rel evt_index]
	mov ecx, 1
	BCALL BS_WAITFOREVENT
	jmp .retry
.got_key:
	call key_convert
	jc .retry			; Ignore keys we can't map
	pop r11
	pop r10
	pop r9
	pop r8
	pop rdx
	pop rcx
	ret


; ------------------------------------------------------------------
; os_check_for_key -- Scans keyboard for input, but doesn't wait
; IN: Nothing; OUT: AX = 0 if no key pressed, otherwise the key (see above)

os_check_for_key:
	push rcx
	push rdx
	push r8
	push r9
	push r10
	push r11
	lea rdx, [rel key_buf]
	PCALL con_in, CIN_READKEY
	test rax, rax
	jnz .nokey
	call key_convert
	jnc .done
.nokey:
	xor eax, eax			; Zero result if no key pressed
.done:
	pop r11
	pop r10
	pop r9
	pop r8
	pop rdx
	pop rcx
	ret


; ------------------------------------------------------------------
; os_wait_for_key_ex -- like os_wait_for_key, but also sets key_shift to 1
; when a Shift or Ctrl key is held (needs EFI_SIMPLE_TEXT_INPUT_EX_PROTOCOL;
; without it key_shift is always 0)

os_wait_for_key_ex:
	cmp qword [con_in_ex], 0
	jne .ex
	mov byte [key_shift], 0
	jmp os_wait_for_key
.ex:
	push rcx
	push rdx
	push r8
	push r9
	push r10
	push r11
.retry:
	lea rdx, [rel key_data]
	PCALL con_in_ex, 8			; ReadKeyStrokeEx
	test rax, rax
	jz .got
	mov rax, [con_in_ex]			; nothing yet: sleep until a key arrives
	lea rdx, [rax + 16]			; WaitForKeyEx event
	lea r8, [rel evt_index]
	mov ecx, 1
	BCALL BS_WAITFOREVENT
	jmp .retry
.got:
	mov eax, [key_data]			; EFI_INPUT_KEY (same layout as key_buf)
	mov [key_buf], eax
	mov eax, [key_data + 4]			; KeyShiftState
	xor ecx, ecx
	test eax, 80000000h			; state valid?
	jz .set
	test eax, 0Fh				; left/right shift or ctrl
	jz .set
	mov ecx, 1
.set:
	mov [key_shift], cl
	call key_convert
	jc .retry
	pop r11
	pop r10
	pop r9
	pop r8
	pop rdx
	pop rcx
	ret


; ------------------------------------------------------------------
; key_convert -- (internal) EFI_INPUT_KEY in key_buf -> BIOS style AX
; OUT: AX = key, carry set if the key has no BIOS equivalent

key_convert:
	movzx eax, word [key_buf + 2]	; UnicodeChar
	test eax, eax
	jz .scancode
	cmp eax, 0Ah			; Some terminals send LF for Enter
	jne .not_lf
	mov eax, 0Dh
.not_lf:
	cmp eax, 255			; Not in the 8-bit range?
	jbe .ascii_ok
	mov eax, '?'
.ascii_ok:
	clc
	ret
.scancode:
	movzx ecx, word [key_buf]	; ScanCode
	cmp ecx, 17h			; Escape
	jne .not_esc
	mov eax, 011Bh			; AH = 01h, AL = 27
	clc
	ret
.not_esc:
	cmp ecx, 1			; Cursor keys, Home, End, Ins, Del, PgUp, PgDn
	jb .none
	cmp ecx, 0Ah
	ja .try_function
	lea rax, [rel .scan_table]
	movzx eax, byte [rax + rcx - 1]
	shl eax, 8			; AL = 0, AH = BIOS scan code
	clc
	ret
.try_function:
	cmp ecx, 0Bh			; F1 - F10
	jb .none
	cmp ecx, 14h
	ja .none
	lea eax, [rcx + 3Bh - 0Bh]
	shl eax, 8
	clc
	ret
.none:
	stc
	ret

.scan_table:
	db 48h, 50h, 4Dh, 4Bh, 47h, 4Fh, 52h, 53h, 49h, 51h


; ==================================================================
