; ==================================================================
; GMU OS 64 -- 64-bit UEFI edition of MikeOS
; Based on MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2022 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS derivative learning edition: GM University, Davanagere, 2026
;
; This file is a complete UEFI application (PE32+, x86-64).
; Build it with:   nasm -f bin -o BOOTX64.EFI kernel.asm
; and put the result at  \EFI\BOOT\BOOTX64.EFI  on a FAT32 USB stick
; (or in a QEMU/OVMF disk image).  The firmware loads it in 64-bit
; long mode, so no real-mode / protected-mode switching is needed.
; ==================================================================

	BITS 64
	DEFAULT REL

	%DEFINE MIKEOS_VER '4.7.0'	; OS version number
	%DEFINE MIKEOS_API_VER 18	; API version for programs to check

	%INCLUDE "uefi.inc"

; ------------------------------------------------------------------
; PE32+ HEADER  (hand-built so that only NASM is needed to build)

TEXT_VA		equ 0x1000
RELOC_VA	equ 0x100000		; .text may grow up to 1 MB
BSS_VA		equ 0x101000

section .hdr start=0 vstart=0

dos_header:
	dw 0x5A4D			; 'MZ'
	times 0x3A db 0
	dd pe_header			; e_lfanew
pe_header:
	db 'PE', 0, 0
	dw 0x8664			; Machine: x86-64
	dw 3				; Sections: .text .reloc .bss
	dd 0, 0, 0
	dw opt_end - opt_start		; SizeOfOptionalHeader
	dw 0x0022			; EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE
opt_start:
	dw 0x20B			; PE32+
	db 14, 0
	dd text_raw_end - text_start	; SizeOfCode
	dd 0
	dd bss_end - bss_start		; SizeOfUninitializedData
	dd efi_main			; AddressOfEntryPoint
	dd text_start			; BaseOfCode
	dq 0x140000000			; ImageBase (code is position independent)
	dd 0x1000			; SectionAlignment
	dd 0x200			; FileAlignment
	dw 6, 0, 0, 0, 6, 0
	dd 0
	dd bss_end			; SizeOfImage
	dd 0x200			; SizeOfHeaders
	dd 0
	dw 10				; Subsystem: EFI application
	dw 0x0100			; NX_COMPAT
	dq 0x100000, 0x10000, 0x100000, 0x10000
	dd 0
	dd 16				; NumberOfRvaAndSizes
	dd 0, 0				; export
	dd 0, 0				; import
	dd 0, 0				; resource
	dd 0, 0				; exception
	dd 0, 0				; certificate
	dd reloc_start, reloc_end - reloc_start	; base relocations
	times 10 dd 0, 0
opt_end:
	db '.text', 0, 0, 0
	dd text_end - text_start
	dd text_start
	dd text_raw_end - text_start
	dd 0x200
	dd 0, 0
	dw 0, 0
	dd 0xE0000060			; code, initialised data, R/W/X
	db '.reloc', 0, 0
	dd reloc_end - reloc_start
	dd reloc_start
	dd 0x200
	dd 0x200 + (text_raw_end - text_start)
	dd 0, 0
	dw 0, 0
	dd 0x42000040
	db '.bss', 0, 0, 0, 0
	dd bss_end - bss_start
	dd bss_start
	dd 0
	dd 0
	dd 0, 0
	dw 0, 0
	dd 0xC0000080
	align 0x200, db 0

; ------------------------------------------------------------------
section .text start=0x200 vstart=TEXT_VA

text_start:

; ------------------------------------------------------------------
; efi_main -- firmware entry point
; IN: RCX = ImageHandle, RDX = EFI_SYSTEM_TABLE*

efi_main:
	cld
	mov [image_handle], rcx
	mov [system_table], rdx
	mov rax, [rdx + ST_CONIN]
	mov [con_in], rax
	mov rax, [rdx + ST_CONOUT]
	mov [con_out], rax
	mov rax, [rdx + ST_BOOT]
	mov [boot_svc], rax
	mov rax, [rdx + ST_RUNTIME]
	mov [run_svc], rax

	xor ecx, ecx			; Disable the 5-minute watchdog reset
	xor edx, edx
	xor r8d, r8d
	xor r9d, r9d
	BCALL BS_SETWATCHDOG

	xor edx, edx			; Text mode 0 = 80x25, like BIOS mode 3
	PCALL con_out, COUT_SETMODE
	xor edx, edx
	PCALL con_in, CIN_RESET

	mov qword [con_in_ex], 0	; extended keyboard protocol (Shift state)
	mov rax, [system_table]
	mov rcx, [rax + 40]		; ConsoleInHandle
	lea rdx, [rel guid_input_ex]
	lea r8, [rel con_in_ex]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jz .ex_ok
	mov qword [con_in_ex], 0
.ex_ok:

	mov byte [hw_attr], 0xFF	; force first attribute to be sent
	mov byte [cur_attr], 0x07

	call init_vectors

	xor ecx, ecx			; Allocate the 1 MB program/file area
	mov edx, 1			; EfiLoaderCode: executable memory
	mov r8d, FILE_MAX / 4096 + 1
	lea r9, [rel prog_area]
	BCALL BS_ALLOCATEPAGES
	test rax, rax
	jz .have_area
	call os_clear_screen
	lea rsi, [rel .nomem_msg]
	call os_print_string
.hang:
	hlt
	jmp .hang
.have_area:
	call disk_mount			; Open the boot volume (USB stick / disk image)
	call disk_scan_usb		; and look for other USB drives
	jmp os_main

	.nomem_msg db 'GMU OS: cannot allocate memory', 13, 10, 0


; ------------------------------------------------------------------
; init_vectors -- fill vec_table with absolute addresses of the kernel
; system calls (programs receive the table's address in RDI)

init_vectors:
	lea rdi, [rel vec_table]
%macro V 1
	lea rax, [rel %1]
	stosq
%endmacro
%macro VU 1				; not ported yet: points at os_unsupported
	lea rax, [rel os_unsupported]
	stosq
%endmacro
	%include "vectors.inc"
%unmacro V 1
%unmacro VU 1
	ret


; ------------------------------------------------------------------
; START OF MAIN KERNEL CODE

os_main:
	cld

	call os_seed_random		; Seed random number generator

	; Let's see if there's a file called AUTORUN.BIN and execute
	; it if so, before going to the program launcher menu

	lea rax, [rel autorun_bin_file_name]
	call os_file_exists
	jc gui_start			; Skip if AUTORUN.BIN doesn't exist: desktop (or text menu)

	mov rcx, [prog_area]		; Otherwise load the program into RAM...
	call os_load_file
	jmp execute_bin_program		; ...and move on to the executing part


	; Now we display a dialog box offering the user a choice of
	; a menu-driven program selector, or a command-line interface

option_screen:
	lea rax, [rel os_init_msg]	; Set up the welcome screen
	lea rbx, [rel os_version_msg]
	mov ecx, 10011111b		; Colour: white text on light blue
	call os_draw_background

	lea rax, [rel dialog_string_1]	; Ask if user wants app selector or command-line
	lea rbx, [rel dialog_string_2]
	lea rcx, [rel dialog_string_3]
	mov edx, 1			; We want a two-option dialog box (OK or Cancel)
	call os_dialog_box

	cmp rax, 1			; If OK (option 0) chosen, start app selector
	jne app_selector

	call os_clear_screen		; Otherwise clean screen and start the CLI
	call os_command_line

	jmp option_screen		; Offer menu/CLI choice after CLI has exited


	; Data for the above code...

	os_init_msg		db 'Welcome to MikeOS', 0
	os_version_msg		db 'Version ', MIKEOS_VER, ' (64-bit UEFI)', 0

	dialog_string_1		db 'Thanks for trying out MikeOS!', 0
	dialog_string_2		db 'Please select an interface: OK for the', 0
	dialog_string_3		db 'program menu, Cancel for command line.', 0


app_selector:
	lea rax, [rel os_init_msg]	; Draw main screen layout
	lea rbx, [rel os_version_msg]
	mov ecx, 10011111b		; Colour: white text on light blue
	call os_draw_background

	call os_file_selector		; Get user to select a file, and store
					; the resulting string location in AX

	jc option_screen		; Return to the CLI/menu choice screen if Esc pressed

	mov rsi, rax			; Did the user try to run 'KERNEL.BIN'?
	lea rdi, [rel kern_file_name]
	call os_string_compare
	jc no_kernel_execute		; Show an error message if so

	; Next, we need to check that the program we're attempting to run is
	; valid -- in other words, that it has a .BIN extension

	push rsi			; Save filename temporarily

	mov rax, rsi
	call os_string_length
	mov rbx, rsi
	add rbx, rax			; BX now points to end of filename...
	sub rbx, 3			; ...and now to start of extension!
	cmp rbx, rsi
	jb not_bin_extension		; (name shorter than 3 chars)

	push rsi
	mov rsi, rbx
	lea rdi, [rel bin_ext]
	mov ecx, 3
	repe cmpsb			; Are final 3 chars 'BIN'?
	pop rsi
	jne not_bin_extension		; If not, it might be a '.BAS'

	pop rsi				; Restore filename

	mov rax, rsi
	mov rcx, [prog_area]		; Where to load the program file
	call os_load_file		; Load filename pointed to by AX

execute_bin_program:
	call os_clear_screen		; Clear screen before running

	mov rsi, [prog_area]		; 64-bit programs start with 'GMU64BIN'
	mov rax, 'GMU64BIN'
	cmp [rsi], rax
	jne .not_64bit

	xor eax, eax			; Clear all registers
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx
	xor esi, esi
	lea rdi, [rel vec_table]
	mov r8, [prog_area]
	add r8, 8
	call r8				; Call the external program code
					; (program must end with 'ret')
	jmp .finished

.not_64bit:
	lea rsi, [rel not64_msg]
	call os_print_string

.finished:
	lea rsi, [rel program_finished_msg]	; Give the program a chance to display
	call os_print_string			; any output before clearing the screen
	call os_wait_for_key

	call os_clear_screen		; When finished, clear screen
	jmp app_selector		; and go back to the program list


no_kernel_execute:			; Warn about trying to executing kernel!
	lea rax, [rel kerndlg_string_1]
	lea rbx, [rel kerndlg_string_2]
	lea rcx, [rel kerndlg_string_3]
	xor edx, edx			; One button for dialog box
	call os_dialog_box

	jmp app_selector		; Start over again...


not_bin_extension:
	pop rsi				; We pushed during the .BIN extension check

	lea rax, [rel ext_string_1]
	lea rbx, [rel ext_string_2]
	xor ecx, ecx
	xor edx, edx			; One button for dialog box
	call os_dialog_box

	jmp app_selector		; Start over again...


	; And now data for the above code...

	kern_file_name		db 'KERNEL.BIN', 0
	autorun_bin_file_name	db 'AUTORUN.BIN', 0
	bin_ext			db 'BIN'

	kerndlg_string_1	db 'Cannot load and execute MikeOS kernel!', 0
	kerndlg_string_2	db 'KERNEL.BIN is the core of MikeOS, and', 0
	kerndlg_string_3	db 'is not a normal program.', 0

	ext_string_1		db 'Invalid filename extension! You can', 0
	ext_string_2		db 'only execute 64-bit .BIN programs.', 0

	program_finished_msg	db '>>> Program finished -- press a key to continue...', 0


; ------------------------------------------------------------------
; SYSTEM VARIABLES -- Settings for programs and system calls

	; Time and date formatting

	fmt_12_24	db 0		; Non-zero = 24-hr format

	fmt_date	db 0, '/'	; 0, 1, 2 = M/D/Y, D/M/Y or Y/M/D
					; Bit 7 = use name for months
					; If bit 7 = 0, second byte = separator character

	; UEFI state
	image_handle	dq 0
	system_table	dq 0
	con_in		dq 0
	con_out		dq 0
	boot_svc	dq 0
	run_svc		dq 0
	root_dir	dq 0
	prog_area	dq 0
	li_ptr		dq 0
	sfs_ptr		dq 0
	file_handle	dq 0
	info_size	dq 0
	lf_dest		dq 0
	lf_size		dq 0
	lf_status	dq 0
	wf_name		dq 0
	wf_buf		dq 0
	wf_size		dq 0
	wf_status	dq 0
	rn_new		dq 0
	dir_count	dd 0
	hist_count	dd 0
	hist_pos	dd 0
	hist_enable	db 0
	list_dirs	db 0
	drive_missing	db 0
	vol_count	dd 1		; 0 = boot drive, 1.. = other USB drives
	usb_i		dd 0
	boot_dev	dq 0
	list_root	dq 0
	sc_count	dq 0
	sc_buf		dq 0
	sc_dp		dq 0
	sc_root		dq 0
	sfs_tmp		dq 0
	dir_cols	dd 4
	dir_colw	dd 20
	dir_limit	db 0
	cur_attr	db 7
	hw_attr		db 0xFF
	key_buf		dw 0, 0
	key_data	times 16 db 0
	key_shift	db 0
	con_in_ex	dq 0
	evt_index	dq 0
	wchar_buf	dw 0, 0
	rtc_time	times 16 db 0

	; GUIDs
guid_loaded_image:	dd 0x5B1B31A1
			dw 0x9562, 0x11D2
			db 0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B
guid_sfs:		dd 0x964E5B22
			dw 0x6459, 0x11D2
			db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B
guid_input_ex:		dd 0xDD9E7534
			dw 0x7762, 0x4698
			db 0x8C, 0x14, 0xF5, 0x85, 0x17, 0xA6, 0x25, 0xAA
guid_devpath:		dd 0x09576E91
			dw 0x6D3F, 0x11D2
			db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B
guid_file_info:		dd 0x09576E92
			dw 0x6D3F, 0x11D2
			db 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B


; ------------------------------------------------------------------
; FEATURES -- Code to pull into the kernel

	%INCLUDE "features/cli.asm"
	%INCLUDE "features/ccomp.asm"
	%INCLUDE "features/cedit.asm"
	%INCLUDE "features/prn.asm"
	%INCLUDE "features/gfx.asm"
	%INCLUDE "features/gui.asm"
	%INCLUDE "features/guiprn.asm"
	%INCLUDE "features/disk.asm"
	%INCLUDE "features/keyboard.asm"
	%INCLUDE "features/math.asm"
	%INCLUDE "features/misc.asm"
	%INCLUDE "features/ports.asm"
	%INCLUDE "features/screen.asm"
	%INCLUDE "features/sound.asm"
	%INCLUDE "features/string.asm"

text_end:
	%if (text_end - text_start) > (RELOC_VA - TEXT_VA)
	%error ".text is larger than 1 MB - raise RELOC_VA/BSS_VA"
	%endif
	align 0x200, db 0
text_raw_end:

; ------------------------------------------------------------------
section .reloc follows=.text vstart=RELOC_VA
reloc_start:
	dd TEXT_VA, 12			; one empty (ABSOLUTE) block: the code is
	dw 0, 0				; fully position independent
reloc_end:
	align 0x200, db 0

; ------------------------------------------------------------------
section .bss nobits start=BSS_VA

bss_start:
vec_table	resq 128
strbuf		resb 512
wname		resb 512
info_buf	resb 1024
dir_buffer	resb MAX_RECS * REC_SIZE
file_sel_buf	resb 4096
hist_buf	resb 16 * 64
vol_root	resq 8
usb_tmp		resb 4096
clip_buf	resb FILE_MAX
c_src		resb 65600		; C source file
c_code		resb 65600		; compiled bytecode
c_strs		resb 16384		; string literals
c_stk		resq 4096		; VM operand stack
c_lstk		resq 16384		; VM local variables (frames)
c_cstk		resq 2048		; VM call frames: return pc, caller fp
c_glob		resq 4096		; VM global variables
c_syms		resb 64*512		; compiler symbol table
c_fns		resb 64*128		; compiler function table
c_patch		resq 3*2048		; call sites to fix up (pos, fn, nargs)
c_brk		resq 2*256		; pending break jumps (pos, loop depth)
loop_cont	resq 64			; continue address per loop depth
c_numbuf	resb 96
c_name		resb 64			; identifier read by the lexer
xt_tab		resd 4096		; wallpaper scaling table
	alignb 4096
bss_end:
