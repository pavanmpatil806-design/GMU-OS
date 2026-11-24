; ==================================================================
; GMU OS 64 -- UEFI definitions, helper macros
; Based on MikeOS (c) 2006 - 2022 MikeOS Developers -- see doc/LICENSE.TXT
; ==================================================================

; ---- EFI_SYSTEM_TABLE offsets
ST_CONIN		equ 48
ST_CONOUT		equ 64
ST_RUNTIME		equ 88
ST_BOOT			equ 96

; ---- EFI_BOOT_SERVICES offsets
BS_ALLOCATEPAGES	equ 40
BS_WAITFOREVENT		equ 96
BS_HANDLEPROTOCOL	equ 152
BS_STALL		equ 248
BS_SETWATCHDOG		equ 256

; ---- EFI_RUNTIME_SERVICES offsets
RT_GETTIME		equ 24
RT_RESETSYSTEM		equ 104

; ---- EFI_SIMPLE_TEXT_INPUT_PROTOCOL
CIN_RESET		equ 0
CIN_READKEY		equ 8
CIN_WAITKEY		equ 16

; ---- EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
COUT_OUTSTR		equ 8
COUT_SETMODE		equ 32
COUT_SETATTR		equ 40
COUT_CLEAR		equ 48
COUT_SETCUR		equ 56
COUT_ENCUR		equ 64
COUT_MODE		equ 72

; ---- EFI_FILE_PROTOCOL
FILE_OPEN		equ 8
FILE_CLOSE		equ 16
FILE_DELETE		equ 24
FILE_READ		equ 32
FILE_WRITE		equ 40
FILE_SETPOS		equ 56
FILE_GETINFO		equ 64
FILE_SETINFO		equ 72

; ---- file open modes
EFI_FILE_READ		equ 1
EFI_FILE_RW		equ 3
EFI_FILE_CREATE_RW	equ 0x8000000000000003

; ---- Directory record kept by the kernel (one per file, 64 bytes)
;      (dates/times are stored in FAT format, so the original
;       type_date / type_time routines work unchanged)
REC_SIZE		equ 64
REC_NAME		equ 0		; 32 bytes, ASCII, zero terminated
REC_ATTR		equ 32		; DOS attribute byte
REC_CDATE		equ 34		; created date  (FAT format)
REC_CTIME		equ 36		; created time  (FAT format)
REC_MDATE		equ 38		; modified date (FAT format)
REC_MTIME		equ 40		; modified time (FAT format)
REC_FSIZE		equ 44		; file size in bytes (dword)
MAX_RECS		equ 512

FILE_MAX		equ 1048576	; largest file the kernel will load (1 MB)

; ---- General register save / restore (64-bit replacement for PUSHA / POPA)
%macro pushall 0
	push rax
	push rcx
	push rdx
	push rbx
	push rbp
	push rsi
	push rdi
	push r8
	push r9
	push r10
	push r11
%endmacro

%macro popall 0
	pop r11
	pop r10
	pop r9
	pop r8
	pop rdi
	pop rsi
	pop rbp
	pop rbx
	pop rdx
	pop rcx
	pop rax
%endmacro

; ---- PCALL var, offset -- call a method of an EFI protocol whose
;      interface pointer is stored in memory variable "var".
;      Arguments 2..5 must already be in RDX, R8, R9, R10.
%macro PCALL 2
	mov rcx, [%1]
	mov rax, [rcx + %2]
	call efi_thunk
%endmacro

; ---- BCALL offset -- call an EFI Boot Service.
;      Arguments must already be in RCX, RDX, R8, R9, R10.
%macro BCALL 1
	mov rax, [boot_svc]
	mov rax, [rax + %1]
	call efi_thunk
%endmacro
