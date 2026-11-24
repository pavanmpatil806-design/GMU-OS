; ==================================================================
; MikeOS 64 -- system call interface for 64-bit programs
; Include this file at the top of a program (see hello64.asm).
;
; Programs are flat, position-independent 64-bit binaries that begin
; with the 8-byte signature 'GMU64BIN'. The kernel calls the code
; just after the signature with:
;     RDI = address of the system-call table
;     RSI = parameter string typed after the program name (or 0)
; Register conventions of every os_* call are the same as in 16-bit
; MikeOS, but pointers are 64-bit (RAX/RBX/RCX/RSI/RDI hold addresses).
; R11 is used by the oscall macro; the program must end with RET.
; ==================================================================

	BITS 64
	DEFAULT REL

%assign _vi 0
%macro V 1
	%1 equ _vi
	%assign _vi _vi + 1
%endmacro
%macro VU 1
	V %1
%endmacro
%include "vectors.inc"
%unmacro V 1
%unmacro VU 1

; OS_INIT -- first thing a program does (saves the table address)
%macro OS_INIT 0
	mov [rel os_vecs], rdi
%endmacro

; oscall os_print_string  -- call a system call by name
%macro oscall 1
	mov r11, [rel os_vecs]
	call [r11 + 8 * %1]
%endmacro

os_vecs: dq 0
