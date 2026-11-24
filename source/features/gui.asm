; ==================================================================
; GMU OS 64 -- graphical desktop
;
; Desktop with wallpaper, icons, taskbar, start menu and a mouse pointer
; (UEFI Simple Pointer protocol).  When no mouse is found the arrow keys
; move the pointer and Enter clicks.  If graphics are not available (or the
; file NOGUI.TXT exists on the boot pendrive) the old text interface starts.
; ==================================================================

APP_COMPUTER	equ 1
APP_DOCS	equ 2
APP_PICS	equ 3
APP_TERMINAL	equ 4
APP_CCOMP	equ 5
APP_FILEMGR	equ 6
APP_SETTINGS	equ 7
APP_RECYCLE	equ 8
APP_EDITOR	equ 9
APP_HELP	equ 10
APP_ABOUT	equ 11
APP_SHUTDOWN	equ 12
APP_PRINTER	equ 13

ID_START	equ 20
ID_TB		equ 21			; 21..24 taskbar apps
ID_MENU		equ 30			; 30..37 start menu items
ID_RECENT	equ 40			; 40..42 recent files
ID_OK		equ 50
ID_SEARCH	equ 19

TB_H		equ 48
MENU_W		equ 450
MENU_H		equ 514

; ------------------------------------------------------------------
; gui_start -- called from os_main: run the desktop, or fall back to text

gui_start:
	call gui_init
	jc option_screen
	call gui_main
	jmp option_screen

; ------------------------------------------------------------------
; gui_init -- set up graphics, buffers, pointers.  Carry set = not possible

gui_init:
	pushall
	lea rax, [rel s_nogui]			; NOGUI.TXT on the stick = text mode only
	call os_file_exists
	jnc .fail
	lea rcx, [rel guid_gop]
	xor edx, edx
	lea r8, [rel gop]
	BCALL 320				; LocateProtocol
	test rax, rax
	jnz .fail
	call gop_select_mode
	jc .fail
	mov eax, [gW]				; back buffer + wallpaper buffer
	imul eax, [gH]
	mov [gDwords], eax
	shl eax, 2
	add eax, 4095
	shr eax, 12
	mov [gPages], eax
	xor ecx, ecx
	mov edx, 2				; EfiLoaderData
	mov r8d, [gPages]
	lea r9, [rel gBack]
	BCALL BS_ALLOCATEPAGES
	test rax, rax
	jnz .fail
	xor ecx, ecx
	mov edx, 2
	mov r8d, [gPages]
	lea r9, [rel gWall]
	BCALL BS_ALLOCATEPAGES
	test rax, rax
	jnz .fail
	call gfx_make_wall
	call gui_ptr_init
	call gui_calibrate
	mov eax, [gW]				; pointer starts in the middle
	shr eax, 1
	mov [cur_x], eax
	mov eax, [gH]
	shr eax, 1
	mov [cur_y], eax
	mov dword [hover_id], 0
	mov dword [sel_id], 0
	mov byte [menu_open], 0
	mov byte [msg_open], 0
	mov rax, 0
	mov [cur_font], rax
	popall
	clc
	ret
.fail:
	popall
	stc
	ret

; gui_ptr_init -- find all pointing devices (relative mice and absolute pointers)
gui_ptr_init:
	pushall
	mov dword [ptr_cnt], 0
	mov dword [abs_cnt], 0
	lea rax, [rel guid_ptr]
	mov [pc_guid], rax
	lea rax, [rel ptr_list]
	mov [pc_list], rax
	lea rax, [rel ptr_cnt]
	mov [pc_cnt], rax
	call ptr_collect
	lea rax, [rel guid_abs]
	mov [pc_guid], rax
	lea rax, [rel abs_list]
	mov [pc_list], rax
	lea rax, [rel abs_cnt]
	mov [pc_cnt], rax
	call ptr_collect
	popall
	ret

; ptr_collect -- open every handle that has the protocol [pc_guid]; store up to 4
; interface pointers in [pc_list] and their number in the dword at [pc_cnt]
ptr_collect:
	pushall
	mov ecx, 2				; ByProtocol
	mov rdx, [pc_guid]
	xor r8d, r8d
	lea r9, [rel sc_count]
	lea r10, [rel sc_buf]
	BCALL 312				; LocateHandleBuffer
	test rax, rax
	jnz .done
	mov rbx, [sc_buf]
	xor esi, esi
.l:
	cmp rsi, [sc_count]
	jae .free
	mov rax, [pc_cnt]
	cmp dword [rax], 4
	jae .free
	mov rcx, [rbx + rsi*8]
	mov rdx, [pc_guid]
	lea r8, [rel sfs_tmp]
	BCALL BS_HANDLEPROTOCOL
	test rax, rax
	jnz .n
	mov rcx, [sfs_tmp]
	mov edx, 1
	mov rax, [rcx]				; Reset
	call efi_thunk
	mov rax, [pc_cnt]
	mov ecx, [rax]
	mov rdx, [pc_list]
	mov rdi, [sfs_tmp]
	mov [rdx + rcx*8], rdi
	inc dword [rax]
.n:
	inc rsi
	jmp .l
.free:
	mov rcx, [sc_buf]
	BCALL 72
.done:
	popall
	ret

; gui_calibrate -- measure the CPU time stamp counter against the firmware clock
gui_calibrate:
	pushall
	rdtsc
	shl rdx, 32
	or rax, rdx
	mov [tsc_base], rax
	mov ecx, 20000
	BCALL BS_STALL
	rdtsc
	shl rdx, 32
	or rax, rdx
	sub rax, [tsc_base]
	xor edx, edx
	mov ecx, 20
	div rcx
	cmp rax, 1000
	jae .ok
	mov rax, 1000000
.ok:
	mov [tsc_per_ms], rax
	rdtsc
	shl rdx, 32
	or rax, rdx
	mov [tsc_base], rax
	popall
	ret

; gui_ms -- RAX = milliseconds since start
gui_ms:
	push rdx
	push rcx
	rdtsc
	shl rdx, 32
	or rax, rdx
	sub rax, [tsc_base]
	xor edx, edx
	div qword [tsc_per_ms]
	pop rcx
	pop rdx
	ret

; ------------------------------------------------------------------
; main loop

gui_main:
	call os_hide_cursor
	call gui_refresh_recent
	call gui_scene
.loop:
	call gui_poll_input
	call gui_hit
	cmp eax, [hover_id]
	je .nohover
	mov [hover_id], eax
	call gui_scene
.nohover:
	mov al, [ptr_seen]
	cmp al, [ptr_seen_drawn]
	je .seen_ok
	mov [ptr_seen_drawn], al
	call gui_scene				; the status line changed
.seen_ok:
	cmp byte [click_ev], 0
	je .noclick
	mov byte [click_ev], 0
	call gui_click
.noclick:
	call gui_clock_tick
	call gui_cursor_update
	mov ecx, 1000
	BCALL BS_STALL
	jmp .loop

; gui_cursor_update -- move the pointer sprite if the position changed
gui_cursor_update:
	mov eax, [cur_x]
	cmp eax, [old_x]
	jne .move
	mov eax, [cur_y]
	cmp eax, [old_y]
	jne .move
	cmp byte [cur_valid], 0
	jne .ret
.move:
	cmp byte [cur_valid], 0
	je .nodel
	call gfx_cursor_erase
.nodel:
	mov eax, [cur_x]
	mov [old_x], eax
	mov eax, [cur_y]
	mov [old_y], eax
	call gfx_cursor_draw
	mov byte [cur_valid], 1
.ret:
	ret

; gui_clock_tick -- redraw when the minute changes
gui_clock_tick:
	call gui_ms
	mov rcx, rax
	sub rcx, [last_tick_ms]
	cmp rcx, 1000
	jb .ret
	mov [last_tick_ms], rax
	inc byte [prn_tick]			; every 3 seconds: is a printer plugged in / removed?
	cmp byte [prn_tick], 3
	jb .noscan
	mov byte [prn_tick], 0
	mov al, [prn_found]
	call prn_scan
	cmp al, [prn_found]
	je .noscan
	call gui_scene
.noscan:
	call rtc_read
	movzx eax, byte [rtc_time + 5]
	cmp al, [clk_min]
	je .ret
	mov [clk_min], al
	call gui_scene
.ret:
	ret

; ------------------------------------------------------------------
; input

gui_poll_input:
	pushall
	mov byte [btn_now], 0
	xor ebx, ebx
.p:
	cmp ebx, [ptr_cnt]
	jae .ptrdone
	lea r8, [rel ptr_list]
	mov rcx, [r8 + rbx*8]
	lea rdx, [rel ptr_state]
	mov rax, [rcx + 8]			; GetState
	call efi_thunk
	test rax, rax
	jnz .next
	lea r8, [rel ptr_list]
	mov rcx, [r8 + rbx*8]
	mov rcx, [rcx + 24]			; Mode
	mov r9, [rcx]				; ResolutionX (counts per mm)
	test r9, r9
	jnz .res
	mov r9d, 8
.res:
	movsxd rax, dword [ptr_state]
	imul rax, [ptr_speed]
	lea r8, [rel ptr_accx]
	add rax, [r8 + rbx*8]
	cqo
	idiv r9
	mov [r8 + rbx*8], rdx
	add [cur_x], eax
	movsxd rax, dword [ptr_state + 4]
	imul rax, [ptr_speed]
	lea r8, [rel ptr_accy]
	add rax, [r8 + rbx*8]
	cqo
	idiv r9
	mov [r8 + rbx*8], rdx
	add [cur_y], eax
	mov al, [ptr_state + 12]
	or [btn_now], al
	mov byte [ptr_seen], 1
.next:
	inc ebx
	jmp .p
.ptrdone:
	xor ebx, ebx				; absolute pointers (tablets, touch, virtual machines)
.a:
	cmp ebx, [abs_cnt]
	jae .absdone
	lea r8, [rel abs_list]
	mov rcx, [r8 + rbx*8]
	lea rdx, [rel abs_state]
	mov rax, [rcx + 8]			; GetState
	call efi_thunk
	test rax, rax
	jnz .anext
	lea r8, [rel abs_list]
	mov rsi, [r8 + rbx*8]
	mov rsi, [rsi + 24]			; Mode
	mov rax, [abs_state]			; X
	sub rax, [rsi]
	mov ecx, [gW]
	imul rax, rcx
	mov rcx, [rsi + 24]
	sub rcx, [rsi]
	inc rcx
	xor edx, edx
	div rcx
	mov [cur_x], eax
	mov rax, [abs_state + 8]		; Y
	sub rax, [rsi + 8]
	mov ecx, [gH]
	imul rax, rcx
	mov rcx, [rsi + 32]
	sub rcx, [rsi + 8]
	inc rcx
	xor edx, edx
	div rcx
	mov [cur_y], eax
	mov eax, [abs_state + 24]		; ActiveButtons
	and al, 1
	or [btn_now], al
	mov byte [ptr_seen], 1
.anext:
	inc ebx
	jmp .a
.absdone:
	; keyboard: arrows move the pointer, Enter / Space click, Esc closes
	call os_check_for_key
	test ax, ax
	jz .clamp
	cmp ah, 48h
	jne .k1
	sub dword [cur_y], 16
.k1:
	cmp ah, 50h
	jne .k2
	add dword [cur_y], 16
.k2:
	cmp ah, 4Bh
	jne .k3
	sub dword [cur_x], 16
.k3:
	cmp ah, 4Dh
	jne .k4
	add dword [cur_x], 16
.k4:
	cmp al, 9				; Tab: jump to the next clickable item
	jne .nt
	call gui_tab
.nt:
	cmp al, 13
	je .kclick
	cmp al, ' '
	je .kclick
	cmp al, 27
	jne .clamp
	cmp byte [msg_open], 0
	je .esc2
	mov byte [msg_open], 0
	mov dword [hover_id], -1
	jmp .clamp
.esc2:
	cmp byte [prn_win], 0
	je .esc3
	cmp byte [prn_win], 2			; file picker: back to the printer window
	jne .esc_close
	mov byte [prn_win], 1
	mov dword [hover_id], -1
	jmp .clamp
.esc_close:
	mov byte [prn_win], 0
	mov dword [hover_id], -1
	jmp .clamp
.esc3:
	cmp byte [menu_open], 0
	je .clamp
	mov byte [menu_open], 0
	mov dword [hover_id], -1
	jmp .clamp
.kclick:
	mov byte [click_ev], 1
	mov byte [kbd_click], 1
.clamp:
	mov eax, [cur_x]
	test eax, eax
	jns .x1
	xor eax, eax
.x1:
	mov ecx, [gW]
	dec ecx
	cmp eax, ecx
	jle .x2
	mov eax, ecx
.x2:
	mov [cur_x], eax
	mov eax, [cur_y]
	test eax, eax
	jns .y1
	xor eax, eax
.y1:
	mov ecx, [gH]
	dec ecx
	cmp eax, ecx
	jle .y2
	mov eax, ecx
.y2:
	mov [cur_y], eax
	mov al, [btn_now]
	cmp al, 0
	je .release
	cmp byte [btn_prev], 0
	jne .done
	mov byte [click_ev], 1			; button went down
.release:
.done:
	mov al, [btn_now]
	mov [btn_prev], al
	popall
	ret

; gui_tab -- move the pointer to the centre of the next hotspot (keyboard use)
gui_tab:
	push rax
	push rcx
	push rdx
	push r8
	mov eax, [hot_n]
	test eax, eax
	jz .out
	cmp byte [msg_open], 0
	je .next
	dec eax					; message box: the OK button (last hotspot)
	jmp .set
.next:
	mov eax, [tab_idx]
	mov ecx, [hot_n]			; at most one lap
.try:
	inc eax
	cmp eax, [hot_n]
	jb .inrange
	xor eax, eax
.inrange:
	cmp byte [prn_win], 0
	je .set
	imul edx, eax, 20			; printer windows: skip the desktop's hotspots
	lea r8, [rel hot_tab]
	add r8, rdx
	cmp dword [r8 + 16], 50
	jae .set
	dec ecx
	jnz .try
.set:
	mov [tab_idx], eax
	imul edx, eax, 20
	lea r8, [rel hot_tab]
	add r8, rdx
	mov eax, [r8]
	mov ecx, [r8 + 8]
	shr ecx, 1
	add eax, ecx
	mov [cur_x], eax
	mov eax, [r8 + 4]
	mov ecx, [r8 + 12]
	shr ecx, 1
	add eax, ecx
	mov [cur_y], eax
.out:
	pop r8
	pop rdx
	pop rcx
	pop rax
	ret

; gui_hit -- EAX = id of the hotspot under the pointer (0 = none)
gui_hit:
	push rbx
	push rcx
	push rdx
	push r8
	mov ecx, [hot_n]
.l:
	test ecx, ecx
	jz .none
	dec ecx
	imul edx, ecx, 20
	lea r8, [rel hot_tab]
	add r8, rdx
	mov eax, [cur_x]
	mov edx, [r8]
	cmp eax, edx
	jl .l
	add edx, [r8 + 8]
	cmp eax, edx
	jge .l
	mov eax, [cur_y]
	mov edx, [r8 + 4]
	cmp eax, edx
	jl .l
	add edx, [r8 + 12]
	cmp eax, edx
	jge .l
	mov eax, [r8 + 16]
	cmp byte [msg_open], 0			; a message box blocks everything but OK
	je .nomsgm
	cmp eax, ID_OK
	jne .l
	jmp .found
.nomsgm:
	cmp byte [prn_win], 0			; printer windows: only their own controls
	je .found
	cmp eax, 50
	jb .l
.found:
	pop r8
	pop rdx
	pop rcx
	pop rbx
	ret
.none:
	xor eax, eax
	pop r8
	pop rdx
	pop rcx
	pop rbx
	ret

; hot_add -- register a clickable rectangle   EAX=x EBX=y ECX=w EDX=h R8D=id
hot_add:
	push r9
	push r10
	push r11
	mov r9d, [hot_n]
	cmp r9d, 64
	jae .out
	imul r10d, r9d, 20
	lea r11, [rel hot_tab]
	add r11, r10
	mov [r11], eax
	mov [r11 + 4], ebx
	mov [r11 + 8], ecx
	mov [r11 + 12], edx
	mov [r11 + 16], r8d
	inc dword [hot_n]
.out:
	pop r11
	pop r10
	pop r9
	ret

; ------------------------------------------------------------------
; clicks

gui_click:
	pushall
	mov al, [kbd_click]
	mov [kc_now], al
	mov byte [kbd_click], 0
	call gui_hit
	mov ebx, eax
	cmp byte [msg_open], 0
	je .nomsg
	cmp ebx, ID_OK
	jne .out
	mov byte [msg_open], 0
	mov dword [hover_id], -1
	call gui_scene
	jmp .out
.nomsg:
	cmp byte [prn_win], 0			; the printer window / file picker is open
	je .noprn
	mov eax, ebx
	call gui_prn_click
	jmp .out
.noprn:
	test ebx, ebx
	jnz .some
	; click on empty space: close the menu, clear the selection
	mov byte [menu_open], 0
	mov dword [sel_id], 0
	call gui_scene
	jmp .out
.some:
	cmp ebx, 9
	ja .notdesk
	; desktop icon: select, double click opens
	call gui_ms
	mov rcx, rax
	sub rcx, [last_click_ms]
	mov [last_click_ms], rax
	cmp byte [kc_now], 0			; keyboard: Enter opens at once
	jne .open
	cmp ebx, [sel_id]
	jne .newsel
	cmp rcx, 450
	jae .newsel
.open:
	mov byte [menu_open], 0
	mov dword [sel_id], 0
	lea rcx, [rel desk_apps]
	movzx eax, byte [rcx + rbx - 1]		; icon n opens its app
	call gui_activate
	jmp .out
.newsel:
	mov byte [menu_open], 0
	mov [sel_id], ebx
	call gui_scene
	jmp .out
.notdesk:
	cmp ebx, ID_START
	jne .nostart
	xor byte [menu_open], 1
	cmp byte [menu_open], 0
	je .redo
	call gui_refresh_recent
.redo:
	call gui_scene
	jmp .out
.nostart:
	cmp ebx, ID_TB
	jb .nottb
	cmp ebx, ID_TB + 3
	ja .nottb
	mov byte [menu_open], 0
	lea rcx, [rel tb_apps]
	mov eax, ebx
	sub eax, ID_TB
	movzx eax, byte [rcx + rax]
	call gui_activate
	jmp .out
.nottb:
	cmp ebx, ID_MENU
	jb .notmenu
	cmp ebx, ID_MENU + 8
	ja .notmenu
	mov byte [menu_open], 0
	lea rcx, [rel menu_apps]
	mov eax, ebx
	sub eax, ID_MENU
	movzx eax, byte [rcx + rax]
	call gui_activate
	jmp .out
.notmenu:
	cmp ebx, ID_RECENT
	jb .out
	cmp ebx, ID_RECENT + 2
	ja .out
	mov byte [menu_open], 0
	mov eax, ebx
	sub eax, ID_RECENT
	call gui_recent_msg
.out:
	popall
	ret

; ------------------------------------------------------------------
; gui_activate -- EAX = app number
gui_activate:
	pushall
	mov ebx, eax
	cmp ebx, APP_TERMINAL
	jne .a1
	xor eax, eax
	call gui_launch_cli
	jmp .out
.a1:
	cmp ebx, APP_CCOMP
	je .editor
	cmp ebx, APP_EDITOR
	jne .a2
.editor:
	mov eax, 1
	call gui_launch_cli
	jmp .out
.a2:
	cmp ebx, APP_PRINTER
	jne .nprn
	call gui_prn_open
	jmp .out
.nprn:
	cmp ebx, APP_SHUTDOWN
	je .shutdown
	cmp ebx, APP_HELP
	jne .a3
	lea rsi, [rel app_names + 9*20]
	lea rdx, [rel help_l1]
	lea r8, [rel help_l2]
	lea r9, [rel help_l3]
	call gui_show_msg
	jmp .out
.a3:
	cmp ebx, APP_ABOUT
	jne .generic
	lea rsi, [rel app_names + 10*20]
	lea rdx, [rel about_l1]
	lea r8, [rel about_l2]
	lea r9, [rel about_l3]
	call gui_show_msg
	jmp .out
.generic:
	lea rsi, [rel app_names - 20]
	mov eax, ebx
	imul eax, 20
	add rsi, rax
	lea rdx, [rel soon_l1]
	lea r8, [rel soon_l2]
	lea r9, [rel soon_l3]
	call gui_show_msg
	jmp .out
.shutdown:
	mov ecx, 2				; EfiResetShutdown
	xor edx, edx
	xor r8d, r8d
	xor r9d, r9d
	mov rax, [run_svc]
	mov rax, [rax + RT_RESETSYSTEM]
	call efi_thunk
.hang:
	hlt
	jmp .hang
.out:
	popall
	ret

; gui_show_msg -- RSI = title, RDX/R8/R9 = three text lines
gui_show_msg:
	mov [msg_t], rsi
	mov [msg_1], rdx
	mov [msg_2], r8
	mov [msg_3], r9
	mov byte [msg_open], 1
	mov dword [hover_id], -1
	jmp gui_scene

; gui_recent_msg -- EAX = index of the recent file
gui_recent_msg:
	pushall
	lea rcx, [rel recent_ptr]
	mov rsi, [rcx + rax*8]
	lea rdx, [rel rec_l1]
	lea r8, [rel rec_l2]
	lea r9, [rel rec_l3]
	call gui_show_msg
	popall
	ret

; gui_launch_cli -- EAX = 0: command line, 1: C editor.  Returns to the desktop afterwards.
gui_launch_cli:
	pushall
	mov [cli_start_cmd], al
	call gui_clear_fb
	call os_show_cursor
	call os_clear_screen
	call os_command_line
%ifdef TEST_MODEFLIP
	mov rcx, [gop]				; test only: the firmware changes the mode behind our back
	xor edx, edx
	mov rax, [rcx + 8]
	call efi_thunk
%endif
	call os_hide_cursor
	mov dword [hover_id], -1
	mov byte [cur_valid], 0
	call gui_refresh_recent
	call gui_scene
	popall
	ret

; gui_clear_fb -- paint the whole screen black (before the text console takes over)
gui_clear_fb:
	pushall
	mov rdi, [gFbBase]
	mov ecx, [gFbStride]
	imul ecx, [gH]
	shr ecx, 2
	xor eax, eax
	rep stosd
	popall
	ret

; gui_refresh_recent -- take the first three files of the boot drive for the Recent list
gui_refresh_recent:
	pushall
	mov dword [recent_n], 0
	mov rcx, [root_dir]
	mov [list_root], rcx
	call disk_read_root_dir
	jc .out
	lea rdi, [rel dir_buffer]
	mov ebx, [dir_count]
	lea r8, [rel recent_ptr]
.l:
	test ebx, ebx
	jz .out
	cmp dword [recent_n], 3
	jae .out
	test byte [rdi + REC_ATTR], 18h
	jnz .n
	mov al, [rdi]
	cmp al, ' '
	jbe .n
	cmp al, '.'
	je .n
	mov eax, [recent_n]
	mov [r8 + rax*8], rdi
	inc dword [recent_n]
.n:
	add rdi, REC_SIZE
	dec ebx
	jmp .l
.out:
	popall
	ret

; ------------------------------------------------------------------
; scene

gui_scene:
	pushall
	call gfx_ensure_mode
	mov dword [hot_n], 0
	mov rsi, [gWall]
	mov rdi, [gBack]
	mov ecx, [gDwords]
	rep movsd
	call gui_draw_title
	call gui_draw_icons
	call gui_draw_taskbar
	cmp byte [menu_open], 0
	je .nomenu
	call gui_draw_menu
.nomenu:
	cmp byte [prn_win], 0
	je .noprnwin
	call gui_draw_prnwin
.noprnwin:
	cmp byte [msg_open], 0
	je .nomsg
	call gui_draw_msg
.nomsg:
	xor eax, eax
	xor ebx, ebx
	mov ecx, [gW]
	mov edx, [gH]
	call gfx_present
	mov byte [cur_valid], 0
	popall
	ret

; text helpers: font selection
%macro FONT 1
	lea rax, [rel %1]
	mov [cur_font], rax
%endmacro

gui_draw_title:
	pushall
	lea rsi, [rel title_img]
	movzx ecx, word [rsi]
	mov eax, [gW]
	sub eax, ecx
	sub eax, 80
	mov ebx, [gH]
	sub ebx, 250
	mov r8d, 0xFFFFFF
	mov r9d, 256
	call gfx_mask
	lea rsi, [rel subtitle_img]
	movzx ecx, word [rsi]
	mov eax, [gW]
	sub eax, ecx
	sub eax, 80
	mov ebx, [gH]
	sub ebx, 188
	mov r8d, 0xD6E6FF
	mov r9d, 235
	call gfx_mask
	FONT font_ui
	lea rsi, [rel ver_text]
	call gfx_text_width
	mov ecx, eax
	mov eax, [gW]
	sub eax, ecx
	sub eax, 80
	mov ebx, [gH]
	sub ebx, 148
	mov r8d, 0x9DB7E8
	mov dword [txt_alpha], 256
	call gfx_text
	; mouse status line
	call gui_mouse_text
	call gfx_text_width
	mov ecx, eax
	mov eax, [gW]
	sub eax, ecx
	sub eax, 80
	mov ebx, [gH]
	sub ebx, 124
	mov r8d, 0x7F9BD0
	call gui_mouse_text
	call gfx_text
	popall
	ret

; gui_mouse_text -- RSI = status text for the mouse line
gui_mouse_text:
	push rax
	lea rsi, [rel mouse_work_text]
	cmp byte [ptr_seen], 0
	jne .r
	lea rsi, [rel mouse_ok_text]
	mov eax, [ptr_cnt]
	add eax, [abs_cnt]
	jnz .r
	lea rsi, [rel mouse_no_text]
.r:
	pop rax
	ret

gui_draw_icons:
	pushall
	FONT font_ui
	mov dword [txt_alpha], 256
	xor ebx, ebx				; icon number 0..8
.l:
	cmp ebx, 9
	jae .out
	mov [gi], ebx
	mov eax, [gH]				; icons per column
	sub eax, TB_H + 8
	xor edx, edx
	mov ecx, 72
	div ecx
	mov ecx, eax
	test ecx, ecx
	jnz .rows_ok
	mov ecx, 1
.rows_ok:
	mov eax, ebx
	xor edx, edx
	div ecx					; EAX = column, EDX = row
	imul eax, 100
	add eax, 4
	mov [cell_x], eax
	imul ebx, edx, 72
	add ebx, 8				; cell y
	mov eax, [cell_x]
	mov ecx, 92
	mov edx, 70
	mov r8d, [gi]
	inc r8d
	call hot_add
	mov r8d, [gi]
	inc r8d
	mov r9d, 0
	cmp r8d, [hover_id]
	jne .nh
	mov r9d, 38
.nh:
	cmp r8d, [sel_id]
	jne .ns
	mov r9d, 62
.ns:
	test r9d, r9d
	jz .nohl
	mov eax, [cell_x]
	mov r8d, 0xFFFFFF
	mov r10d, 6
	call gfx_rrect
.nohl:
	mov eax, [gi]				; icon image
	imul eax, GFX_ICON48
	lea rsi, [rel icons48]
	add rsi, rax
	mov eax, [cell_x]
	add eax, 22
	add ebx, 4
	mov ecx, 48
	call gfx_icon
	sub ebx, 4
	; label centred under the icon
	mov eax, [gi]
	imul eax, 14
	lea rsi, [rel desk_labels]
	add rsi, rax
	call gfx_text_width
	mov ecx, 92
	sub ecx, eax
	sar ecx, 1
	add ecx, [cell_x]
	mov eax, ecx
	add ebx, 52
	mov r8d, 0xFFFFFF
	call gfx_text_shadow
	mov ebx, [gi]
	inc ebx
	jmp .l
.out:
	popall
	ret

gui_draw_taskbar:
	pushall
	mov ebx, [gH]
	sub ebx, TB_H				; taskbar top
	mov [tb_y], ebx
	xor eax, eax
	mov ecx, [gW]
	mov edx, TB_H
	mov r8d, 0x08122B
	mov r9d, 222
	xor r10d, r10d
	call gfx_rrect
	xor eax, eax
	mov ecx, [gW]
	mov edx, 1
	mov r8d, 0xFFFFFF
	mov r9d, 40
	call gfx_rrect
	; start button
	mov eax, 6
	mov ebx, [tb_y]
	add ebx, 4
	mov ecx, 48
	mov edx, 40
	mov r8d, ID_START
	call hot_add
	mov r9d, 0
	cmp dword [hover_id], ID_START
	jne .n1
	mov r9d, 36
.n1:
	cmp byte [menu_open], 0
	je .n2
	mov r9d, 55
.n2:
	test r9d, r9d
	jz .nohl1
	mov eax, 6
	mov r8d, 0xFFFFFF
	mov r10d, 6
	call gfx_rrect
.nohl1:
	lea rsi, [rel icons32 + 11*GFX_ICON32]
	mov eax, 14
	add ebx, 4
	mov ecx, 32
	call gfx_icon
	; search box
	mov eax, 66
	mov ebx, [tb_y]
	add ebx, 7
	mov ecx, 300
	mov edx, 34
	mov r8d, ID_SEARCH
	call hot_add
	mov r8d, 0xFFFFFF
	mov r9d, 30
	cmp dword [hover_id], ID_SEARCH
	jne .n3
	mov r9d, 46
.n3:
	mov r10d, 17
	call gfx_rrect
	lea rsi, [rel icons32 + 10*GFX_ICON32]
	mov eax, 70
	mov ebx, [tb_y]
	add ebx, 8
	mov ecx, 32
	call gfx_icon
	FONT font_ui
	mov dword [txt_alpha], 256
	lea rsi, [rel search_text]
	mov eax, 108
	mov ebx, [tb_y]
	add ebx, 14
	mov r8d, 0xB4C2DC
	call gfx_text
	; pinned apps
	xor edi, edi
.apps:
	cmp edi, 4
	jae .tray
	imul eax, edi, 56
	add eax, 396
	mov ebx, [tb_y]
	add ebx, 4
	mov ecx, 48
	mov edx, 40
	mov r8d, edi
	add r8d, ID_TB
	push rax
	sub eax, 8
	call hot_add
	add eax, 8
	pop rax
	mov r9d, 0
	lea r8d, [rdi + ID_TB]
	cmp r8d, [hover_id]
	jne .nh
	mov r9d, 36
.nh:
	test r9d, r9d
	jz .noh
	sub eax, 8
	mov ebx, [tb_y]
	add ebx, 4
	mov ecx, 48
	mov edx, 40
	mov r8d, 0xFFFFFF
	mov r10d, 6
	call gfx_rrect
	add eax, 8
.noh:
	lea rcx, [rel tb_icons]
	movzx r8d, byte [rcx + rdi]
	imul r8d, GFX_ICON32
	lea rsi, [rel icons32]
	add rsi, r8
	mov ebx, [tb_y]
	add ebx, 8
	mov ecx, 32
	call gfx_icon
	inc edi
	jmp .apps
.tray:
	; clock: time and date, right aligned
	lea rbx, [rel clk_time]
	call os_get_time_string
	mov ax, [fmt_date]
	push rax
	mov ax, 0x0080				; month names: "Nov 16, 2026"
	call os_set_date_fmt
	lea rbx, [rel clk_date]
	call os_get_date_string
	pop rax
	mov [fmt_date], ax
	FONT font_ui
	mov dword [txt_alpha], 256
	lea rsi, [rel clk_time]
	call gfx_text_width
	mov ecx, [gW]
	sub ecx, 16
	sub ecx, eax
	mov eax, ecx
	mov ebx, [tb_y]
	add ebx, 5
	mov r8d, 0xFFFFFF
	call gfx_text
	lea rsi, [rel clk_date]
	call gfx_text_width
	mov ecx, [gW]
	sub ecx, 16
	sub ecx, eax
	mov eax, ecx
	mov ebx, [tb_y]
	add ebx, 24
	mov r8d, 0xD6E2F8
	call gfx_text
	lea rsi, [rel icons32 + 9*GFX_ICON32]	; volume
	mov eax, [gW]
	sub eax, 150
	mov ebx, [tb_y]
	add ebx, 8
	mov ecx, 32
	call gfx_icon
	cmp byte [prn_found], 0			; printer connected
	je .noprn_icon
	lea rsi, [rel icons32 + 12*GFX_ICON32]
	mov eax, [gW]
	sub eax, 230
	mov ebx, [tb_y]
	add ebx, 8
	mov ecx, 32
	call gfx_icon
.noprn_icon:
	lea rsi, [rel icons32 + 8*GFX_ICON32]	; removable drive
	mov eax, [gW]
	sub eax, 190
	mov ebx, [tb_y]
	add ebx, 8
	mov ecx, 32
	call gfx_icon
	popall
	ret

; ------------------------------------------------------------------
; start menu

gui_draw_menu:
	pushall
	mov eax, 12
	mov ebx, [gH]
	sub ebx, TB_H + 8 + MENU_H
	mov [mn_y], ebx
	mov ecx, MENU_W
	mov edx, MENU_H
	mov r8d, 0x0C1A3A
	mov r9d, 236
	mov r10d, 12
	call gfx_rrect
	mov eax, 12
	mov ecx, MENU_W
	mov edx, 1
	mov r8d, 0xFFFFFF
	mov r9d, 38
	xor r10d, r10d
	call gfx_rrect
	; header
	lea rsi, [rel icons32 + 11*GFX_ICON32]
	mov eax, 32
	mov ebx, [mn_y]
	add ebx, 18
	mov ecx, 32
	call gfx_icon
	FONT font_big
	mov dword [txt_alpha], 256
	lea rsi, [rel menu_title]
	mov eax, 76
	mov ebx, [mn_y]
	add ebx, 19
	mov r8d, 0xFFFFFF
	call gfx_text
	; items
	FONT font_ui
	xor edi, edi
.items:
	cmp edi, 9
	jae .right
	; row y: 5 apps, gap, 2 entries, gap, shutdown
	mov ebx, [mn_y]
	add ebx, 70
	lea rcx, [rel menu_rows]
	movzx eax, word [rcx + rdi*2]
	add ebx, eax				; row top
	mov eax, 20
	mov ecx, 246
	mov edx, 44
	lea r8d, [rdi + ID_MENU]
	call hot_add
	lea r8d, [rdi + ID_MENU]
	cmp r8d, [hover_id]
	jne .nh
	mov r9d, 30
	mov r8d, 0xFFFFFF
	mov r10d, 8
	call gfx_rrect
.nh:
	lea rcx, [rel menu_icons]
	movzx eax, byte [rcx + rdi]
	imul eax, GFX_ICON32
	lea rsi, [rel icons32]
	add rsi, rax
	mov eax, 32
	add ebx, 6
	mov ecx, 32
	call gfx_icon
	lea rax, [rdi + rdi*8]			; label = menu_labels + i*18
	add rax, rax
	lea rsi, [rel menu_labels]
	add rsi, rax
	mov eax, 78
	add ebx, 6
	mov r8d, 0xFFFFFF
	call gfx_text
	inc edi
	jmp .items
.right:
	; divider
	mov eax, 12 + 276
	mov ebx, [mn_y]
	add ebx, 70
	mov ecx, 1
	mov edx, MENU_H - 100
	mov r8d, 0xFFFFFF
	mov r9d, 34
	xor r10d, r10d
	call gfx_rrect
	FONT font_bold
	lea rsi, [rel recent_title]
	mov eax, 12 + 296
	mov ebx, [mn_y]
	add ebx, 74
	mov r8d, 0xFFFFFF
	call gfx_text
	FONT font_ui
	xor edi, edi
.recent:
	cmp edi, [recent_n]
	jae .out
	imul ebx, edi, 40
	add ebx, [mn_y]
	add ebx, 108
	mov eax, 12 + 292
	mov ecx, 140
	mov edx, 36
	lea r8d, [rdi + ID_RECENT]
	call hot_add
	lea r8d, [rdi + ID_RECENT]
	cmp r8d, [hover_id]
	jne .rnh
	mov r9d, 30
	mov r8d, 0xFFFFFF
	mov r10d, 8
	call gfx_rrect
.rnh:
	lea rsi, [rel icons32 + 3*GFX_ICON32]
	mov eax, 12 + 296
	add ebx, 2
	mov ecx, 32
	call gfx_icon
	; file name (at most 14 characters)
	lea rcx, [rel recent_ptr]
	mov rsi, [rcx + rdi*8]
	lea rdx, [rel recent_tmp]
	xor ecx, ecx
.cp:
	cmp ecx, 14
	jae .cpd
	mov al, [rsi + rcx]
	test al, al
	jz .cpd
	mov [rdx + rcx], al
	inc ecx
	jmp .cp
.cpd:
	mov byte [rdx + rcx], 0
	lea rsi, [rel recent_tmp]
	mov eax, 12 + 336
	add ebx, 7
	mov r8d, 0xFFFFFF
	call gfx_text
	inc edi
	jmp .recent
.out:
	popall
	ret

; ------------------------------------------------------------------
; message box

gui_draw_msg:
	pushall
	xor eax, eax				; dim the desktop
	xor ebx, ebx
	mov ecx, [gW]
	mov edx, [gH]
	mov r8d, 0x000000
	mov r9d, 100
	xor r10d, r10d
	call gfx_rrect
	mov eax, [gW]
	sub eax, 480
	shr eax, 1
	mov [mg_x], eax
	mov ebx, [gH]
	sub ebx, 210
	shr ebx, 1
	mov [mg_y], ebx
	mov ecx, 480
	mov edx, 210
	mov r8d, 0x0F1F45
	mov r9d, 250
	mov r10d, 12
	call gfx_rrect
	mov eax, [mg_x]
	mov ebx, [mg_y]
	mov ecx, 480
	mov edx, 1
	mov r8d, 0xFFFFFF
	mov r9d, 50
	xor r10d, r10d
	call gfx_rrect
	FONT font_big
	mov dword [txt_alpha], 256
	mov rsi, [msg_t]
	mov eax, [mg_x]
	add eax, 24
	mov ebx, [mg_y]
	add ebx, 16
	mov r8d, 0xFFFFFF
	call gfx_text
	FONT font_ui
	mov rsi, [msg_1]
	mov eax, [mg_x]
	add eax, 24
	mov ebx, [mg_y]
	add ebx, 68
	mov r8d, 0xD6E2F8
	call gfx_text
	mov rsi, [msg_2]
	mov eax, [mg_x]
	add eax, 24
	mov ebx, [mg_y]
	add ebx, 92
	call gfx_text
	mov rsi, [msg_3]
	mov eax, [mg_x]
	add eax, 24
	mov ebx, [mg_y]
	add ebx, 116
	call gfx_text
	; OK button
	mov eax, [mg_x]
	add eax, 480 - 114
	mov ebx, [mg_y]
	add ebx, 210 - 54
	mov ecx, 90
	mov edx, 34
	mov r8d, ID_OK
	call hot_add
	mov r8d, 0x2F7BFF
	cmp dword [hover_id], ID_OK
	jne .nb
	mov r8d, 0x5599FF
.nb:
	mov r9d, 256
	mov r10d, 7
	call gfx_rrect
	FONT font_bold
	lea rsi, [rel ok_text]
	mov eax, [mg_x]
	add eax, 480 - 114 + 33
	mov ebx, [mg_y]
	add ebx, 210 - 54 + 8
	mov r8d, 0xFFFFFF
	call gfx_text
	popall
	ret

; ==================================================================
; DATA
; ==================================================================

s_nogui		db 'NOGUI.TXT', 0
ver_text	db '64-bit UEFI edition  -  based on MikeOS', 0
search_text	db 'Search GMU OS...', 0
mouse_ok_text	db 'Mouse found - keyboard: arrows move, Tab jumps, Enter clicks', 0
mouse_work_text	db 'Mouse working', 0
mouse_no_text	db 'No mouse - keyboard: arrows move, Tab jumps, Enter clicks', 0
menu_title	db 'GMU OS', 0
recent_title	db 'Recent Files', 0
ok_text		db 'OK', 0

desk_labels:
	db 'My Computer', 0, 0, 0
	db 'Documents', 0, 0, 0, 0, 0
	db 'Pictures', 0, 0, 0, 0, 0, 0
	db 'Terminal', 0, 0, 0, 0, 0, 0
	db 'C Compiler', 0, 0, 0, 0
	db 'File Manager', 0, 0
	db 'Settings', 0, 0, 0, 0, 0, 0
	db 'Recycle Bin', 0, 0, 0
	db 'Printer', 0, 0, 0, 0, 0, 0, 0

menu_labels:
	db 'File Manager', 0, 0, 0, 0, 0, 0
	db 'C Compiler', 0, 0, 0, 0, 0, 0, 0, 0
	db 'Terminal', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Text Editor', 0, 0, 0, 0, 0, 0, 0
	db 'Settings', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Printer', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Help', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'About GMU OS', 0, 0, 0, 0, 0, 0
	db 'Shut Down', 0, 0, 0, 0, 0, 0, 0, 0, 0

%if ($ - desk_labels) != 9*14 + 9*18
%error "desk_labels / menu_labels have the wrong record size"
%endif
app_names:				; 20 bytes each, indexed by app number - 1
	db 'My Computer', 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Documents', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Pictures', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Terminal', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'C Compiler', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'File Manager', 0, 0, 0, 0, 0, 0, 0, 0
	db 'Settings', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Recycle Bin', 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Text Editor', 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Help', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'About GMU OS', 0, 0, 0, 0, 0, 0, 0, 0
	db 'Shut Down', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	db 'Printer', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

%if ($ - app_names) != 13*20
%error "app_names has the wrong record size"
%endif
; taskbar: app numbers and icon numbers of the four pinned apps
tb_apps		db APP_FILEMGR, APP_TERMINAL, APP_CCOMP, APP_SETTINGS
tb_icons	db 0, 1, 2, 4
; start menu: app numbers, icon numbers and the vertical position of each row
menu_apps	db APP_FILEMGR, APP_CCOMP, APP_TERMINAL, APP_EDITOR, APP_SETTINGS, APP_PRINTER, APP_HELP, APP_ABOUT, APP_SHUTDOWN
desk_apps	db APP_COMPUTER, APP_DOCS, APP_PICS, APP_TERMINAL, APP_CCOMP, APP_FILEMGR, APP_SETTINGS, APP_RECYCLE, APP_PRINTER
menu_icons	db 0, 2, 1, 3, 4, 12, 5, 6, 7
menu_rows	dw 0, 44, 88, 132, 176, 220, 280, 324, 384

soon_l1		db 'This app is part of the next phase of the GMU OS desktop.', 0
soon_l2		db 'The Terminal and the C Compiler already work: double-click', 0
soon_l3		db 'their icons, or use the Start menu.', 0
help_l1		db 'Double-click an icon, or open the Start menu (bottom left).', 0
help_l2		db 'Terminal = command line (DIR, COPY, PASTE, CC ...).  Type EXIT', 0
help_l3		db 'to come back to the desktop.  C Compiler = type and run C.', 0
about_l1	db 'GMU OS 64-bit UEFI edition, based on MikeOS.', 0
about_l2	db 'GM University, Davangere  -  Pavan M Patil.', 0
about_l3	db 'Desktop phase 1: graphics, mouse pointer, icons, start menu.', 0
rec_l1		db 'Opening files from the desktop comes with the File Manager', 0
rec_l2		db '(next phase).  For now use the Terminal:  CAT <file>  or', 0
rec_l3		db 'C <file>  to look at or edit it.', 0

guid_gop:	dd 0x9042A9DE
		dw 0x23DC, 0x4A38
		db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A
guid_abs:	dd 0x8D59D32B
		dw 0xC655, 0x4AE9
		db 0x9B, 0x15, 0xF2, 0x59, 0x04, 0x99, 0x2A, 0x43
guid_ptr:	dd 0x31878C87
		dw 0x0B75, 0x11D5
		db 0x9A, 0x4F, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D

gPages		dd 0
gDwords		dd 0
gi		dd 0
tb_y		dd 0
mn_y		dd 0
mg_x		dd 0
mg_y		dd 0
hot_n		dd 0
hover_id	dd 0
sel_id		dd 0
recent_n	dd 0
tab_idx		dd -1
cell_x		dd 0
prn_tick	db 0
ptr_cnt		dd 0
abs_cnt		dd 0
ptr_seen	db 0
ptr_seen_drawn	db 0
pc_guid		dq 0
pc_list		dq 0
pc_cnt		dq 0
abs_list	times 4 dq 0
abs_state	times 40 db 0
ptr_speed	dq 5
btn_now		db 0
btn_prev	db 0
click_ev	db 0
kbd_click	db 0
kc_now		db 0
cur_valid	db 0
menu_open	db 0
msg_open	db 0
clk_min		db 0xFF
cli_start_cmd	db 0
tsc_base	dq 0
tsc_per_ms	dq 1000000
last_tick_ms	dq 0
last_click_ms	dq 0
msg_t		dq 0
msg_1		dq 0
msg_2		dq 0
msg_3		dq 0
ptr_list	times 4 dq 0
ptr_accx	times 4 dq 0
ptr_accy	times 4 dq 0
ptr_state	times 16 db 0
recent_ptr	times 3 dq 0
recent_tmp	times 20 db 0
clk_time	times 24 db 0
clk_date	times 32 db 0
hot_tab		times 64 * 20 db 0

; ==================================================================

