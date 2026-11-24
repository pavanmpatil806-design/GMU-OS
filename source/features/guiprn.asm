; ==================================================================
; GMU OS 64 -- desktop: Printer window and file picker
; ==================================================================

ID_PRN_PRINT	equ 70
ID_PRN_REFRESH	equ 71
ID_PRN_CLOSE	equ 72
ID_PICK_PRINT	equ 73
ID_PICK_PREV	equ 74
ID_PICK_NEXT	equ 75
ID_PICK_BACK	equ 76
ID_PICK_ROW	equ 80			; 80..89 = ten rows per page

PICK_MAX	equ 64			; files in the picker
PICK_REC	equ 40			; bytes per entry
PICK_PAGE	equ 10

; ------------------------------------------------------------------
; gui_prn_open -- open the Printer window (looks for the printer first)
gui_prn_open:
	pushall
	call prn_scan_full
	mov byte [prn_win], 1
	mov dword [hover_id], -1
	call gui_scene
	popall
	ret

; ------------------------------------------------------------------
; gui_prn_click -- a click on one of the printer window controls (EAX = id)
gui_prn_click:
	pushall
	mov ebx, eax
	cmp ebx, ID_PRN_CLOSE
	jne .n1
	mov byte [prn_win], 0
	mov dword [hover_id], -1
	call gui_scene
	jmp .out
.n1:
	cmp ebx, ID_PRN_REFRESH
	jne .n2
	call prn_scan_full
	call gui_scene
	jmp .out
.n2:
	cmp ebx, ID_PRN_PRINT
	jne .n3
	call gui_pick_build
	mov byte [prn_win], 2
	mov dword [pick_sel], -1
	mov dword [pick_page], 0
	mov dword [hover_id], -1
	call gui_scene
	jmp .out
.n3:
	cmp ebx, ID_PICK_BACK
	jne .n4
	mov byte [prn_win], 1
	mov dword [hover_id], -1
	call gui_scene
	jmp .out
.n4:
	cmp ebx, ID_PICK_PREV
	jne .n5
	cmp dword [pick_page], 0
	je .out
	dec dword [pick_page]
	mov dword [pick_sel], -1
	call gui_scene
	jmp .out
.n5:
	cmp ebx, ID_PICK_NEXT
	jne .n6
	mov eax, [pick_page]
	inc eax
	imul eax, PICK_PAGE
	cmp eax, [pick_n]
	jae .out
	inc dword [pick_page]
	mov dword [pick_sel], -1
	call gui_scene
	jmp .out
.n6:
	cmp ebx, ID_PICK_PRINT
	jne .n7
	cmp dword [pick_sel], 0
	jl .out
	call gui_do_print
	jmp .out
.n7:
	cmp ebx, ID_PICK_ROW
	jb .out
	cmp ebx, ID_PICK_ROW + PICK_PAGE - 1
	ja .out
	mov eax, [pick_page]
	imul eax, PICK_PAGE
	lea ecx, [rbx - ID_PICK_ROW]
	add eax, ecx
	cmp eax, [pick_n]
	jae .out
	mov [pick_sel], eax
	call gui_scene
.out:
	popall
	ret

; gui_do_print -- print the file selected in the picker
gui_do_print:
	pushall
	lea rsi, [rel app_names + 12*20]
	lea rdx, [rel s_sending]
	lea r8, [rel s_empty]
	lea r9, [rel s_empty]
	call gui_show_msg			; (redraws, so the user sees it before we block)
	mov eax, [pick_sel]
	imul eax, PICK_REC
	lea rcx, [rel pick_list]
	add rax, rcx
	mov [pick_name], rax
	call prn_print_file
	jc .failed
	lea rsi, [rel app_names + 12*20]
	lea rdx, [rel s_sent]
	mov r8, [pick_name]
	lea r9, [rel s_checkprn]
	call gui_show_msg
	jmp .out
.failed:
	lea rsi, [rel app_names + 12*20]
	lea rdx, [rel s_pfailed]
	mov r8, [prn_err]
	lea r9, [rel s_empty]
	call gui_show_msg
.out:
	popall
	ret

; gui_pick_build -- list the files of the boot drive and of the other USB drives
gui_pick_build:
	pushall
	mov dword [pick_n], 0
	mov rcx, [root_dir]
	mov [list_root], rcx
	xor r8d, r8d				; drive prefix number (0 = none)
	call .add_volume
	mov dword [usb_i], 1
.vol:
	mov eax, [usb_i]
	cmp eax, [vol_count]
	jae .done
	lea rcx, [rel vol_root]
	mov rcx, [rcx + rax*8]
	mov [list_root], rcx
	mov r8d, eax
	call .add_volume
	inc dword [usb_i]
	jmp .vol
.done:
	mov rcx, [root_dir]
	mov [list_root], rcx
	popall
	ret

.add_volume:				; R8D = drive number; reads list_root into the picker
	pushall
	mov [pb_drive], r8d
	call disk_read_root_dir
	jc .av_out
	lea rsi, [rel dir_buffer]
	mov ebx, [dir_count]
.av_l:
	test ebx, ebx
	jz .av_out
	cmp dword [pick_n], PICK_MAX
	jae .av_out
	test byte [rsi + REC_ATTR], 18h		; skip folders and volume labels
	jnz .av_next
	mov al, [rsi]
	cmp al, ' '
	jbe .av_next
	cmp al, '.'
	je .av_next
	mov eax, [pick_n]
	imul eax, PICK_REC
	lea rdi, [rel pick_list]
	add rdi, rax
	mov eax, [pb_drive]
	test eax, eax
	jz .av_copy
	mov byte [rdi], 'U'
	mov byte [rdi + 1], 'S'
	mov byte [rdi + 2], 'B'
	add al, '0'
	mov [rdi + 3], al
	mov byte [rdi + 4], ':'
	add rdi, 5
.av_copy:
	xor ecx, ecx
.av_c:
	mov al, [rsi + rcx]
	test al, al
	jz .av_end
	cmp ecx, 30
	jae .av_end
	mov [rdi + rcx], al
	inc ecx
	jmp .av_c
.av_end:
	mov byte [rdi + rcx], 0
	inc dword [pick_n]
.av_next:
	add rsi, REC_SIZE
	dec ebx
	jmp .av_l
.av_out:
	popall
	ret

; ------------------------------------------------------------------
; gui_button -- EAX=x EBX=y ECX=w EDX=h RSI=label R8D=id R9D=enabled(0/1)
; (an enabled button is registered as a hotspot)
gui_button:
	pushall
	mov [bt_x], eax
	mov [bt_y], ebx
	mov [bt_w], ecx
	mov [bt_h], edx
	mov [bt_label], rsi
	mov [bt_en], r9d
	mov r10d, 0x3A4666			; disabled colour
	test r9d, r9d
	jz .draw
	call hot_add
	mov r10d, 0x2F7BFF
	cmp r8d, [hover_id]
	jne .draw
	mov r10d, 0x5599FF
.draw:
	mov r8d, r10d
	mov r9d, 256
	mov r10d, 7
	mov eax, [bt_x]
	mov ebx, [bt_y]
	mov ecx, [bt_w]
	mov edx, [bt_h]
	call gfx_rrect
	FONT font_bold
	mov dword [txt_alpha], 256
	mov rsi, [bt_label]
	call gfx_text_width
	mov ecx, [bt_w]
	sub ecx, eax
	shr ecx, 1
	add ecx, [bt_x]
	mov eax, ecx
	mov ebx, [bt_h]
	sub ebx, 19
	shr ebx, 1
	add ebx, [bt_y]
	mov r8d, 0xFFFFFF
	cmp dword [bt_en], 0
	jne .t
	mov r8d, 0x8C99B8
.t:
	mov rsi, [bt_label]
	call gfx_text
	popall
	ret

; ------------------------------------------------------------------
; gui_draw_prnwin -- the Printer window (prn_win = 1) or the file picker (prn_win = 2)
gui_draw_prnwin:
	pushall
	xor eax, eax				; dim the desktop
	xor ebx, ebx
	mov ecx, [gW]
	mov edx, [gH]
	xor r8d, r8d
	mov r9d, 100
	xor r10d, r10d
	call gfx_rrect
	cmp byte [prn_win], 2
	je .picker

	; ---------------- Printer window
	mov dword [pw_w], 520
	mov dword [pw_h], 280
	call .place
	mov eax, [pw_x]
	mov ebx, [pw_y]
	mov ecx, [pw_w]
	mov edx, [pw_h]
	call .panel
	lea rsi, [rel icons48 + 8*GFX_ICON48]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 18
	mov ecx, 48
	call gfx_icon
	FONT font_big
	mov dword [txt_alpha], 256
	lea rsi, [rel app_names + 12*20]
	mov eax, [pw_x]
	add eax, 88
	mov ebx, [pw_y]
	add ebx, 28
	mov r8d, 0xFFFFFF
	call gfx_text
	FONT font_ui
	cmp byte [prn_found], 0
	je .noprinter
	lea rax, [rel s_connected]
	lea rbx, [rel prn_name]
	lea rcx, [rel prn_line]
	call os_string_join
	lea rsi, [rel prn_line]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 92
	mov r8d, 0xFFFFFF
	call gfx_text
	call prn_lang_text
	mov rbx, rsi
	lea rax, [rel s_language]
	lea rcx, [rel prn_line]
	call os_string_join
	lea rsi, [rel prn_line]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 118
	mov r8d, 0xD6E2F8
	call gfx_text
	lea rsi, [rel s_hint1]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 148
	mov r8d, 0x9DB7E8
	call gfx_text
	jmp .buttons
.noprinter:
	lea rsi, [rel s_noprn1]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 92
	mov r8d, 0xFFFFFF
	call gfx_text
	lea rsi, [rel s_noprn2]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 120
	mov r8d, 0xD6E2F8
	call gfx_text
	lea rsi, [rel s_noprn3]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 144
	call gfx_text
.buttons:
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 150
	mov edx, 36
	lea rsi, [rel s_btn_print]
	mov r8d, ID_PRN_PRINT
	movzx r9d, byte [prn_found]
	call gui_button
	mov eax, [pw_x]
	add eax, 26 + 162
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 110
	mov edx, 36
	lea rsi, [rel s_btn_refresh]
	mov r8d, ID_PRN_REFRESH
	mov r9d, 1
	call gui_button
	mov eax, [pw_x]
	add eax, [pw_w]
	sub eax, 26 + 100
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 100
	mov edx, 36
	lea rsi, [rel s_btn_close]
	mov r8d, ID_PRN_CLOSE
	mov r9d, 1
	call gui_button
	jmp .out

	; ---------------- file picker
.picker:
	mov dword [pw_w], 600
	mov dword [pw_h], 480
	call .place
	mov eax, [pw_x]
	mov ebx, [pw_y]
	mov ecx, [pw_w]
	mov edx, [pw_h]
	call .panel
	FONT font_big
	mov dword [txt_alpha], 256
	lea rsi, [rel s_pick_title]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 18
	mov r8d, 0xFFFFFF
	call gfx_text
	FONT font_ui
	lea rsi, [rel s_pick_hint]
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, 54
	mov r8d, 0x9DB7E8
	call gfx_text
	cmp dword [pick_n], 0
	jne .rows
	lea rsi, [rel s_nofiles]
	mov eax, [pw_x]
	add eax, 40
	mov ebx, [pw_y]
	add ebx, 100
	mov r8d, 0xD6E2F8
	call gfx_text
.rows:
	xor edi, edi
.row:
	cmp edi, PICK_PAGE
	jae .pager
	mov eax, [pick_page]
	imul eax, PICK_PAGE
	add eax, edi
	cmp eax, [pick_n]
	jae .pager
	mov [pr_idx], eax
	imul ebx, edi, 30
	add ebx, [pw_y]
	add ebx, 84
	mov [pr_y], ebx
	mov eax, [pw_x]
	add eax, 26
	mov ecx, [pw_w]
	sub ecx, 52
	mov edx, 28
	lea r8d, [rdi + ID_PICK_ROW]
	call hot_add
	mov r9d, 0
	mov r8d, 0xFFFFFF
	lea eax, [rdi + ID_PICK_ROW]
	cmp eax, [hover_id]
	jne .nh
	mov r9d, 30
.nh:
	mov eax, [pr_idx]
	cmp eax, [pick_sel]
	jne .ns
	mov r9d, 150
	mov r8d, 0x2F7BFF
.ns:
	test r9d, r9d
	jz .name
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pr_y]
	mov ecx, [pw_w]
	sub ecx, 52
	mov edx, 28
	mov r10d, 6
	call gfx_rrect
.name:
	mov eax, [pr_idx]
	imul eax, PICK_REC
	lea rsi, [rel pick_list]
	add rsi, rax
	mov eax, [pw_x]
	add eax, 42
	mov ebx, [pr_y]
	add ebx, 5
	mov r8d, 0xFFFFFF
	call gfx_text
	inc edi
	jmp .row
.pager:
	; page indicator
	mov eax, [pick_n]
	add eax, PICK_PAGE - 1
	xor edx, edx
	mov ecx, PICK_PAGE
	div ecx
	test eax, eax
	jnz .pc
	mov eax, 1
.pc:
	mov [pr_pages], eax
	mov eax, [pick_page]
	inc eax
	call os_int_to_string
	mov rbx, rax
	lea rax, [rel s_page]
	lea rcx, [rel prn_line]
	call os_string_join			; "Page 1"
	lea rax, [rel prn_line]
	lea rbx, [rel s_of]
	lea rcx, [rel prn_line2]
	call os_string_join			; "Page 1 of "
	mov eax, [pr_pages]
	call os_int_to_string
	mov rbx, rax
	lea rax, [rel prn_line2]
	lea rcx, [rel prn_line]
	call os_string_join			; "Page 1 of 3"
	lea rsi, [rel prn_line]
	mov eax, [pw_x]
	add eax, 372
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 48
	mov r8d, 0xD6E2F8
	call gfx_text
	; buttons
	mov eax, [pw_x]
	add eax, 26
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 100
	mov edx, 36
	lea rsi, [rel s_btn_printit]
	mov r8d, ID_PICK_PRINT
	xor r9d, r9d
	cmp dword [pick_sel], 0
	jl .b1
	mov r9d, 1
.b1:
	call gui_button
	mov eax, [pw_x]
	add eax, 26 + 112
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 80
	mov edx, 36
	lea rsi, [rel s_btn_prev]
	mov r8d, ID_PICK_PREV
	xor r9d, r9d
	cmp dword [pick_page], 0
	je .b2
	mov r9d, 1
.b2:
	call gui_button
	mov eax, [pw_x]
	add eax, 26 + 112 + 90
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 80
	mov edx, 36
	lea rsi, [rel s_btn_next]
	mov r8d, ID_PICK_NEXT
	xor r9d, r9d
	mov eax, [pick_page]
	inc eax
	imul eax, PICK_PAGE
	cmp eax, [pick_n]
	jae .b3
	mov r9d, 1
.b3:
	mov eax, [pw_x]
	add eax, 26 + 112 + 90
	call gui_button
	mov eax, [pw_x]
	add eax, [pw_w]
	sub eax, 26 + 100
	mov ebx, [pw_y]
	add ebx, [pw_h]
	sub ebx, 58
	mov ecx, 100
	mov edx, 36
	lea rsi, [rel s_btn_back]
	mov r8d, ID_PICK_BACK
	mov r9d, 1
	call gui_button
.out:
	popall
	ret

.place:					; centre the window: pw_x, pw_y from pw_w, pw_h
	mov eax, [gW]
	sub eax, [pw_w]
	sar eax, 1
	mov [pw_x], eax
	mov eax, [gH]
	sub eax, [pw_h]
	sar eax, 1
	mov [pw_y], eax
	ret

.panel:					; EAX=x EBX=y ECX=w EDX=h
	push rax
	push rbx
	push rcx
	push rdx
	mov r8d, 0x0F1F45
	mov r9d, 250
	mov r10d, 12
	call gfx_rrect
	pop rdx
	pop rcx
	pop rbx
	pop rax
	mov edx, 1
	mov r8d, 0xFFFFFF
	mov r9d, 50
	xor r10d, r10d
	call gfx_rrect
	ret

; ==================================================================
; DATA
; ==================================================================

s_empty		db 0
s_sending	db 'Sending the file to the printer - please wait...', 0
s_sent		db 'Sent to the printer:', 0
s_checkprn	db 'Check the printer for the page.', 0
s_pfailed	db 'Printing failed:', 0
s_connected	db 'Connected:  ', 0
s_language	db 'Language:  ', 0
s_hint1		db 'Text files are sent in the language the printer reports.', 0
s_noprn1	db 'No USB printer found.', 0
s_noprn2	db 'Connect the printer with a USB cable and switch it on,', 0
s_noprn3	db 'then press Refresh.', 0
s_btn_print	db 'Print a file', 0
s_btn_refresh	db 'Refresh', 0
s_btn_close	db 'Close', 0
s_pick_title	db 'Choose a file to print', 0
s_pick_hint	db 'Click a file, then press Print.  Files on other USB drives are shown as USB1:NAME.', 0
s_nofiles	db 'No files found.', 0
s_btn_printit	db 'Print', 0
s_btn_prev	db 'Prev', 0
s_btn_next	db 'Next', 0
s_btn_back	db 'Back', 0
s_page		db 'Page ', 0
s_of		db ' of ', 0

prn_win		db 0
pick_n		dd 0
pick_sel	dd -1
pick_page	dd 0
pb_drive	dd 0
pw_x		dd 0
pw_y		dd 0
pw_w		dd 0
pw_h		dd 0
pr_idx		dd 0
pr_y		dd 0
pr_pages	dd 0
bt_x		dd 0
bt_y		dd 0
bt_w		dd 0
bt_h		dd 0
bt_en		dd 0
bt_label	dq 0
pick_name	dq 0
prn_line	times 96 db 0
prn_line2	times 96 db 0
pick_list	times PICK_MAX * PICK_REC db 0

; ==================================================================
