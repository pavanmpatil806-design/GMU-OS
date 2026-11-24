; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2021 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition
;
; MATH ROUTINES (64-bit version)
; ==================================================================


; ------------------------------------------------------------------
; os_seed_random -- Seed the random number generator based on clock
; IN: Nothing; OUT: Nothing (registers preserved)

os_seed_random:
	push rax
	call rtc_read
	movzx eax, byte [rtc_time + 5]		; Minute
	shl eax, 8
	or al, [rtc_time + 6]			; Second
	mov [os_random_seed], ax
	pop rax
	ret

	os_random_seed	dw 0


; ------------------------------------------------------------------
; os_get_random -- Return a random integer between low and high (inclusive)
; IN: AX = low integer, BX = high integer
; OUT: CX = random integer

os_get_random:
	push rdx
	push rbx
	push rax
	movzx ebx, bx
	movzx eax, ax
	sub ebx, eax				; We want a number between 0 and (high-low)
	movzx eax, word [os_random_seed]	; linear congruent method
	imul eax, eax, 23167
	add eax, 12409
	movzx eax, ax
	mov [os_random_seed], ax
	lea edx, [rbx + 1]
	imul eax, edx
	shr eax, 16
	mov ecx, eax
	pop rax
	pop rbx
	pop rdx
	movzx eax, ax
	add ecx, eax				; Add the low offset back
	ret


; ------------------------------------------------------------------
; os_bcd_to_int -- Converts binary coded decimal number to an integer
; IN: AL = BCD number; OUT: AX = integer value

os_bcd_to_int:
	push rbx
	mov bl, al
	and al, 0Fh
	shr bl, 4
	imul ebx, ebx, 10
	movzx eax, al
	add eax, ebx
	pop rbx
	ret


; ------------------------------------------------------------------
; os_long_int_negate -- Multiply value in RAX by -1

os_long_int_negate:
	neg rax
	ret


; ==================================================================
