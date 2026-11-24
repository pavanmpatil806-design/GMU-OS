; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2021 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition: GM University, Davanagere, 2026
;
; STRING MANIPULATION ROUTINES  (64-bit version)
; Pointers are full 64-bit registers (RAX, RBX, RSI, RDI ...).
; ==================================================================


; ------------------------------------------------------------------
; os_string_length -- Return length of a string
; IN: AX = string location; OUT: AX = length (other regs preserved)

os_string_length:
	push rcx
	xor ecx, ecx
.more:
	cmp byte [rax + rcx], 0		; Zero (end of string) yet?
	je .done
	inc rcx				; If not, keep adding
	jmp .more
.done:
	mov rax, rcx
	pop rcx
	ret


; ------------------------------------------------------------------
; os_string_reverse -- Reverse the characters in a string
; IN: SI = string location

os_string_reverse:
	pushall
	cmp byte [rsi], 0		; Don't attempt to reverse empty string
	je .end
	mov rax, rsi
	call os_string_length
	mov rdi, rsi
	add rdi, rax
	dec rdi				; DI now points to last char in string
.loop:
	mov al, [rsi]			; Swap bytes
	mov bl, [rdi]
	mov [rsi], bl
	mov [rdi], al
	inc rsi				; Move towards string centre
	dec rdi
	cmp rdi, rsi			; Both reached the centre?
	ja .loop
.end:
	popall
	ret


; ------------------------------------------------------------------
; os_find_char_in_string -- Find location of character in a string
; IN: SI = string location, AL = character to find
; OUT: AX = location in string (1 = first char), or 0 if char not present

os_find_char_in_string:
	push rcx
	push rsi
	mov ecx, 1
.more:
	cmp [rsi], al
	je .done
	cmp byte [rsi], 0
	je .notfound
	inc rsi
	inc ecx
	jmp .more
.done:
	mov eax, ecx
	pop rsi
	pop rcx
	ret
.notfound:
	xor eax, eax
	pop rsi
	pop rcx
	ret


; ------------------------------------------------------------------
; os_string_charchange -- Change instances of character in a string
; IN: SI = string, AL = char to find, BL = char to replace with

os_string_charchange:
	push rsi
	push rax
	mov ah, al
.loop:
	mov al, [rsi]
	test al, al
	je .finish
	cmp al, ah
	jne .nochange
	mov [rsi], bl
.nochange:
	inc rsi
	jmp .loop
.finish:
	pop rax
	pop rsi
	ret


; ------------------------------------------------------------------
; os_string_uppercase -- Convert zero-terminated string to upper case
; IN/OUT: AX = string location

os_string_uppercase:
	push rsi
	mov rsi, rax			; Use SI to access string
.more:
	cmp byte [rsi], 0		; Zero-termination of string?
	je .done			; If so, quit
	cmp byte [rsi], 'a'		; In the lower case A to Z range?
	jb .noatoz
	cmp byte [rsi], 'z'
	ja .noatoz
	sub byte [rsi], 20h		; If so, convert input char to upper case
.noatoz:
	inc rsi
	jmp .more
.done:
	pop rsi
	ret


; ------------------------------------------------------------------
; os_string_lowercase -- Convert zero-terminated string to lower case
; IN/OUT: AX = string location

os_string_lowercase:
	push rsi
	mov rsi, rax
.more:
	cmp byte [rsi], 0
	je .done
	cmp byte [rsi], 'A'
	jb .noatoz
	cmp byte [rsi], 'Z'
	ja .noatoz
	add byte [rsi], 20h
.noatoz:
	inc rsi
	jmp .more
.done:
	pop rsi
	ret


; ------------------------------------------------------------------
; os_string_copy -- Copy one string into another
; IN/OUT: SI = source, DI = destination (programmer ensure sufficient room)

os_string_copy:
	push rax
	push rsi
	push rdi
.more:
	mov al, [rsi]			; Transfer contents (at least one byte terminator)
	mov [rdi], al
	inc rsi
	inc rdi
	test al, al			; If source string is empty, quit out
	jnz .more
	pop rdi
	pop rsi
	pop rax
	ret


; ------------------------------------------------------------------
; os_string_truncate -- Chop string down to specified number of characters
; IN: SI = string location, AX = number of characters

os_string_truncate:
	push rsi
	add rsi, rax
	mov byte [rsi], 0
	pop rsi
	ret


; ------------------------------------------------------------------
; os_string_join -- Join two strings into a third string
; IN/OUT: AX = string one, BX = string two, CX = destination string

os_string_join:
	pushall
	mov rsi, rax			; Put first string into CX
	mov rdi, rcx
	call os_string_copy
	call os_string_length		; Get length of first string
	add rcx, rax			; Position at end of first string
	mov rsi, rbx			; Add second string onto it
	mov rdi, rcx
	call os_string_copy
	popall
	ret


; ------------------------------------------------------------------
; os_string_chomp -- Strip leading and trailing spaces from a string
; IN: AX = string location

os_string_chomp:
	pushall
	mov rdx, rax			; Save string location
	mov rdi, rax			; Put location into DI
	xor ecx, ecx			; Space counter
.keepcounting:				; Get number of leading spaces into CX
	cmp byte [rdi], ' '
	jne .counted
	inc ecx
	inc rdi
	jmp .keepcounting
.counted:
	test ecx, ecx			; No leading spaces?
	je .finished_copy
	mov rsi, rdi			; Address of first non-space character
	mov rdi, rdx			; DI = original string start
.keep_copying:
	mov al, [rsi]			; Copy SI into DI
	mov [rdi], al			; Including terminator
	test al, al
	je .finished_copy
	inc rsi
	inc rdi
	jmp .keep_copying
.finished_copy:
	mov rax, rdx			; AX = original string start
	call os_string_length
	test rax, rax			; If empty or all blank, done, return 'null'
	je .done
	mov rsi, rdx
	add rsi, rax			; Move to end of string
.more:
	dec rsi
	cmp byte [rsi], ' '
	jne .done
	mov byte [rsi], 0		; Fill end spaces with 0s
	jmp .more			; (First 0 will be the string terminator)
.done:
	popall
	ret


; ------------------------------------------------------------------
; os_string_strip -- Removes specified character from a string
; IN: SI = string location, AL = character to remove

os_string_strip:
	pushall
	mov rdi, rsi
	mov bl, al			; Copy the char into BL since LODSB and STOSB use AL
.nextchar:
	lodsb
	stosb
	test al, al			; Check if we reached the end of the string
	je .finish			; If so, bail out
	cmp al, bl			; Check to see if the character we read is the interesting char
	jne .nextchar			; If not, skip to the next character
	dec rdi				; Decrement DI so we overwrite on the next pass
	jmp .nextchar
.finish:
	popall
	ret


; ------------------------------------------------------------------
; os_string_compare -- See if two strings match
; IN: SI = string one, DI = string two
; OUT: carry set if same, clear if different

os_string_compare:
	push rax
	push rbx
	push rsi
	push rdi
.more:
	mov al, [rsi]			; Retrieve string contents
	mov bl, [rdi]
	cmp al, bl			; Compare characters at current location
	jne .not_same
	test al, al			; End of first string? Must also be end of second
	je .terminated
	inc rsi
	inc rdi
	jmp .more
.not_same:				; If unequal lengths with same beginning, the byte
	pop rdi				; comparison fails at shortest string terminator
	pop rsi
	pop rbx
	pop rax
	clc				; Clear carry flag
	ret
.terminated:				; Both strings terminated at the same position
	pop rdi
	pop rsi
	pop rbx
	pop rax
	stc				; Set carry flag
	ret


; ------------------------------------------------------------------
; os_string_strincmp -- See if two strings match up to set number of chars
; IN: SI = string one, DI = string two, CL = chars to check
; OUT: carry set if same, clear if different

os_string_strincmp:
	push rax
	push rbx
	push rcx
	push rsi
	push rdi
.more:
	mov al, [rsi]
	mov bl, [rdi]
	cmp al, bl
	jne .not_same
	test al, al
	je .terminated
	inc rsi
	inc rdi
	dec cl				; If we've lasted through our char count
	test cl, cl			; Then the bits of the string match!
	je .terminated
	jmp .more
.not_same:
	pop rdi
	pop rsi
	pop rcx
	pop rbx
	pop rax
	clc
	ret
.terminated:
	pop rdi
	pop rsi
	pop rcx
	pop rbx
	pop rax
	stc
	ret


; ------------------------------------------------------------------
; os_string_parse -- Take string (eg "run foo bar baz") and return
; pointers to zero-terminated strings (eg AX = "run", BX = "foo" etc.)
; IN: SI = string; OUT: AX, BX, CX, DX = individual strings (0 if absent)

os_string_parse:
	push rsi
	mov rax, rsi			; AX = start of first string
	xor ebx, ebx			; By default, other strings start empty
	xor ecx, ecx
	xor edx, edx
	push rax			; Save to retrieve at end
.loop1:
	lodsb				; Get a byte
	test al, al			; End of string?
	je .finish
	cmp al, ' '			; A space?
	jne .loop1
	dec rsi
	mov byte [rsi], 0		; If so, zero-terminate this bit of the string
	inc rsi				; Store start of next string in BX
	mov rbx, rsi
.loop2:					; Repeat the above for CX and DX...
	lodsb
	test al, al
	je .finish
	cmp al, ' '
	jne .loop2
	dec rsi
	mov byte [rsi], 0
	inc rsi
	mov rcx, rsi
.loop3:
	lodsb
	test al, al
	je .finish
	cmp al, ' '
	jne .loop3
	dec rsi
	mov byte [rsi], 0
	inc rsi
	mov rdx, rsi
.finish:
	pop rax
	pop rsi
	ret


; ------------------------------------------------------------------
; os_string_to_int -- Convert decimal string to integer value
; IN: SI = string location; OUT: AX = number

os_string_to_int:
	push rsi
	push rcx
	xor eax, eax
.loop:
	movzx ecx, byte [rsi]
	sub ecx, '0'
	cmp ecx, 9
	ja .finish
	imul rax, rax, 10
	add rax, rcx
	inc rsi
	jmp .loop
.finish:
	pop rcx
	pop rsi
	ret


; ------------------------------------------------------------------
; os_int_to_string -- Convert unsigned integer to string
; IN: AX = unsigned int; OUT: AX = string location

os_int_to_string:
	pushall
	xor ecx, ecx
	mov ebx, 10			; Set BX 10, for division and mod
	lea rdi, [rel .t]		; Get our pointer ready
.push:
	xor edx, edx
	div rbx				; Remainder in DX, quotient in AX
	inc ecx				; Increase pop loop counter
	push rdx			; Push remainder, so as to reverse order when popping
	test rax, rax			; Is quotient zero?
	jnz .push			; If not, loop again
.pop:
	pop rdx				; Pop off values in reverse order, and add 48 to make them digits
	add dl, '0'			; And save them in the string, increasing the pointer each time
	mov [rdi], dl
	inc rdi
	dec ecx
	jnz .pop
	mov byte [rdi], 0		; Zero-terminate string
	popall
	lea rax, [rel .t]		; Return location of string
	ret

	.t	times 24 db 0


; ------------------------------------------------------------------
; os_sint_to_string -- Convert signed integer to string
; IN: AX = signed int; OUT: AX = string location

os_sint_to_string:
	pushall
	xor ecx, ecx
	mov ebx, 10
	lea rdi, [rel .t]
	test rax, rax			; Find out if X > 0 or not, force a sign
	js .neg
	jmp .push
.neg:
	neg rax				; Make AX positive
	mov byte [rel .t], '-'		; Add a minus sign to our string
	inc rdi				; Update the index
.push:
	xor edx, edx
	div rbx
	inc ecx
	push rdx
	test rax, rax
	jnz .push
.pop:
	pop rdx
	add dl, '0'
	mov [rdi], dl
	inc rdi
	dec ecx
	jnz .pop
	mov byte [rdi], 0
	popall
	lea rax, [rel .t]
	ret

	.t	times 24 db 0


; ------------------------------------------------------------------
; os_long_int_to_string -- Convert value in RAX to string
; IN: RAX = unsigned integer (now up to 64 bits), BX = number base,
;     DI = string location
; OUT: DI = location of converted string

os_long_int_to_string:
	pushall
	mov byte [rdi], 0		; Terminate string, creates 'null'
	cmp rbx, 37			; Base > 37 or < 0 not supported, return null
	ja .done
	test rbx, rbx			; Base = 0 produces overflow, return null
	je .done
	lea r8, [rel .tmp]
	xor ecx, ecx
.conversion_loop:
	xor edx, edx
	div rbx				; RDX = digit, RAX = rest
	cmp edx, 9			; Eliminate punctuation between '9' and 'A'
	jle .convert_digit
	add edx, 'A'-'9'-1
.convert_digit:
	add edx, '0'			; Convert to ASCII
	mov [r8 + rcx], dl
	inc ecx
	test rax, rax			; Nothing left?
	jnz .conversion_loop
.reverse:				; Digits were produced LSD first
	dec ecx
	mov al, [r8 + rcx]
	mov [rdi], al
	inc rdi
	test ecx, ecx
	jnz .reverse
	mov byte [rdi], 0
.done:
	popall
	ret

	.tmp	times 72 db 0


; ------------------------------------------------------------------
; os_string_to_long_int -- Convert decimal string to integer value
; IN: SI = string location; OUT: RAX = number

os_string_to_long_int:
	push rsi
	push rcx
	xor eax, eax
.dloop:
	movzx ecx, byte [rsi]
	sub ecx, '0'			; Test validity
	cmp ecx, 9
	ja .finish
	imul rax, rax, 10		; Current total = last * 10 + this digit
	add rax, rcx
	inc rsi
	jmp .dloop
.finish:
	pop rcx
	pop rsi
	ret


; ------------------------------------------------------------------
; os_set_time_fmt -- Set time reporting format (eg '10:25 AM' or '2300 hours')
; IN: AL = format flag, 0 = 12-hr format

os_set_time_fmt:
	test al, al
	je .store
	mov al, 0FFh
.store:
	mov [fmt_12_24], al
	ret


; ------------------------------------------------------------------
; rtc_read -- (internal) read the real-time clock through UEFI
; Fills rtc_time (EFI_TIME). Preserves all registers.

rtc_read:
	pushall
	lea rcx, [rel rtc_time]
	xor edx, edx
	mov rax, [run_svc]
	mov rax, [rax + RT_GETTIME]
	call efi_thunk
	popall
	ret


; ------------------------------------------------------------------
; os_get_time_string -- Get current time in a string (eg '10:25 PM')
; IN/OUT: BX = string location

os_get_time_string:
	pushall
	mov rdi, rbx			; Location to place time string
	call rtc_read
	movzx edx, byte [rtc_time + 4]	; Hours 0-23
	movzx ecx, byte [rtc_time + 5]	; Minutes
	test byte [fmt_12_24], 0FFh
	jz .twelve_hr
	mov eax, edx			; 24-hour format: 'HHMM hours'
	call .put2
	jmp .minutes
.twelve_hr:
	mov eax, edx
	test eax, eax			; If 00mm, make 12 AM
	jnz .not_midnight
	mov eax, 12
.not_midnight:
	cmp eax, 12			; Change from 24 to 12-hour format
	jle .hour_ready
	sub eax, 12
.hour_ready:
	cmp eax, 10			; Before 10, store 1 digit
	jb .one_digit
	call .put2
	jmp .colon
.one_digit:
	add al, '0'
	stosb
.colon:
	mov al, ':'			; Time separator (12-hr format)
	stosb
.minutes:
	mov eax, ecx
	call .put2
	mov al, ' '			; Separate time designation
	stosb
	lea rsi, [rel .hours_string]	; Assume 24-hr format
	test byte [fmt_12_24], 0FFh
	jnz .copy
	lea rsi, [rel .pm_string]	; Assume PM
	cmp edx, 12			; Test for AM/PM
	jge .copy
	lea rsi, [rel .am_string]	; Was actually AM
.copy:
	lodsb				; Copy designation, including terminator
	stosb
	test al, al
	jnz .copy
	popall
	ret

.put2:					; EAX (0-99) -> two ASCII digits at RDI
	push rcx
	push rdx
	xor edx, edx
	mov ecx, 10
	div ecx
	add al, '0'
	stosb
	mov al, dl
	add al, '0'
	stosb
	pop rdx
	pop rcx
	ret

	.hours_string	db 'hours', 0
	.am_string	db 'AM', 0
	.pm_string	db 'PM', 0


; ------------------------------------------------------------------
; os_set_date_fmt -- Set date reporting format (M/D/Y, D/M/Y or Y/M/D - 0, 1, 2)
; IN: AX = format flag, 0-2
; If AX bit 7 = 1 = use name for months
; If AX bit 7 = 0, high byte = separator character

os_set_date_fmt:
	push rax
	test al, 80h			; ASCII months (bit 7)?
	jnz .fmt_clear
	and ax, 7F03h			; 7-bit ASCII separator and format number
	jmp short .fmt_test
.fmt_clear:
	and ax, 0003h			; Ensure separator is clear
.fmt_test:
	cmp al, 3			; Only allow 0, 1 and 2
	jae .leave
	mov [fmt_date], ax
.leave:
	pop rax
	ret


; ------------------------------------------------------------------
; os_get_date_string -- Get current date in a string (eg '12/31/2007')
; IN/OUT: BX = string location

os_get_date_string:
	pushall
	mov rdi, rbx			; Store string location for now
	call rtc_read
	movzx r8d, word [rtc_time]	; Year
	movzx r9d, byte [rtc_time + 2]	; Month
	movzx r10d, byte [rtc_time + 3]	; Day
	movzx ebx, byte [fmt_date]	; BL = format code
	and ebx, 3
	movzx ecx, byte [fmt_date + 1]	; CL = separator, 0 = use month names
	and ecx, 7Fh
	cmp ebx, 2			; YYYY/MM/DD format, suitable for sorting
	jne .try_fmt1
	mov eax, r8d
	call .put4			; Always provide 4-digit year
	mov al, '/'
	stosb
	mov eax, r9d
	call .put2			; Always 2-digit month
	mov al, '/'
	stosb
	mov eax, r10d
	call .put2			; Always 2-digit day
	jmp .done
.try_fmt1:
	cmp ebx, 1			; D/M/Y format (military and Europe)
	jne .do_fmt0
	mov eax, r10d			; Day
	call .put1or2
	mov al, cl
	test cl, cl
	jnz .fmt1_day
	mov al, ' '			; If ASCII months, use space as separator
.fmt1_day:
	stosb				; Day-month separator
	mov eax, r9d			; Month
	test cl, cl			; ASCII?
	jnz .fmt1_month
	call .add_month			; Yes, add to string
	mov al, ','
	stosb
	mov al, ' '
	stosb
	jmp .fmt1_year
.fmt1_month:
	call .put1or2			; No, use digits and separator
	mov al, cl
	stosb
.fmt1_year:
	mov eax, r8d
	call .put4
	jmp .done
.do_fmt0:				; Default format, M/D/Y (US and others)
	mov eax, r9d			; Month
	test cl, cl			; ASCII?
	jnz .fmt0_month
	call .add_month			; Yes, add to string and space
	mov al, ' '
	stosb
	jmp .fmt0_day
.fmt0_month:
	call .put1or2			; No, use digits and separator
	mov al, cl
	stosb
.fmt0_day:
	mov eax, r10d			; Day
	call .put1or2
	mov al, cl
	test cl, cl			; ASCII?
	jnz .fmt0_day2
	mov al, ','			; Yes, separator = comma space
	stosb
	mov al, ' '
.fmt0_day2:
	stosb
	mov eax, r8d
	call .put4
.done:
	mov byte [rdi], 0		; Terminate date string
	popall
	ret

.put1or2:
	cmp eax, 10
	jae .put2
	add al, '0'
	stosb
	ret

.put2:					; EAX (0-99) -> two ASCII digits
	push rcx
	push rdx
	xor edx, edx
	mov ecx, 10
	div ecx
	add al, '0'
	stosb
	mov al, dl
	add al, '0'
	stosb
	pop rdx
	pop rcx
	ret

.put4:					; EAX (0-9999) -> four ASCII digits
	push rcx
	push rdx
	xor edx, edx
	mov ecx, 100
	div ecx
	push rdx
	call .put2
	pop rax
	call .put2
	pop rdx
	pop rcx
	ret

.add_month:
	push rsi
	push rcx
	dec eax				; January = 0
	cmp eax, 11
	jbe .month_ok
	xor eax, eax
.month_ok:
	shl eax, 2			; Multiply month by 4 characters/month
	lea rsi, [rel .months]
	add rsi, rax
	mov ecx, 4
	rep movsb
	cmp byte [rdi - 1], ' '		; May?
	jne .done_month			; Yes, eliminate extra space
	dec rdi
.done_month:
	pop rcx
	pop rsi
	ret

	.months db 'Jan.Feb.Mar.Apr.May JuneJulyAug.SeptOct.Nov.Dec.'


; ------------------------------------------------------------------
; os_string_tokenize -- Reads tokens separated by specified char from
; a string. Returns pointer to next token, or 0 if none left
; IN: AL = separator char, SI = beginning; OUT: DI = next token or 0 if none

os_string_tokenize:
	push rsi
.next_char:
	cmp [rsi], al
	je .return_token
	cmp byte [rsi], 0
	jz .no_more
	inc rsi
	jmp .next_char
.return_token:
	mov byte [rsi], 0
	inc rsi
	mov rdi, rsi
	pop rsi
	ret
.no_more:
	xor edi, edi
	pop rsi
	ret


; ==================================================================
