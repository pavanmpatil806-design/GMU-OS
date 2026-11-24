; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2019 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS derivative learning edition: GM University, Davanagere, 2026
;
; COMMAND LINE INTERFACE  (64-bit UEFI version)
;
; Same commands, same behaviour and same messages as the 16-bit cli.asm:
;   EXIT HELP GMUINFO ABOUT CAL CLS DIR LS VER TIME DATE PBL
;   CAT DEL COPY REN SIZE, plus running programs by name.
; Pointers are 64-bit now (RSI/RDI/RAX/RBX...), file data lives in the
; 1 MB program area (prog_area) instead of segment offset 32768.
; ==================================================================

os_command_line:
	call os_clear_screen
	cmp byte [cli_start_cmd], 0		; started from the desktop's C Compiler icon?
	je .normal
	mov byte [cli_start_cmd], 0
	jmp c_editor
.normal:

	lea rsi, [rel version_msg]
	call os_print_string
	lea rsi, [rel help_text]
	call os_print_string

get_cmd:
	lea rdi, [rel command]			; Clear the command buffer
	mov ecx, 80
	xor eax, eax
	rep stosb

	lea rsi, [rel prompt]
	call os_print_string

	lea rax, [rel input]
	mov ebx, 64
	mov byte [hist_enable], 1		; Up/Down arrows recall earlier commands
	call os_input_string
	mov byte [hist_enable], 0

	call os_print_newline

	lea rax, [rel input]
	call os_string_chomp

	lea rsi, [rel input]
	cmp byte [rsi], 0
	je get_cmd

	call hist_add				; Remember this command line

	; --------------------------------------------------------------
	; Check whether a parameter exists.
	; We do this before tokenizing the command.
	; --------------------------------------------------------------

	lea rsi, [rel input]

.find_parameter:
	mov al, [rsi]
	cmp al, 0
	je .no_parameter
	cmp al, ' '
	je .has_parameter
	inc rsi
	jmp .find_parameter

.has_parameter:
	lea rsi, [rel input]
	mov al, ' '
	call os_string_tokenize
	mov [param_list], rdi
	jmp .parameter_done

.no_parameter:
	mov qword [param_list], 0

.parameter_done:
	lea rsi, [rel input]
	lea rdi, [rel command]
	call os_string_copy

	; --------------------------------------------------------------
	; Convert command to uppercase
	; --------------------------------------------------------------

	lea rax, [rel input]
	call os_string_uppercase

	lea rsi, [rel input]

	; --------------------------------------------------------------
	; Reject parameters for commands that do not use them
	; --------------------------------------------------------------

	cmp qword [param_list], 0
	je .no_parameter_check

	lea rsi, [rel input]
	lea rdi, [rel exit_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel cls_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel list_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel time_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel cal_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel ver_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel about_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel gmuinfo_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel shutdown_string]
	call os_string_compare
	jc total_fail

	lea rsi, [rel input]
	lea rdi, [rel printer_string]
	call os_string_compare
	jc total_fail

.no_parameter_check:

	; EXIT
	lea rsi, [rel input]
	lea rdi, [rel exit_string]
	call os_string_compare
	jc exit

	; HELP
	lea rdi, [rel help_string]
	call os_string_compare
	jc help_command

	; GMUINFO
	lea rsi, [rel input]
	lea rdi, [rel gmuinfo_string]
	call os_string_compare
	jc print_gmuinfo

	; ABOUT
	lea rsi, [rel input]
	lea rdi, [rel about_string]
	call os_string_compare
	jc print_about

	; CAL
	lea rdi, [rel cal_string]
	call os_string_compare
	jc print_cal

	; CLS
	lea rdi, [rel cls_string]
	call os_string_compare
	jc clear_screen

	; DIR
	lea rdi, [rel dir_string]
	call os_string_compare
	jc list_directory

	; VER
	lea rdi, [rel ver_string]
	call os_string_compare
	jc print_ver

	; TIME
	lea rdi, [rel time_string]
	call os_string_compare
	jc print_time

	; DATE
	lea rdi, [rel date_string]
	call os_string_compare
	jc date_command

	; PBL
	lea rdi, [rel pbl_string]
	call os_string_compare
	jc pbl_command

	; CAT
	lea rdi, [rel cat_string]
	call os_string_compare
	jc cat_file

	; DEL
	lea rdi, [rel del_string]
	call os_string_compare
	jc del_file

	; COPY
	lea rdi, [rel copy_string]
	call os_string_compare
	jc copy_file

	; REN
	lea rdi, [rel ren_string]
	call os_string_compare
	jc ren_file

	; SIZE
	lea rdi, [rel size_string]
	call os_string_compare
	jc size_file

	; LS
	lea rdi, [rel list_string]
	call os_string_compare
	jc dir_list

	; PASTE
	lea rdi, [rel paste_string]
	call os_string_compare
	jc paste_file

	; SHUTDOWN
	lea rdi, [rel shutdown_string]
	call os_string_compare
	jc shutdown_command

	; CC  (C compiler and runner, see ccomp.asm)
	lea rdi, [rel cc_string]
	call os_string_compare
	jc cc_command

	; C  (C editor, see cedit.asm)
	lea rdi, [rel c_string]
	call os_string_compare
	jc c_command

	; PRINTER / PRINT  (USB printer, see prn.asm)
	lea rdi, [rel printer_string]
	call os_string_compare
	jc printer_command
	lea rdi, [rel print_string]
	call os_string_compare
	jc print_command

	; --------------------------------------------------------------
	; If the user hasn't entered any of the above commands, then we
	; need to check for an executable file -- .BIN or .BAS, and the
	; user may not have provided the extension
	; --------------------------------------------------------------

	lea rax, [rel command]
	call os_string_uppercase
	call os_string_length

	; If the user has entered, say, MYPROG.BIN, we can just run it.

	lea rsi, [rel command]
	add rsi, rax
	sub rsi, 4

	lea rdi, [rel bin_extension]
	call os_string_compare
	jc bin_file

	lea rdi, [rel bas_extension]
	call os_string_compare
	jc bas_file

	lea rdi, [rel pcx_extension]
	call os_string_compare
	jc total_fail

	jmp no_extension


bin_file:
	lea rax, [rel command]
	mov rcx, [prog_area]
	call os_load_file
	jc total_fail

execute_bin:
	lea rsi, [rel command]
	lea rdi, [rel kern_file_string]
	mov ecx, 6
	call os_string_strincmp
	jc no_kernel_allowed

	; 64-bit programs start with the 8-byte signature 'GMU64BIN'
	mov rsi, [prog_area]
	mov rax, 'GMU64BIN'
	cmp [rsi], rax
	jne not_64bit_program

	xor eax, eax				; Clear all registers
	xor ebx, ebx
	xor ecx, ecx
	xor edx, edx
	mov rsi, [param_list]			; Pass the parameter string (or 0)
	lea rdi, [rel vec_table]		; Pass the system call table
	mov r8, [prog_area]
	add r8, 8				; Code starts after the signature
	call r8

	jmp get_cmd


not_64bit_program:
	lea rsi, [rel not64_msg]
	call os_print_string
	jmp get_cmd


bas_file:
	lea rax, [rel command]
	mov rcx, [prog_area]
	call os_load_file
	jc total_fail
	lea rsi, [rel basic_msg]		; BASIC interpreter is still 16-bit only
	call os_print_string
	jmp get_cmd


no_extension:
	lea rax, [rel command]
	call os_string_length

	lea rsi, [rel command]
	add rsi, rax				; SI now points to end of command

	mov byte [rsi], '.'
	mov byte [rsi + 1], 'B'
	mov byte [rsi + 2], 'I'
	mov byte [rsi + 3], 'N'
	mov byte [rsi + 4], 0

	lea rax, [rel command]
	mov rcx, [prog_area]
	call os_load_file
	jc try_bas_ext

	jmp execute_bin


try_bas_ext:
	lea rax, [rel command]
	call os_string_length

	lea rsi, [rel command]
	add rsi, rax
	sub rsi, 4

	mov byte [rsi], '.'
	mov byte [rsi + 1], 'B'
	mov byte [rsi + 2], 'A'
	mov byte [rsi + 3], 'S'
	mov byte [rsi + 4], 0

	jmp bas_file


total_fail:
	lea rsi, [rel invalid_msg]
	call os_print_string
	jmp get_cmd


no_kernel_allowed:
	lea rsi, [rel kern_warn_msg]
	call os_print_string
	jmp get_cmd


pbl_command:
	lea rsi, [rel pbl_msg]
	call os_print_string
	jmp get_cmd


; ==================================================================
; HELP COMMAND
;
; HELP, HELP DIR, HELP LS, HELP COPY, HELP REN, HELP DEL, HELP CAT,
; HELP SIZE, HELP CLS, HELP TIME, HELP DATE, HELP VER, HELP ABOUT,
; HELP CAL, HELP HELP, HELP EXIT
; ==================================================================

help_command:
	cmp qword [param_list], 0
	je print_help

	mov rsi, [param_list]
	mov rax, rsi
	call os_string_uppercase

	mov rsi, [param_list]
	lea rdi, [rel dir_string]
	call os_string_compare
	jc help_dir

	mov rsi, [param_list]
	lea rdi, [rel list_string]
	call os_string_compare
	jc help_ls

	mov rsi, [param_list]
	lea rdi, [rel copy_string]
	call os_string_compare
	jc help_copy

	mov rsi, [param_list]
	lea rdi, [rel ren_string]
	call os_string_compare
	jc help_ren

	mov rsi, [param_list]
	lea rdi, [rel del_string]
	call os_string_compare
	jc help_del

	mov rsi, [param_list]
	lea rdi, [rel cat_string]
	call os_string_compare
	jc help_cat

	mov rsi, [param_list]
	lea rdi, [rel size_string]
	call os_string_compare
	jc help_size

	mov rsi, [param_list]
	lea rdi, [rel cls_string]
	call os_string_compare
	jc help_cls

	mov rsi, [param_list]
	lea rdi, [rel time_string]
	call os_string_compare
	jc help_time

	mov rsi, [param_list]
	lea rdi, [rel date_string]
	call os_string_compare
	jc help_date

	mov rsi, [param_list]
	lea rdi, [rel ver_string]
	call os_string_compare
	jc help_ver

	mov rsi, [param_list]
	lea rdi, [rel about_string]
	call os_string_compare
	jc help_about

	mov rsi, [param_list]
	lea rdi, [rel cal_string]
	call os_string_compare
	jc help_cal

	mov rsi, [param_list]
	lea rdi, [rel help_string]
	call os_string_compare
	jc help_help

	mov rsi, [param_list]
	lea rdi, [rel exit_string]
	call os_string_compare
	jc help_exit

	mov rsi, [param_list]
	lea rdi, [rel paste_string]
	call os_string_compare
	jc help_paste

	mov rsi, [param_list]
	lea rdi, [rel shutdown_string]
	call os_string_compare
	jc help_shutdown

	lea rsi, [rel help_not_found]
	call os_print_string
	jmp get_cmd

%macro HELPITEM 2
%1:
	lea rsi, [rel %2]
	call os_print_string
	jmp get_cmd
%endmacro

	HELPITEM help_dir, dir_help_text
	HELPITEM help_ls, ls_help_text
	HELPITEM help_copy, copy_help_text
	HELPITEM help_ren, ren_help_text
	HELPITEM help_del, del_help_text
	HELPITEM help_cat, cat_help_text
	HELPITEM help_size, size_help_text
	HELPITEM help_cls, cls_help_text
	HELPITEM help_time, time_help_text
	HELPITEM help_date, date_help_text
	HELPITEM help_ver, ver_help_text
	HELPITEM help_about, about_help_text
	HELPITEM help_cal, cal_help_text
	HELPITEM help_help, help_help_text
	HELPITEM help_exit, exit_help_text
	HELPITEM help_paste, paste_help_text
	HELPITEM help_shutdown, shutdown_help_text


; ==================================================================
; SHUTDOWN -- power the computer off (UEFI ResetSystem)
; ==================================================================

shutdown_command:
	lea rsi, [rel shutdown_msg]
	call os_print_string
	mov ecx, 2				; EfiResetShutdown
	xor edx, edx				; EFI_SUCCESS
	xor r8d, r8d
	xor r9d, r9d
	mov rax, [run_svc]
	mov rax, [rax + RT_RESETSYSTEM]
	call efi_thunk
.hang:						; only reached if the firmware refuses
	hlt
	jmp .hang


; ==================================================================
; DATE COMMAND
;
; DATE              - show current date
; DATE CHECK        - ask for a date and validate it
; DATE DD/MM/YYYY   - validate the given date
; ==================================================================

date_command:
	cmp qword [param_list], 0
	je print_date

	mov rsi, [param_list]
	mov rax, rsi
	call os_string_uppercase

	mov rsi, [param_list]
	lea rdi, [rel date_check_string]
	call os_string_compare
	jc date_check_input

	mov rsi, [param_list]
	call date_validate
	jmp get_cmd


date_check_input:
	lea rsi, [rel date_prompt]
	call os_print_string

	lea rax, [rel date_input]
	mov ebx, 15
	call os_input_string
	call os_print_newline

	lea rsi, [rel date_input]
	call date_validate
	jmp get_cmd


; ==================================================================
; DATE VALIDATION  (format DD/MM/YYYY)
; Checks: only numbers, correct '/', day range, month range, year,
; leap year, maximum days in month
; ==================================================================

date_validate:
	mov byte [date_error], 0

	call date_two_digits			; DAY
	jc date_invalid_input
	mov [date_day], eax

	cmp byte [rsi], '/'
	jne date_invalid_input
	inc rsi

	call date_two_digits			; MONTH
	jc date_invalid_input
	mov [date_month], eax

	cmp byte [rsi], '/'
	jne date_invalid_input
	inc rsi

	call date_two_digits			; YEAR - first two digits
	jc date_invalid_input
	imul eax, eax, 100
	mov [date_year], eax
	call date_two_digits			; YEAR - last two digits
	jc date_invalid_input
	add [date_year], eax

	cmp byte [rsi], 0			; No extra characters
	jne date_invalid_input

	cmp dword [date_year], 1		; YEAR >= 1
	jb date_invalid

	cmp dword [date_month], 1		; MONTH 1-12
	jb date_invalid
	cmp dword [date_month], 12
	ja date_invalid

	cmp dword [date_day], 1			; DAY >= 1
	jb date_invalid

	; LEAP YEAR: divisible by 400, or divisible by 4 and not by 100

	mov dword [date_leap], 0

	mov eax, [date_year]
	xor edx, edx
	mov ebx, 400
	div ebx
	cmp edx, 0
	je date_is_leap

	mov eax, [date_year]
	xor edx, edx
	mov ebx, 100
	div ebx
	cmp edx, 0
	je date_not_leap

	mov eax, [date_year]
	xor edx, edx
	mov ebx, 4
	div ebx
	cmp edx, 0
	je date_is_leap
	jmp date_not_leap

date_is_leap:
	mov dword [date_leap], 1
	jmp date_check_month

date_not_leap:
	mov dword [date_leap], 0
	jmp date_check_month

date_check_month:				; FIND MAXIMUM DAYS OF MONTH
	cmp dword [date_month], 2		; February
	je date_february
	cmp dword [date_month], 4		; April
	je date_30_days
	cmp dword [date_month], 6		; June
	je date_30_days
	cmp dword [date_month], 9		; September
	je date_30_days
	cmp dword [date_month], 11		; November
	je date_30_days
	mov dword [date_max_day], 31		; Remaining months = 31 days
	jmp date_check_day

date_30_days:
	mov dword [date_max_day], 30
	jmp date_check_day

date_february:
	cmp dword [date_leap], 1
	je date_feb_29
	mov dword [date_max_day], 28
	jmp date_check_day

date_feb_29:
	mov dword [date_max_day], 29

date_check_day:
	mov eax, [date_day]
	cmp eax, [date_max_day]
	ja date_invalid

	lea rsi, [rel date_valid_msg]		; Valid date
	call os_print_string

	cmp dword [date_leap], 1
	je date_print_leap

	lea rsi, [rel date_not_leap_msg]
	call os_print_string
	ret

date_print_leap:
	lea rsi, [rel date_leap_msg]
	call os_print_string
	ret


; date_two_digits -- read two decimal digits at [RSI] into EAX
; OUT: carry set if either character is not a digit; RSI advanced by 2

date_two_digits:
	mov al, [rsi]
	call date_is_digit
	jc .bad
	sub al, '0'
	movzx edx, al
	imul edx, edx, 10
	inc rsi
	mov al, [rsi]
	call date_is_digit
	jc .bad
	sub al, '0'
	movzx eax, al
	add eax, edx
	inc rsi
	clc
	ret
.bad:
	stc
	ret

date_is_digit:
	cmp al, '0'
	jb date_not_digit
	cmp al, '9'
	ja date_not_digit
	clc
	ret

date_not_digit:
	stc
	ret

date_invalid_input:
	lea rsi, [rel date_input_error_msg]
	call os_print_string
	ret

date_invalid:
	lea rsi, [rel date_invalid_msg]
	call os_print_string
	ret


; ==================================================================
; SIMPLE INFORMATION COMMANDS
; ==================================================================

print_help:
	lea rsi, [rel help_text]
	call os_print_string
	jmp get_cmd

print_gmuinfo:
	lea rsi, [rel gmuinfo_text]
	call os_print_string
	jmp get_cmd

print_about:
	lea rsi, [rel about_text]
	call os_print_string
	jmp get_cmd

clear_screen:
	call os_clear_screen
	jmp get_cmd

print_time:
	lea rbx, [rel tmp_string]
	call os_get_time_string
	mov rsi, rbx
	call os_print_string
	call os_print_newline
	jmp get_cmd

print_date:
	lea rbx, [rel tmp_string]
	call os_get_date_string
	mov rsi, rbx
	call os_print_string
	call os_print_newline
	jmp get_cmd

print_cal:
	lea rsi, [rel cal_text]
	call os_print_string

	lea rbx, [rel tmp_string]
	call os_get_date_string
	mov rsi, rbx
	call os_print_string
	call os_print_newline

	lea rbx, [rel tmp_string]
	call os_get_time_string
	mov rsi, rbx
	call os_print_string
	call os_print_newline
	jmp get_cmd

print_ver:
	lea rsi, [rel version_msg]
	call os_print_string
	jmp get_cmd

kern_warning:
	lea rsi, [rel kern_warn_msg]
	call os_print_string
	jmp get_cmd


; ==================================================================
; DIR  -- DIR lists all files; DIR *.EXT lists files with that extension
; ==================================================================

list_directory:
	cmp qword [param_list], 0		; DIR with no parameter -> full file list
	je .show_all

	; DIR with a wildcard parameter: DIR *.BIN, DIR *.TXT, DIR *.BAS ...
	mov rax, [param_list]
	call os_string_uppercase

	mov rsi, [param_list]
	lea rdi, [rel usb_string]		; DIR USB: files of the other pendrives
	call os_string_compare
	jc dir_usb_command

	mov rsi, [param_list]

	; The supported filter format is exactly "*." + 3 characters.
	cmp byte [rsi], '*'
	jne .invalid_filter
	cmp byte [rsi + 1], '.'
	jne .invalid_filter

	mov al, [rsi + 2]			; Copy the requested 3-character extension.
	cmp al, 0
	je .invalid_filter
	mov [dir_filter_ext], al

	mov al, [rsi + 3]
	cmp al, 0
	je .invalid_filter
	mov [dir_filter_ext + 1], al

	mov al, [rsi + 4]
	cmp al, 0
	je .invalid_filter
	mov [dir_filter_ext + 2], al

	cmp byte [rsi + 5], 0			; There must be no fourth extension character.
	jne .invalid_filter

	jmp list_filtered_directory

.invalid_filter:
	jmp total_fail

.show_all:
	mov dword [dir_cols], 4
	mov dword [dir_colw], 20
	xor ecx, ecx
	lea rax, [rel dirlist]
	mov byte [list_dirs], 1			; DIR also shows folders as [NAME]
	call os_get_file_list
	mov byte [list_dirs], 0

show_grid:
	lea rsi, [rel dirlist]
	xor ecx, ecx

.set_column:
	call os_get_cursor_pos
	push rdx
	mov eax, ecx
	xor edx, edx
	div dword [dir_cols]
	mov eax, edx
	imul eax, [dir_colw]
	mov r8d, eax
	add r8d, [dir_colw]
	dec r8d
	mov [dir_limit], r8b
	pop rdx
	mov dl, al
	call os_move_cursor

.next_char:
	lodsb
	cmp al, ','
	je .next_filename
	cmp al, 0
	je .done
	push rax				; truncate names that don't fit the column
	call os_get_cursor_pos
	cmp dl, [dir_limit]
	pop rax
	jae .next_char
	call os_putc
	jmp .next_char

.next_filename:
	inc ecx
	mov eax, ecx
	xor edx, edx
	div dword [dir_cols]
	test edx, edx
	jne .set_column
	call os_print_newline
	jmp .set_column

.done:
	call os_print_newline
	jmp dir_select


; DIR USB -- list the files of all other USB drives (names shown as USBn:file)

dir_usb_command:
	call disk_scan_usb
	cmp dword [vol_count], 1
	jne .have_usb
	lea rsi, [rel no_usb_msg]
	call os_print_string
	jmp get_cmd
.have_usb:
	lea rdi, [rel dirlist]
	mov byte [rdi], 0
	mov dword [usb_i], 1
.vol:
	mov eax, [usb_i]
	cmp eax, [vol_count]
	jae .built
	lea rcx, [rel vol_root]
	mov rcx, [rcx + rax*8]
	mov [list_root], rcx
	mov byte [list_dirs], 1
	lea rax, [rel usb_tmp]
	call os_get_file_list			; (keeps RDI)
	mov byte [list_dirs], 0
	lea rsi, [rel usb_tmp]
	cmp byte [rsi], 0
	je .next_vol
.entry:
	lea rax, [rel dirlist + 15000]
	cmp rdi, rax
	jae .built
	lea rax, [rel dirlist]
	cmp rdi, rax				; comma between entries
	je .no_comma
	mov byte [rdi], ','
	inc rdi
.no_comma:
	mov byte [rdi], 'U'			; prefix USBn:
	mov byte [rdi + 1], 'S'
	mov byte [rdi + 2], 'B'
	mov eax, [usb_i]
	add al, '0'
	mov [rdi + 3], al
	mov byte [rdi + 4], ':'
	add rdi, 5
.copy:
	lodsb
	test al, al
	jz .next_vol
	cmp al, ','
	je .entry
	mov [rdi], al
	inc rdi
	jmp .copy
.next_vol:
	inc dword [usb_i]
	jmp .vol
.built:
	mov byte [rdi], 0
	mov rcx, [root_dir]
	mov [list_root], rcx
	lea rsi, [rel dirlist]
	cmp byte [rsi], 0
	jne .show
	lea rsi, [rel usb_empty_msg]
	call os_print_string
	jmp get_cmd
.show:
	mov eax, [vol_count]
	dec eax
	add al, '0'
	mov [usb_found_msg + 12], al
	lea rsi, [rel usb_found_msg]
	call os_print_string
	mov dword [dir_cols], 3
	mov dword [dir_colw], 26
	jmp show_grid


; dir_select -- after DIR: pick a file with the arrow keys
; (Left/Right = previous/next, Up/Down = row above/below, Enter = pick
;  the file for COPY, Esc = skip)

dir_select:
	lea rsi, [rel dirlist]
	cmp byte [rsi], 0
	je get_cmd
	mov ebx, 1
.count:
	lodsb
	test al, al
	jz .counted
	cmp al, ','
	jne .count
	inc ebx
	jmp .count
.counted:
	mov [dir_n], ebx
	mov eax, ebx
	add eax, [dir_cols]
	dec eax
	xor edx, edx
	div dword [dir_cols]
	cmp eax, 20				; too many to select on one screen
	ja get_cmd
	mov [dir_rows], eax
	lea rsi, [rel dir_select_hint]
	call os_print_string
	call os_get_cursor_pos
	movzx eax, dh
	sub eax, [dir_rows]
	dec eax
	jl get_cmd
	mov [dir_start], eax
	mov dword [dir_idx], 0
	xor eax, eax
	mov bl, 0x70
	call dir_draw_item
.key:
	call os_wait_for_key
	cmp al, 27
	je .esc
	cmp al, 13
	je .enter
	mov ecx, [dir_idx]
	mov edx, ecx
	cmp ah, 4Bh				; Left
	jne .n1
	test edx, edx
	jz .key
	dec edx
	jmp .move
.n1:
	cmp ah, 4Dh				; Right
	jne .n2
	inc edx
	cmp edx, [dir_n]
	jae .key
	jmp .move
.n2:
	cmp ah, 48h				; Up
	jne .n3
	sub edx, [dir_cols]
	jb .key
	jmp .move
.n3:
	cmp ah, 50h				; Down
	jne .key
	add edx, [dir_cols]
	cmp edx, [dir_n]
	jae .key
.move:
	mov eax, ecx				; un-highlight the old one
	mov bl, 0x07
	call dir_draw_item
	mov [dir_idx], edx
	mov eax, edx				; highlight the new one
	mov bl, 0x70
	call dir_draw_item
	jmp .key
.enter:
	mov r8d, [dir_idx]
	lea rdi, [rel sel_name]
	call dir_copy_name
	call .cursor_below
	lea rax, [rel sel_name]
	jmp clip_copy				; Enter = copy to clipboard, ready for PASTE
.esc:
	mov eax, [dir_idx]
	mov bl, 0x07
	call dir_draw_item
	call .cursor_below
	jmp get_cmd
.cursor_below:
	mov eax, [dir_start]
	add eax, [dir_rows]
	inc eax
	mov dh, al
	xor edx, edx
	mov dh, al
	call os_move_cursor
	ret


; dir_draw_item -- redraw file number EAX of the DIR grid in colour BL
dir_draw_item:
	pushall
	movzx r10d, bl
	mov r8d, eax
	lea rdi, [rel sel_tmp]
	call dir_copy_name
	mov eax, [dir_colw]
	dec eax
	lea rsi, [rel sel_tmp]
	mov byte [rsi + rax], 0
	mov eax, r8d
	xor edx, edx
	div dword [dir_cols]
	push rax				; row offset
	mov eax, edx
	imul eax, [dir_colw]
	mov r9d, eax
	pop rax
	add eax, [dir_start]
	mov dh, al
	mov dl, r9b
	call os_move_cursor
	mov al, [cur_attr]
	push rax
	mov [cur_attr], r10b
	lea rsi, [rel sel_tmp]
	call os_print_string
	pop rax
	mov [cur_attr], al
	popall
	ret


; dir_copy_name -- copy name number R8D of dirlist to [RDI]
dir_copy_name:
	lea rsi, [rel dirlist]
	mov ecx, r8d
.skip:
	test ecx, ecx
	jz .copy
.s2:
	lodsb
	cmp al, ','
	jne .s2
	dec ecx
	jmp .skip
.copy:
	lodsb
	cmp al, ','
	je .end
	test al, al
	jz .end
	stosb
	jmp .copy
.end:
	mov byte [rdi], 0
	ret


; DIR *.<EXT> -- lists files whose extension matches dir_filter_ext

list_filtered_directory:
	call disk_read_root_dir
	jc .read_fail

	lea rdi, [rel dir_buffer]
	mov ebx, [dir_count]
	xor edx, edx				; EDX = number of matching files

.next_entry:
	test ebx, ebx				; End of directory?
	jz .finished

	mov al, [rdi + REC_ATTR]
	cmp al, 0Fh				; Skip long-file-name entries
	je .skip_entry
	test al, 018h				; Skip volume labels and directories
	jnz .skip_entry

	; Find the extension: text after the last '.' in the name
	lea rsi, [rdi + REC_NAME]
	xor ecx, ecx				; RCX = position of last '.', 0 = none
	xor eax, eax
.scan:
	cmp byte [rsi + rax], 0
	je .scan_done
	cmp byte [rsi + rax], '.'
	jne .scan_next
	lea rcx, [rax + 1]
.scan_next:
	inc eax
	jmp .scan
.scan_done:
	test ecx, ecx
	jz .skip_entry
	lea rsi, [rsi + rcx]

	; Compare (case-insensitive) with the requested extension
	push rdx
	lea r8, [rel dir_filter_ext]
	xor ecx, ecx
.cmpext:
	mov al, [rsi + rcx]
	cmp al, 'a'
	jb .up
	cmp al, 'z'
	ja .up
	sub al, 20h
.up:
	cmp al, [r8 + rcx]
	jne .nomatch
	inc ecx
	cmp ecx, 3
	jb .cmpext
	cmp byte [rsi + 3], 0			; extension must be exactly 3 chars
	jne .nomatch
	pop rdx

	call type_name				; Print the matching filename.
	call os_print_newline
	inc edx
	jmp .skip_entry
.nomatch:
	pop rdx

.skip_entry:
	add rdi, REC_SIZE
	dec ebx
	jmp .next_entry

.finished:
	test edx, edx
	jnz .done
	lea rsi, [rel no_filtered_files_msg]
	call os_print_string
	call os_print_newline
.done:
	jmp get_cmd

.read_fail:
	lea rsi, [rel dir_filter_readfail_msg]
	call os_print_string
	call os_print_newline
	jmp get_cmd


; ==================================================================
; CAT, DEL, SIZE, COPY, REN
; ==================================================================

cat_file:
	cmp qword [param_list], 0
	je .no_name
	mov rsi, [param_list]
	call os_string_parse
	cmp rax, 0
	jne .filename_provided
.no_name:
	lea rsi, [rel nofilename_msg]
	call os_print_string
	jmp get_cmd

.filename_provided:
	call os_file_exists			; Check if file exists
	jc .not_found

	mov rcx, [prog_area]
	call os_load_file
	jc .not_found
	mov [file_size], rbx

	cmp rbx, 0
	je get_cmd

	mov rsi, [prog_area]

.loop:
	lodsb
	cmp al, 0Ah				; Newline in the file: also go to column 0
	jne .not_newline
	call os_get_cursor_pos
	mov dl, 0
	call os_move_cursor
	jmp .print
.not_newline:
	cmp al, 0Dh
	je .print
	cmp al, 09h
	je .print
	cmp al, ' '				; Make binary junk safe to show
	jb .dot
	cmp al, '~'
	jbe .print
.dot:
	mov al, '.'
.print:
	call os_putc
	dec rbx
	jnz .loop
	jmp get_cmd

.not_found:
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd


del_file:
	cmp qword [param_list], 0
	je .no_name
	mov rsi, [param_list]
	call os_string_parse
	cmp rax, 0
	jne .filename_provided
.no_name:
	lea rsi, [rel nofilename_msg]
	call os_print_string
	jmp get_cmd

.filename_provided:
	call os_remove_file
	jc .failure

	lea rsi, [rel .success_msg]
	call os_print_string
	mov rsi, rax
	call os_print_string
	call os_print_newline
	jmp get_cmd

.failure:
	lea rsi, [rel .failure_msg]
	call os_print_string
	jmp get_cmd

	.success_msg	db 'Deleted file: ', 0
	.failure_msg	db 'Could not delete file - does not exist or write protected', 13, 10, 0


size_file:
	cmp qword [param_list], 0
	je .no_name
	mov rsi, [param_list]
	call os_string_parse
	cmp rax, 0
	jne .filename_provided
.no_name:
	lea rsi, [rel nofilename_msg]
	call os_print_string
	jmp get_cmd

.filename_provided:
	call os_get_file_size
	jc .failure

	lea rsi, [rel .size_msg]
	call os_print_string

	mov rax, rbx
	call os_int_to_string
	mov rsi, rax
	call os_print_string
	call os_print_newline
	jmp get_cmd

.failure:
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd

	.size_msg	db 'Size (in bytes) is: ', 0


copy_file:
	cmp qword [param_list], 0
	jne .have_param
	cmp byte [sel_name], 0			; COPY alone: use the file picked in DIR
	je .no_name
	lea rax, [rel sel_name]
	jmp clip_copy
.have_param:
	mov rsi, [param_list]
	call os_string_parse
	mov [.tmp], rbx

	cmp rbx, 0
	je clip_copy				; COPY <file>: put it on the clipboard
	jmp .filename_provided
.no_name:
	lea rsi, [rel nofilename_msg]
	call os_print_string
	jmp get_cmd

.filename_provided:
	mov rdx, rax				; Store first filename temporarily
	mov rax, rbx				; Get destination
	call os_file_exists
	jnc .already_exists

	mov rax, rdx				; Get first filename back
	mov rcx, [prog_area]			; Where to load the file
	call os_load_file
	jc .load_fail

	mov rcx, rbx				; File size
	mov rbx, [prog_area]			; Location of data
	mov rax, [.tmp]				; Get destination
	call os_write_file
	jc .write_fail

	lea rsi, [rel .success_msg]
	call os_print_string
	jmp get_cmd

.load_fail:
	cmp byte [drive_missing], 0
	jne nodrive_error
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd

.write_fail:
	cmp byte [drive_missing], 0
	jne nodrive_error
	lea rsi, [rel writefail_msg]
	call os_print_string
	jmp get_cmd

.already_exists:
	lea rsi, [rel exists_msg]
	call os_print_string
	jmp get_cmd

	.tmp		dq 0
	.success_msg	db 'File copied successfully', 13, 10, 0


; clip_copy -- remember a file (name in RAX) on the clipboard
clip_copy:
	mov [cc_name], rax
	mov rsi, rax
	mov al, '['				; folders are shown as [NAME]
	call os_find_char_in_string
	test rax, rax
	jz .is_file
	lea rsi, [rel folder_copy_msg]
	call os_print_string
	jmp get_cmd
.is_file:
	mov rax, [cc_name]
	mov rsi, rax
	mov qword [clip_size], 0
	mov byte [clip_name], 0
	lea rcx, [rel clip_buf]
	call os_load_file
	jc .not_found
	mov [clip_size], rbx
	lea rdi, [rel clip_name]
	call os_string_copy
	lea rsi, [rel clip_msg1]
	call os_print_string
	lea rsi, [rel clip_name]
	call os_print_string
	lea rsi, [rel clip_msg2]
	call os_print_string
	jmp get_cmd
.not_found:
	lea rsi, [rel notfound_msg]
	call os_print_string
	jmp get_cmd


; PASTE [name] -- write the clipboard file; default name is COPY_<name>.
; A path such as EFI/BOOT/X.TXT puts the file in another folder.
paste_file:
	cmp byte [clip_name], 0
	je .empty
	lea rbx, [rel clip_name]		; RBX = clipboard name without USBn:
	cmp byte [rbx + 4], ':'
	jne .plain_name
	add rbx, 5
.plain_name:
	cmp qword [param_list], 0
	jne .have_dest
	lea rax, [rel clip_name]		; From another pendrive: same name on boot drive
	cmp byte [rax + 4], ':'
	jne .make_copy_name
	mov rsi, rbx
	lea rdi, [rel paste_name]
	call os_string_copy
	lea rax, [rel paste_name]
	call os_file_exists
	jc .use_plain
.make_copy_name:
	lea rax, [rel .prefix]
	lea rcx, [rel paste_name]
	call os_string_join
.use_plain:
	lea rax, [rel paste_name]
	jmp .go
.have_dest:
	mov rsi, [param_list]
	call os_string_parse
	mov [.tmp], rax
	call os_string_length
	mov rsi, [.tmp]
	test rax, rax
	jz .go_tmp
	cmp byte [rsi + rax - 1], ':'		; 'USB1:' alone = same name on that drive
	jne .go_tmp
	lea rbx, [rel clip_name]		; (os_string_parse trashed RBX)
	cmp byte [rbx + 4], ':'
	jne .join_plain
	add rbx, 5
.join_plain:
	mov rax, rsi
	lea rcx, [rel paste_name]
	call os_string_join
	lea rax, [rel paste_name]
	jmp .go
.go_tmp:
	mov rax, [.tmp]
.go:
	mov [.tmp], rax
	call os_file_exists
	jnc .already_exists
	mov rax, [.tmp]
	lea rbx, [rel clip_buf]
	mov rcx, [clip_size]
	call os_write_file
	jc .write_fail
	lea rsi, [rel .success_msg]
	call os_print_string
	jmp get_cmd
.empty:
	lea rsi, [rel .empty_msg]
	call os_print_string
	jmp get_cmd
.write_fail:
	cmp byte [drive_missing], 0
	jne nodrive_error
	lea rsi, [rel writefail_msg]
	call os_print_string
	jmp get_cmd
.already_exists:
	lea rsi, [rel exists_msg]
	call os_print_string
	jmp get_cmd

	.tmp		dq 0
	.prefix		db 'COPY_', 0
	.success_msg	db 'File pasted successfully', 13, 10, 0
	.empty_msg	db 'Clipboard is empty - use COPY <file> first', 13, 10, 0


ren_file:
	cmp qword [param_list], 0
	je .no_name
	mov rsi, [param_list]
	call os_string_parse
	cmp rbx, 0
	jne .filename_provided
.no_name:
	lea rsi, [rel nofilename_msg]
	call os_print_string
	jmp get_cmd

.filename_provided:
	mov rcx, rax				; Save old name
	mov rax, rbx				; Check new filename doesn't already exist
	call os_file_exists
	jnc .already_exists

	mov rax, rcx
	call os_rename_file
	jc .failure

	lea rsi, [rel .success_msg]
	call os_print_string
	jmp get_cmd

.already_exists:
	lea rsi, [rel exists_msg]
	call os_print_string
	jmp get_cmd

.failure:
	lea rsi, [rel .failure_msg]
	call os_print_string
	jmp get_cmd

	.success_msg	db 'File renamed successfully', 13, 10, 0
	.failure_msg	db 'Operation failed - file not found or invalid filename', 13, 10, 0


; ==================================================================
; LS -- directory listing with attributes, dates, times and sizes
; (20 entries per page; ESC leaves, any other key shows the next page)
; ==================================================================

dir_list:
	pushall
	call disk_read_root_dir
	jnc .cont1

	lea rsi, [rel .readfail_msg]
	call os_print_string
	jmp short .done

.cont1:
	lea rdi, [rel dir_buffer]
	mov ebx, [dir_count]

.outer_loop:
	lea rsi, [rel .header_msg]
	call os_print_string
	mov ecx, 20				; 20 entries per page

.page_loop:
	test ebx, ebx				; End of directory?
	jz .done

	mov al, [rdi + REC_ATTR]
	cmp al, 0x0f				; Skip long file name entries
	je .next_entry
	test al, 0x18				; Skip directories and volume labels
	jnz .next_entry

	mov al, [rdi + REC_NAME]
	cmp al, 0x5e
	je .next_entry
	cmp al, ' '
	jle .next_entry
	cmp al, '~'
	jae .next_entry
	cmp al, '.'
	je .next_entry

	call dir_entry_dump
	dec ecx

.next_entry:
	add rdi, REC_SIZE
	dec ebx
	test ecx, ecx
	jnz .page_loop

.cont2:
	lea rsi, [rel .footer_msg]
	call os_print_string
	call os_wait_for_key
	cmp al, 27				; ESC key
	je .done
	call os_clear_screen
	jmp .outer_loop

.done:
	call os_print_newline
	popall
	jmp get_cmd

.readfail_msg:
	db 'Unable to read disk directory', 0
.header_msg:
	db '    Name       attr      created             last write              bytes', 13, 10, 0
.footer_msg:
	db 'Press key for next page', 0


; ------------------------------------------------------------------
; dir_entry_dump -- print one directory record   (RDI -> record)

%macro ATTRCHAR 2
	mov al, '.'
	test bh, %1
	jz %%no
	mov al, %2
%%no:
	call os_putc
%endmacro

dir_entry_dump:
	pushall
	call type_name				; Name

	call os_get_cursor_pos
	mov dl, 15
	call os_move_cursor

	mov bh, [rdi + REC_ATTR]
	ATTRCHAR 0x80, '*'
	ATTRCHAR 0x40, '*'
	ATTRCHAR 0x20, 'A'			; Archive
	ATTRCHAR 0x10, 'D'			; Directory
	ATTRCHAR 0x08, 'V'			; Volume label
	ATTRCHAR 0x04, 'S'			; System
	ATTRCHAR 0x02, 'H'			; Hidden
	ATTRCHAR 0x01, 'R'			; Read-only

	call os_print_space
	call os_print_space

	movzx edx, word [rdi + REC_CDATE]	; Created date
	call type_date
	call os_print_space
	movzx edx, word [rdi + REC_CTIME]	; Created time
	call type_time

	call os_print_space
	call os_print_space

	movzx edx, word [rdi + REC_MDATE]	; Last write date
	call type_date
	call os_print_space
	movzx edx, word [rdi + REC_MTIME]	; Last write time
	call type_time

	call os_print_space
	call os_print_space

	mov eax, [rdi + REC_FSIZE]		; File size, right aligned in 10 columns
	push rdi
	mov ebx, 10
	lea rdi, [rel .number]
	call os_long_int_to_string
	mov rsi, rdi
	mov rax, rdi
	call os_string_length
	neg rax
	add rax, 10
	mov rcx, rax
	jle .size_left
.loop2:
	call os_print_space
	dec rcx
	jnz .loop2
.size_left:
	call os_print_string
	call os_print_newline
	pop rdi
	popall
	ret

.number:
	times 24 db 0


; ------------------------------------------------------------------
; type_time -- print FAT time (DX) as hh:mm:ss

type_time:
	pushall
	movzx eax, dx				; Hours
	shr eax, 11
	call .print2
	mov al, ':'
	call os_putc
	movzx eax, dx				; Minutes
	shr eax, 5
	and eax, 0x3f
	call .print2
	mov al, ':'
	call os_putc
	movzx eax, dx				; Seconds
	and eax, 0x1f
	shl eax, 1
	call .print2
	popall
	ret

.print2:					; EAX = 0-99, two digits with leading 0
	cmp eax, 10
	jae .digits
	push rax
	mov al, '0'
	call os_putc
	pop rax
.digits:
	call os_int_to_string
	mov rsi, rax
	call os_print_string
	ret


; ------------------------------------------------------------------
; type_date -- print FAT date (DX) as mm/dd/yy

type_date:
	pushall
	movzx eax, dx
	shr eax, 5
	and eax, 0x0F				; Month
	cmp al, 1
	jl .mon_00
	cmp al, 12
	jbe .month
.mon_00:
	mov al, 0
.month:
	call type_time.print2
	mov al, '/'
	call os_putc

	movzx eax, dx				; Day
	and eax, 0x1F
	call type_time.print2
	mov al, '/'
	call os_putc

	movzx eax, dx				; Year (two digits)
	shr eax, 9
	and eax, 0x3F
	add eax, 1980
	xor edx, edx
	mov ebx, 100
	div ebx
	mov eax, edx
	call type_time.print2
	popall
	ret


; ------------------------------------------------------------------
; type_name -- print the file name of a record (RDI -> record)

type_name:
	push rsi
	lea rsi, [rdi + REC_NAME]
	call os_print_string
	pop rsi
	ret


; ------------------------------------------------------------------
; hist_add -- store the command line in `input` in the history
; (16 entries of 64 bytes; consecutive duplicates are not stored)

hist_add:
	pushall
	mov eax, [hist_count]
	test eax, eax
	jz .add
	dec eax					; Same as the previous command?
	shl eax, 6
	lea rdi, [rel hist_buf]
	add rdi, rax
	lea rsi, [rel input]
	call os_string_compare
	jc .done
	mov eax, [hist_count]
.add:
	cmp eax, 16				; Full? Drop the oldest entry
	jb .store
	lea rdi, [rel hist_buf]
	lea rsi, [rdi + 64]
	mov ecx, 15 * 64
	rep movsb
	mov eax, 15
	mov [hist_count], eax
.store:
	shl eax, 6
	lea rdi, [rel hist_buf]
	add rdi, rax
	lea rsi, [rel input]
	call os_string_copy
	inc dword [hist_count]
.done:
	popall
	ret


; ------------------------------------------------------------------
; EXIT -- return to the interface selection screen

exit:
	ret


; ==================================================================
; DATA
; ==================================================================

input			times 64 db 0
command			times 80 db 0
dirlist			times 16384 db 0
tmp_string		times 32 db 0
file_size		dq 0
param_list		dq 0

; DATE variables
date_day		dd 0
date_month		dd 0
date_year		dd 0
date_max_day		dd 0
date_leap		dd 0
date_error		db 0
date_input		times 16 db 0

; Extensions
bin_extension		db '.BIN', 0
bas_extension		db '.BAS', 0
pcx_extension		db '.PCX', 0

; Prompt
prompt			db 'PAVAN M PATIL> ', 0

; Full help
help_text:
	db 'GMU OS HELP', 13, 10
	db '========================================', 13, 10
	db 'DIR   - List files; DIR *.<EXT> filters; DIR USB lists other pendrives', 13, 10
	db 'LS    - List files', 13, 10
	db 'COPY  - COPY a b copies a file; COPY a puts it on the clipboard', 13, 10
	db 'PASTE - Paste the clipboard file (PASTE [newname])', 13, 10
	db '        Other pendrive files: USB1:NAME (CAT, SIZE, COPY, PASTE, DEL, REN)', 13, 10
	db 'REN   - Rename a file', 13, 10
	db 'DEL   - Delete a file', 13, 10
	db 'CAT   - Display file contents', 13, 10
	db 'SIZE  - Show file size', 13, 10
	db 'CLS   - Clear screen', 13, 10
	db 'HELP  - Show help information', 13, 10
	db 'ABOUT - Show information about GMU OS', 13, 10
	db 'GMUINFO - Show GMU OS information', 13, 10
	db 'TIME  - Show current time', 13, 10
	db 'DATE  - Show current date', 13, 10
	db 'CAL   - Show current date and time', 13, 10
	db 'VER   - Show OS version', 13, 10
	db 'Run a compatible program by typing its .BIN filename', 13, 10
	db 'EXIT  - Exit command line', 13, 10
	db 'SHUTDOWN - Power off the computer', 13, 10
	db 'C     - Type a C program (Enter runs it, Shift+Enter = new line)', 13, 10
	db 'CC    - Compile and run a C file: CC FILE.C', 13, 10
	db 'PRINTER - Detect the USB printer       PRINT [file] - Print a file', 13, 10
	db '========================================', 13, 10
	db 0

pbl_string		db 'PBL', 0
pbl_msg			db 13, 10
			db '===== PBL OS =====', 13, 10
			db 'Project : Problem Based Learning', 13, 10
			db 'Author  : Pavan M Patil', 13, 10
			db 'College : GM University Davangere', 13, 10
			db 'Year    : 2026', 13, 10
			db '===================', 13, 10, 0

; Individual help
dir_help_text:		db 'DIR  - List files; DIR *.<EXT> filters by extension; DIR USB lists the other pendrives (files are named USB1:NAME ...)', 13, 10, 0
ls_help_text:		db 'LS   - List files', 13, 10, 0
copy_help_text:		db 'COPY - COPY a b copies a file; COPY a (or COPY after DIR selection) puts it on the clipboard', 13, 10, 0
paste_help_text:	db 'PASTE - Paste clipboard file: PASTE [newname]; PASTE USB1: puts it on pendrive 1; PASTE DOCS/X.TXT uses a folder', 13, 10, 0
shutdown_help_text:	db 'SHUTDOWN - Power off the computer', 13, 10, 0
ren_help_text:		db 'REN  - Rename a file', 13, 10, 0
del_help_text:		db 'DEL  - Delete a file', 13, 10, 0
cat_help_text:		db 'CAT  - Display file contents', 13, 10, 0
size_help_text:		db 'SIZE - Show file size', 13, 10, 0
cls_help_text:		db 'CLS  - Clear screen', 13, 10, 0
time_help_text:		db 'TIME - Show current time', 13, 10, 0
date_help_text:		db 'DATE - Show current date', 13, 10, 0
ver_help_text:		db 'VER  - Show OS version', 13, 10, 0
about_help_text:	db 'ABOUT- Show information about GMU OS', 13, 10, 0
cal_help_text:		db 'CAL  - Show current date and time', 13, 10, 0
help_help_text:		db 'HELP - Show help information', 13, 10, 0
exit_help_text:		db 'EXIT - Exit command line', 13, 10, 0
help_not_found:		db 'No help available for this command', 13, 10, 0

; Other text
gmuinfo_text:
	db 13, 10
	db '========================================', 13, 10
	db '          GMU OS INFORMATION', 13, 10
	db '========================================', 13, 10
	db 'Operating System : GMU OS', 13, 10
	db 'University       : GM University Davangere', 13, 10
	db 'Project          : Operating System Learning Edition', 13, 10
	db 'Based on         : MikeOS', 13, 10
	db 'Architecture     : 64-bit x86-64 (UEFI)', 13, 10
	db 'Year             : 2026', 13, 10
	db 'Developer        : Pavan M Patil', 13, 10
	db '========================================', 13, 10, 0

about_text:
	db 'GMU OS - GM University', 13, 10
	db 'PBL Learning Edition', 13, 10
	db 'CSE Team Project', 13, 10, 0

cal_text:		db 'Current Date/Time:', 13, 10, 0
invalid_msg:		db 'No such command or program', 13, 10, 0
nofilename_msg:		db 'No filename or not enough filenames', 13, 10, 0
notfound_msg:		db 'File not found', 13, 10, 0
writefail_msg:		db 'Could not write file. Write protected or invalid filename?', 13, 10, 0
exists_msg:		db 'Target file already exists!', 13, 10, 0
finished_msg:		db '>>> Program finished, press any key to continue...', 0
version_msg:		db 'GMU OS ', MIKEOS_VER, ' (64-bit UEFI)', 13, 10, 0
not64_msg:		db 'Not a 64-bit GMU OS program (16-bit MikeOS .BIN files cannot run here)', 13, 10, 0
basic_msg:		db 'The BASIC interpreter is not available in the 64-bit edition yet', 13, 10, 0

; Command strings
exit_string:		db 'EXIT', 0
help_string:		db 'HELP', 0
about_string:		db 'ABOUT', 0
gmuinfo_string:		db 'GMUINFO', 0
cls_string:		db 'CLS', 0
dir_string:		db 'DIR', 0

; Three-character extension used by DIR *.<EXT>
dir_filter_ext:		db 'BIN', 0
no_filtered_files_msg:	db 'No matching files found', 0
dir_filter_readfail_msg: db 'Unable to read disk directory', 0
time_string:		db 'TIME', 0
date_string:		db 'DATE', 0
cal_string:		db 'CAL', 0
ver_string:		db 'VER', 0
cat_string:		db 'CAT', 0
del_string:		db 'DEL', 0
ren_string:		db 'REN', 0
copy_string:		db 'COPY', 0
size_string:		db 'SIZE', 0
list_string:		db 'LS', 0
paste_string:		db 'PASTE', 0
usb_string:		db 'USB', 0
no_usb_msg:		db 'No other USB drive found (plug one in and try again)', 13, 10, 0
usb_empty_msg:		db 'The other USB drive(s) contain no files', 13, 10, 0
usb_found_msg:		db 'USB drives: N  - use names like USB1:FILE.TXT with COPY, CAT, DEL ...', 13, 10, 0
shutdown_string:	db 'SHUTDOWN', 0
printer_string:	db 'PRINTER', 0
print_string:	db 'PRINT', 0

nodrive_msg:		db 'That USB drive is not plugged in - run DIR USB to see the drives', 13, 10, 0
folder_copy_msg:	db 'Folders cannot be copied yet - pick a file', 13, 10, 0
cc_name			dq 0

nodrive_error:
	lea rsi, [rel nodrive_msg]
	call os_print_string
	jmp get_cmd

shutdown_msg:		db 'Shutting down...', 13, 10, 0
selected_msg:		db 'Selected: ', 0
clip_msg1:		db 'Copied to clipboard: ', 0
clip_msg2:		db ' (use PASTE [newname])', 13, 10, 0
dir_select_hint:	db 'Arrow keys: select file   Enter: copy to clipboard   Esc: skip', 13, 10, 0

sel_name		times 64 db 0
sel_tmp			times 64 db 0
clip_name		times 64 db 0
paste_name		times 80 db 0
clip_size		dq 0
dir_n			dd 0
dir_rows		dd 0
dir_start		dd 0
dir_idx			dd 0

; DATE command strings
date_check_string:	db 'CHECK', 0
date_prompt:		db 'Enter date as DD/MM/YYYY (example: 29/02/2024): ', 0
date_input_error_msg:	db 'Invalid input. Use DD/MM/YYYY with numbers only.', 13, 10, 0
date_invalid_msg:	db 'Invalid date', 13, 10, 0
date_valid_msg:		db 'Valid date - ', 0
date_leap_msg:		db 'Leap year', 13, 10, 0
date_not_leap_msg:	db 'Not a leap year', 13, 10, 0

; Kernel
kern_file_string:	db 'KERNEL', 0
kern_warn_msg:		db 'Cannot execute kernel file!', 13, 10, 0

; ==================================================================
