; HELLO64.BIN -- sample 64-bit program for GMU OS 64
; Build: nasm -f bin -I ../source/ -I . hello64.asm -o hello64.bin

	db 'GMU64BIN'			; signature, code starts right after it

%include "mikedev64.inc"

start:
	OS_INIT
	mov [param], rsi

	lea rsi, [rel msg1]
	oscall os_print_string

	mov rsi, [param]		; parameters typed after the name
	test rsi, rsi
	jz .noparam
	lea rsi, [rel msg2]
	oscall os_print_string
	mov rsi, [param]
	oscall os_print_string
	oscall os_print_newline
.noparam:
	lea rsi, [rel msg3]		; show that RAX really is 64 bits wide
	oscall os_print_string
	mov rbx, 0x123456789ABCDEF0
	mov ecx, 4
.hex:
	rol rbx, 16			; take the next 16 bits from the top
	mov ax, bx
	oscall os_print_4hex
	dec ecx
	jnz .hex
	oscall os_print_newline
	ret

param	dq 0
msg1	db 'Hello from a 64-bit program running on GMU OS 64!', 13, 10, 0
msg2	db 'Parameters: ', 0
msg3	db 'A 64-bit register holds 0x', 0
