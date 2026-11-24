; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2019 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition: GM University, Davanagere, 2026
;
; DISK HANDLING ROUTINES  (64-bit UEFI version)
;
; The BIOS INT 13h / FAT12 floppy driver is replaced by the UEFI
; EFI_SIMPLE_FILE_SYSTEM_PROTOCOL: the volume the OS was booted from
; (the USB stick / the QEMU disk image) is used as the file system.
; The firmware understands FAT12/16/32, so the same sticks work on
; any PC.  Only the root directory is used, like in MikeOS.
;
; Register interface of the os_*_file routines is unchanged, except
; that pointers and sizes are now 64-bit (RAX = filename string,
; RBX = size/buffer, RCX = size/destination).
; ==================================================================


; ------------------------------------------------------------------
; disk_mount -- (internal) find the boot volume and open its root
; OUT: root_dir set (0 if no usable file system)

disk_mount:
	pushall
	mov qword [root_dir], 0
	mov rcx, [image_handle]			; Our own loaded-image protocol
	lea rdx, [rel guid_loaded_image]
	lea r8, [rel li_ptr]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jnz .fail
	mov rax, [li_ptr]
	mov rcx, [rax + 24]			; DeviceHandle we were loaded from
	mov [boot_dev], rcx
	lea rdx, [rel guid_sfs]
	lea r8, [rel sfs_ptr]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jnz .fail
	mov rcx, [sfs_ptr]
	lea rdx, [rel root_dir]
	mov rax, [rcx + 8]			; OpenVolume
	call efi_thunk
	test rax, rax
	jnz .zero
	mov rax, [root_dir]
	mov [list_root], rax
	jmp .done
.zero:
	mov qword [root_dir], 0
.fail:
.done:
	popall
	ret


; ------------------------------------------------------------------
; vol_resolve -- (internal) pick the volume named by a file name prefix
;   USB1: USB2: ... = other USB drives, BOOT: = the boot drive,
;   no prefix = the boot drive
; IN: RSI = name; OUT: RSI = name without prefix, RCX = root dir (0 = no such drive)
; Preserves everything except RAX, RCX, RSI

vol_resolve:
	mov byte [drive_missing], 0
	cmp byte [rsi + 4], ':'
	jne .plain
	mov al, [rsi]
	and al, 0DFh
	cmp al, 'B'
	je .boot
	cmp al, 'U'
	jne .plain
	mov al, [rsi + 1]
	and al, 0DFh
	cmp al, 'S'
	jne .plain
	mov al, [rsi + 2]
	and al, 0DFh
	cmp al, 'B'
	jne .plain
	movzx eax, byte [rsi + 3]
	sub eax, '0'
	jz .bad
	cmp eax, 9
	ja .bad
	cmp eax, [vol_count]
	jb .have
	push rax				; Not known yet: maybe plugged in later
	call disk_scan_usb
	pop rax
	cmp eax, [vol_count]
	jae .bad
.have:
	lea rcx, [rel vol_root]
	mov rcx, [rcx + rax*8]
	add rsi, 5
	ret
.boot:
	mov al, [rsi + 1]
	and al, 0DFh
	cmp al, 'O'
	jne .plain
	mov al, [rsi + 2]
	and al, 0DFh
	cmp al, 'O'
	jne .plain
	mov al, [rsi + 3]
	and al, 0DFh
	cmp al, 'T'
	jne .plain
	add rsi, 5
.plain:
	mov rcx, [root_dir]
	ret
.bad:
	mov byte [drive_missing], 1		; no such USB drive plugged in
	xor ecx, ecx
	ret


; ------------------------------------------------------------------
; disk_scan_usb -- (internal) find every USB drive except the one we
; booted from.  vol_root[1..vol_count-1] = their root directories.

disk_scan_usb:
	pushall
	mov esi, 1				; Close the roots of the previous scan
.close:
	cmp esi, [vol_count]
	jae .closed
	lea rcx, [rel vol_root]
	mov rcx, [rcx + rsi*8]
	mov rax, [rcx + FILE_CLOSE]
	call efi_thunk
	inc esi
	jmp .close
.closed:
	mov dword [vol_count], 1

	; The firmware only connects the boot drive by default, so ask it to
	; connect every device (this makes other pendrives show up as volumes)
	xor ecx, ecx				; AllHandles
	xor edx, edx
	xor r8d, r8d
	lea r9, [rel sc_count]
	lea r10, [rel sc_buf]
	BCALL 312				; LocateHandleBuffer
	test rax, rax
	jnz .connected
	mov rbx, [sc_buf]
	xor esi, esi
.connect:
	cmp rsi, [sc_count]
	jae .connect_done
	mov rcx, [rbx + rsi*8]
	xor edx, edx
	xor r8d, r8d
	mov r9d, 1				; Recursive
	BCALL 264				; ConnectController
	inc rsi
	jmp .connect
.connect_done:
	mov rcx, rbx
	BCALL 72				; FreePool
.connected:

	mov ecx, 2				; ByProtocol
	lea rdx, [rel guid_sfs]
	xor r8d, r8d
	lea r9, [rel sc_count]
	lea r10, [rel sc_buf]
	BCALL 312				; LocateHandleBuffer
	test rax, rax
	jnz .done
	mov rbx, [sc_buf]
	xor esi, esi
.next:
	cmp rsi, [sc_count]
	jae .free
	cmp dword [vol_count], 8
	jae .free
	mov rdi, [rbx + rsi*8]			; candidate volume handle
	cmp rdi, [boot_dev]			; not the boot drive itself
	je .skip
	mov rcx, rdi				; Only USB drives: look for a USB
	lea rdx, [rel guid_devpath]		; node in the device path
	lea r8, [rel sc_dp]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jnz .skip
	mov rax, [sc_dp]
.walk:
	movzx ecx, byte [rax]			; node type
	cmp ecx, 7Fh				; end of path: not USB
	je .skip
	cmp ecx, 3				; messaging node?
	jne .advance
	movzx ecx, byte [rax + 1]
	cmp ecx, 5				; USB
	je .is_usb
	cmp ecx, 0Fh				; USB class
	je .is_usb
	cmp ecx, 10h				; USB WWID
	je .is_usb
.advance:
	movzx ecx, word [rax + 2]
	test ecx, ecx
	jz .skip
	add rax, rcx
	jmp .walk
.is_usb:
	mov rcx, rdi
	lea rdx, [rel guid_sfs]
	lea r8, [rel sfs_tmp]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jnz .skip
	mov rcx, [sfs_tmp]
	lea rdx, [rel sc_root]
	mov rax, [rcx + 8]			; OpenVolume
	call efi_thunk
	test rax, rax
	jnz .skip
	mov eax, [vol_count]
	lea rcx, [rel vol_root]
	mov rdx, [sc_root]
	mov [rcx + rax*8], rdx
	inc dword [vol_count]
.skip:
	inc rsi
	jmp .next
.free:
	mov rcx, [sc_buf]
	BCALL 72				; FreePool
.done:
	popall
	ret


; ------------------------------------------------------------------
; ascii_to_wide -- (internal) ASCII string -> UCS-2 string
; IN: RSI = ASCII, RDI = destination; OUT: RDI = just past the terminator

ascii_to_wide:
	push rax
	push rcx
	xor ecx, ecx
.next:
	lodsb
	movzx eax, al
	cmp eax, '/'				; Accept / as folder separator
	jne .store
	mov eax, '\'
.store:
	mov [rdi], ax
	add rdi, 2
	test eax, eax
	jz .done
	inc ecx
	cmp ecx, 250
	jb .next
	mov word [rdi], 0
	add rdi, 2
.done:
	pop rcx
	pop rax
	ret


; ------------------------------------------------------------------
; disk_open -- (internal) open a file in the root directory
; IN: RSI = ASCII file name, R9 = open mode
; OUT: RAX = EFI_STATUS (0 = ok), handle in file_handle

disk_open:
	push rsi
	push rdi
	call vol_resolve			; Handle a USBn: / BOOT: prefix
	test rcx, rcx
	jz .fail
	cmp byte [rsi], 0			; Empty names are not files
	je .fail
	lea rdi, [rel wname]
	call ascii_to_wide			; (keeps RCX)
	lea rdx, [rel file_handle]
	lea r8, [rel wname]
	xor r10d, r10d
	mov rax, [rcx + FILE_OPEN]
	call efi_thunk
	pop rdi
	pop rsi
	ret
.fail:
	mov rax, -1
	pop rdi
	pop rsi
	ret


; ------------------------------------------------------------------
; disk_close -- (internal) close file_handle

disk_close:
	mov rcx, [file_handle]
	mov rax, [rcx + FILE_CLOSE]
	call efi_thunk
	ret


; ------------------------------------------------------------------
; disk_getinfo -- (internal) fetch EFI_FILE_INFO of file_handle into info_buf
; OUT: RAX = EFI_STATUS

disk_getinfo:
	mov rcx, [file_handle]
	lea rdx, [rel guid_file_info]
	mov qword [info_size], 1024
	lea r8, [rel info_size]
	lea r9, [rel info_buf]
	mov rax, [rcx + FILE_GETINFO]
	call efi_thunk
	ret


; ------------------------------------------------------------------
; efi_time_to_fat -- (internal) EFI_TIME -> FAT date/time words
; IN: RSI = EFI_TIME; OUT: AX = FAT date, DX = FAT time

efi_time_to_fat:
	push rcx
	movzx eax, word [rsi]			; Year
	sub eax, 1980
	jge .y1
	xor eax, eax
.y1:
	cmp eax, 127
	jbe .y2
	mov eax, 127
.y2:
	shl eax, 9
	movzx ecx, byte [rsi + 2]		; Month
	shl ecx, 5
	or eax, ecx
	movzx ecx, byte [rsi + 3]		; Day
	or eax, ecx
	movzx edx, byte [rsi + 4]		; Hour
	shl edx, 11
	movzx ecx, byte [rsi + 5]		; Minute
	shl ecx, 5
	or edx, ecx
	movzx ecx, byte [rsi + 6]		; Second / 2
	shr ecx, 1
	or edx, ecx
	pop rcx
	ret


; ------------------------------------------------------------------
; disk_read_root_dir -- (internal) read the root directory into dir_buffer
; as 64-byte records (see uefi.inc); dir_count = number of records
; OUT: carry set on error

disk_read_root_dir:
	pushall
	mov dword [dir_count], 0
	mov rcx, [list_root]
	test rcx, rcx
	jz .fail
	xor edx, edx				; Rewind the directory
	mov rax, [rcx + FILE_SETPOS]
	call efi_thunk
.next:
	mov rcx, [list_root]
	mov qword [info_size], 1024
	lea rdx, [rel info_size]
	lea r8, [rel info_buf]
	mov rax, [rcx + FILE_READ]
	call efi_thunk
	test rax, rax
	jnz .fail
	cmp qword [info_size], 0		; End of directory
	je .done
	mov eax, [dir_count]
	cmp eax, MAX_RECS
	jae .done
	shl eax, 6
	lea rdi, [rel dir_buffer]
	add rdi, rax				; RDI -> record
	push rdi
	xor eax, eax
	mov ecx, 8
	rep stosq				; Clear the record
	pop rdi
	lea rsi, [rel info_buf + 80]		; File name (UCS-2)
	xor ecx, ecx
.name:
	movzx eax, word [rsi + rcx*2]
	test eax, eax
	jz .name_done
	cmp eax, 7Eh
	jbe .name_ok
	mov eax, '?'
.name_ok:
	mov [rdi + rcx], al
	inc ecx
	cmp ecx, 31
	jb .name
.name_done:
	mov al, [info_buf + 72]			; Attributes (low byte = DOS attributes)
	mov [rdi + REC_ATTR], al
	mov eax, [info_buf + 8]
	mov [rdi + REC_FSIZE], eax
	lea rsi, [rel info_buf + 24]		; CreateTime
	call efi_time_to_fat
	mov [rdi + REC_CDATE], ax
	mov [rdi + REC_CTIME], dx
	lea rsi, [rel info_buf + 56]		; ModificationTime
	call efi_time_to_fat
	mov [rdi + REC_MDATE], ax
	mov [rdi + REC_MTIME], dx
	inc dword [dir_count]
	jmp .next
.done:
	popall
	clc
	ret
.fail:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_get_file_list -- Generate comma-separated string of files on volume
; IN: AX = location to store zero-terminated filename string
; OUT: nothing (carry set on error)

os_get_file_list:
	pushall
	mov rdi, rax
	mov byte [rdi], 0
	call disk_read_root_dir
	jc .error
	lea rsi, [rel dir_buffer]
	mov ebx, [dir_count]
	xor ecx, ecx				; Entries stored so far
	mov r8, rdi
	add r8, 3800				; Stay inside a 4K buffer
.entry:
	test ebx, ebx
	jz .finished
	mov al, [rsi + REC_ATTR]
	cmp al, 0Fh				; LFN marker, skip it
	je .skip
	xor r9d, r9d				; R9 = 1 for a folder
	test al, 10h
	jz .not_dir
	cmp byte [list_dirs], 0			; folders only when DIR asks for them
	je .skip
	mov r9d, 1
	jmp .check_name
.not_dir:
	test al, 08h				; Volume label?
	jnz .skip
.check_name:
	mov al, [rsi]				; First name char
	cmp al, ' '
	jle .skip
	cmp al, '~'
	ja .skip
	test r9d, r9d
	jz .name_ok
	cmp al, '.'				; skip . and ..
	je .skip
	cmp al, '$'				; $RECYCLE.BIN and similar system folders
	je .skip
	cmp al, 'S'				; System Volume Information
	jne .name_ok
	cmp byte [rsi + 1], 'y'
	je .skip
.name_ok:
	cmp rdi, r8
	jae .finished
	test ecx, ecx				; 1st entry? no comma
	jz .name
	mov byte [rdi], ','
	inc rdi
.name:
	inc ecx
	push rsi
	test r9d, r9d
	jz .copy
	mov byte [rdi], '['
	inc rdi
.copy:
	lodsb
	test al, al
	jz .copied
	mov [rdi], al
	inc rdi
	jmp .copy
.copied:
	test r9d, r9d
	jz .no_close
	mov byte [rdi], ']'
	inc rdi
.no_close:
	pop rsi
.skip:
	add rsi, REC_SIZE
	dec ebx
	jmp .entry
.finished:
	mov byte [rdi], 0
	popall
	clc
	ret
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_load_file -- Load file into RAM
; IN: AX = location of filename, CX = location in RAM to load file
; OUT: BX = file size (in bytes), carry set if file not found

os_load_file:
	pushall
	mov [lf_dest], rcx
	mov rsi, rax
	mov r9d, EFI_FILE_READ
	call disk_open
	test rax, rax
	jnz .error
	call disk_getinfo
	test rax, rax
	jnz .error_close
	test byte [info_buf + 72], 10h		; A directory is not a file
	jnz .error_close
	mov rax, [info_buf + 8]			; FileSize
	cmp rax, FILE_MAX
	ja .error_close
	mov [lf_size], rax
	mov rcx, [file_handle]
	lea rdx, [rel lf_size]
	mov r8, [lf_dest]
	mov rax, [rcx + FILE_READ]
	call efi_thunk
	mov [lf_status], rax
	call disk_close
	cmp qword [lf_status], 0
	jne .error
	popall
	mov rbx, [lf_size]
	clc
	ret
.error_close:
	call disk_close
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_write_file -- Save (max 1MB) file to the volume
; IN: AX = filename, BX = data location, CX = bytes to write
; OUT: Carry clear if OK, set if failure (write protected, bad name...)

os_write_file:
	pushall
	mov [wf_name], rax
	mov [wf_buf], rbx
	mov [wf_size], rcx
	mov rsi, rax
	mov r9d, EFI_FILE_RW
	call disk_open
	test rax, rax				; Does it already exist?
	jnz .create
	mov rcx, [file_handle]			; Yes: remove the old copy first
	mov rax, [rcx + FILE_DELETE]
	call efi_thunk
	test rax, rax
	jnz .error
.create:
	mov rsi, [wf_name]
	mov r9, EFI_FILE_CREATE_RW
	call disk_open
	test rax, rax
	jnz .error
	mov rcx, [file_handle]
	lea rdx, [rel wf_size]
	mov r8, [wf_buf]
	mov rax, [rcx + FILE_WRITE]
	call efi_thunk
	mov [wf_status], rax
	call disk_close				; Closing flushes the data
	cmp qword [wf_status], 0
	jne .error
	popall
	clc
	ret
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_file_exists -- Check for presence of file on the volume
; IN: AX = filename location; OUT: carry clear if found, set if not

os_file_exists:
	pushall
	mov rsi, rax
	mov r9d, EFI_FILE_READ
	call disk_open
	test rax, rax
	jnz .notfound
	call disk_close
	popall
	clc
	ret
.notfound:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_create_file -- Creates a new 0-byte file on the volume
; IN: AX = location of filename; OUT: carry clear if OK, set if failure

os_create_file:
	pushall
	mov rsi, rax
	mov r9, EFI_FILE_CREATE_RW
	call disk_open
	test rax, rax
	jnz .error
	call disk_close
	popall
	clc
	ret
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_remove_file -- Deletes the specified file from the volume
; IN: AX = location of filename to remove; OUT: carry clear if OK

os_remove_file:
	pushall
	mov rsi, rax
	mov r9d, EFI_FILE_RW
	call disk_open
	test rax, rax
	jnz .error
	mov rcx, [file_handle]
	mov rax, [rcx + FILE_DELETE]		; Delete() also closes the handle
	call efi_thunk
	test rax, rax
	jnz .error
	popall
	clc
	ret
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_rename_file -- Change the name of a file on the volume
; IN: AX = filename to change, BX = new filename (zero-terminated)
; OUT: carry clear on success, set on failure

os_rename_file:
	pushall
	mov [rn_new], rbx
	mov rsi, rax
	mov r9d, EFI_FILE_RW
	call disk_open
	test rax, rax
	jnz .error
	call disk_getinfo
	test rax, rax
	jnz .error_close
	mov rsi, [rn_new]
	cmp byte [rsi], 0
	je .error_close
	lea rdi, [rel info_buf + 80]		; Put the new name into FILE_INFO
	call ascii_to_wide
	lea rax, [rel info_buf]
	sub rdi, rax
	mov [info_buf], rdi			; New structure size
	mov rcx, [file_handle]
	lea rdx, [rel guid_file_info]
	mov r8, rdi
	lea r9, [rel info_buf]
	mov rax, [rcx + FILE_SETINFO]
	call efi_thunk
	mov [lf_status], rax
	call disk_close
	cmp qword [lf_status], 0
	jne .error
	popall
	clc
	ret
.error_close:
	call disk_close
.error:
	popall
	stc
	ret


; ------------------------------------------------------------------
; os_get_file_size -- Get file size information for specified file
; IN: AX = filename; OUT: BX = file size in bytes (carry set if not found)

os_get_file_size:
	pushall
	mov rsi, rax
	mov r9d, EFI_FILE_READ
	call disk_open
	test rax, rax
	jnz .error
	call disk_getinfo
	mov [lf_status], rax
	mov rax, [info_buf + 8]
	mov [lf_size], rax
	call disk_close
	cmp qword [lf_status], 0
	jne .error
	popall
	mov rbx, [lf_size]
	clc
	ret
.error:
	popall
	stc
	ret


; ==================================================================
