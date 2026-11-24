; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2019 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition
;
; MISCELLANEOUS ROUTINES (64-bit version)
; ==================================================================


; ------------------------------------------------------------------
; os_get_api_version -- Return current version of the OS API
; IN: Nothing; OUT: AL = API version number

os_get_api_version:
	mov al, MIKEOS_API_VER
	ret


; ------------------------------------------------------------------
; os_pause -- Delay execution for specified 110ms chunks
; IN: AX = 110 millisecond chunks to wait

os_pause:
	pushall
	movzx rcx, ax
	imul rcx, rcx, 110000			; microseconds
	BCALL BS_STALL
	popall
	ret


; ------------------------------------------------------------------
; os_fatal_error -- Display error message and halt execution
; IN: AX = error message string location

os_fatal_error:
	mov rbx, rax				; Store string location for now
	mov dh, 0
	mov dl, 0
	call os_move_cursor
	mov bl, 01001111b			; Draw red bar at top
	mov ecx, 240
	push rax
	call os_fill_cells
	pop rax
	mov byte [cur_attr], 01001111b
	mov dh, 0
	mov dl, 0
	call os_move_cursor
	lea rsi, [rel .msg_inform]		; Inform of fatal error
	call os_print_string
	mov rsi, rax				; Program-supplied error message
	call os_print_string
.halt:
	hlt					; Halt execution
	jmp .halt

	.msg_inform	db '>>> FATAL OPERATING SYSTEM ERROR', 13, 10, 0


; ------------------------------------------------------------------
; os_unsupported -- placeholder for system calls that exist in the
; 16-bit MikeOS but have not been ported to the 64-bit edition yet.

os_unsupported:
	push rsi
	lea rsi, [rel .msg]
	call os_print_string
	pop rsi
	stc
	ret

	.msg	db '[system call not available in the 64-bit edition]', 13, 10, 0


; ==================================================================
