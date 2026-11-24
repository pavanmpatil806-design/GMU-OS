; ==================================================================
; GMU OS 64 -- graphics core (UEFI Graphics Output Protocol)
;
; Everything is drawn into a back buffer in memory (32-bit pixels
; 0x00RRGGBB) and copied to the real frame buffer with gfx_present.
; All drawing routines clip to the screen.
; ==================================================================

GFX_ICON48	equ 48 * 48 * 4
GFX_ICON32	equ 32 * 32 * 4

; ------------------------------------------------------------------
; gop_select_mode -- choose a 16:9-ish mode, set it and read its layout
; OUT: carry set on failure

gop_select_mode:
	mov rax, [gop]
	mov rax, [rax + 24]			; EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE
	mov ecx, [rax]				; MaxMode
	mov [gm_max], ecx
	mov dword [gm_best], -1
	mov dword [gm_bestscore], 0
	xor ebx, ebx
.loop:
	cmp ebx, [gm_max]
	jae .done
	mov rcx, [gop]
	mov edx, ebx
	lea r8, [rel gm_size]
	lea r9, [rel gm_info]
	mov rax, [rcx]				; QueryMode
	call efi_thunk
	test rax, rax
	jnz .next
	mov rsi, [gm_info]
	mov eax, [rsi + 12]			; PixelFormat: 0 = RGB, 1 = BGR are usable
	cmp eax, 1
	ja .next
	mov r8d, [rsi + 4]
	mov r9d, [rsi + 8]
	lea rdi, [rel gm_prefs]
.pref:
	mov eax, [rdi]
	test eax, eax
	jz .next
	cmp eax, r8d
	jne .pn
	cmp [rdi + 4], r9d
	jne .pn
	mov eax, [rdi + 8]
	cmp eax, [gm_bestscore]
	jbe .next
	mov [gm_bestscore], eax
	mov [gm_best], ebx
	jmp .next
.pn:
	add rdi, 12
	jmp .pref
.next:
	inc ebx
	jmp .loop
.done:
	cmp dword [gm_best], -1
	jne .set
	mov rax, [gop]				; nothing preferred: stay in the current mode
	mov rax, [rax + 24]
	mov ecx, [rax + 4]
	mov [gm_best], ecx
.set:
	mov rcx, [gop]
	mov edx, [gm_best]
	mov rax, [rcx + 8]			; SetMode
	call efi_thunk
	test rax, rax
	jnz .fail
	mov rax, [gop]
	mov rax, [rax + 24]
	mov rsi, [rax + 8]			; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION
	mov ecx, [rsi + 4]
	mov [gW], ecx
	mov ecx, [rsi + 8]
	mov [gH], ecx
	mov ecx, [rsi + 12]
	mov [gFmt], ecx
	cmp ecx, 1
	ja .fail
	mov ecx, [rsi + 32]			; PixelsPerScanLine
	shl ecx, 2
	mov [gFbStride], ecx
	mov rcx, [rax + 24]			; FrameBufferBase
	mov [gFbBase], rcx
	test rcx, rcx
	jz .fail
	mov ecx, [gW]
	cmp ecx, 640
	jb .fail
	cmp ecx, 4000
	ja .fail
	shl ecx, 2
	mov [gPitch], ecx
	clc
	ret
.fail:
	stc
	ret

; ------------------------------------------------------------------
; gfx_ensure_mode -- the text console (or the firmware) may change the graphics
; mode, resolution, address or line length behind our back, which shows up as
; a sheared, striped screen.  Re-assert our mode and re-read the layout.

gfx_ensure_mode:
	pushall
	mov rax, [gop]
	mov rax, [rax + 24]			; Mode
	mov ecx, [rax + 4]			; current mode number
	cmp ecx, [gm_best]
	jne .reset
	mov rsi, [rax + 8]			; Info
	mov ecx, [rsi + 4]
	cmp ecx, [gW]
	jne .reset
	mov ecx, [rsi + 8]
	cmp ecx, [gH]
	jne .reset
	jmp .refresh
.reset:
	mov rcx, [gop]
	mov edx, [gm_best]
	mov rax, [rcx + 8]			; SetMode
	call efi_thunk
	mov rax, [gop]
	mov rax, [rax + 24]
.refresh:
	mov rsi, [rax + 8]
	mov ecx, [rsi + 32]			; PixelsPerScanLine
	shl ecx, 2
	mov [gFbStride], ecx
	mov ecx, [rsi + 12]
	cmp ecx, 1
	ja .keepfmt
	mov [gFmt], ecx
.keepfmt:
	mov rcx, [rax + 24]			; FrameBufferBase
	test rcx, rcx
	jz .out
	mov [gFbBase], rcx
.out:
	popall
	ret

; ------------------------------------------------------------------
; gfx_clip -- clip the rectangle EAX=x EBX=y ECX=w EDX=h to the screen
; OUT: clipped values, carry set if nothing is left

gfx_clip:
	lea esi, [rax + rcx]			; right edge
	lea edi, [rbx + rdx]			; bottom edge
	test eax, eax
	jns .x0
	xor eax, eax
.x0:
	test ebx, ebx
	jns .y0
	xor ebx, ebx
.y0:
	cmp esi, [gW]
	jle .x1
	mov esi, [gW]
.x1:
	cmp edi, [gH]
	jle .y1
	mov edi, [gH]
.y1:
	mov ecx, esi
	sub ecx, eax
	jle .empty
	mov edx, edi
	sub edx, ebx
	jle .empty
	clc
	ret
.empty:
	stc
	ret

; gfx_ptr -- RDI = address in the back buffer of pixel (EAX, EBX)
gfx_ptr:
	mov edi, ebx
	imul edi, [gPitch]
	mov esi, eax
	shl esi, 2
	add edi, esi
	add rdi, [gBack]
	ret

; ------------------------------------------------------------------
; px_blend -- blend one pixel   RDI = destination, R8D = colour, R9D = alpha 0..256
; Clobbers EAX, ECX, EDX

px_blend:
	mov eax, [rdi]
	mov ecx, 256
	sub ecx, r9d
	mov edx, eax
	and eax, 0x00FF00FF
	and edx, 0x0000FF00
	imul eax, ecx
	imul edx, ecx
	mov ecx, r8d
	and ecx, 0x00FF00FF
	imul ecx, r9d
	add eax, ecx
	mov ecx, r8d
	and ecx, 0x0000FF00
	imul ecx, r9d
	add edx, ecx
	shr eax, 8
	and eax, 0x00FF00FF
	shr edx, 8
	and edx, 0x0000FF00
	or eax, edx
	mov [rdi], eax
	ret

; ------------------------------------------------------------------
; gfx_fill -- opaque rectangle   EAX=x EBX=y ECX=w EDX=h R8D=colour

gfx_fill:
	pushall
	mov r10d, r8d
	call gfx_clip
	jc .out
	mov r9d, edx				; rows
	mov r11d, ecx				; width
	call gfx_ptr
	mov eax, r10d
.row:
	mov ecx, r11d
	push rdi
	rep stosd
	pop rdi
	mov ecx, [gPitch]
	add rdi, rcx
	dec r9d
	jnz .row
.out:
	popall
	ret

; ------------------------------------------------------------------
; gfx_rrect -- rounded rectangle blended with alpha
;   EAX=x EBX=y ECX=w EDX=h R8D=colour R9D=alpha(0..256) R10D=radius (0 = square)

gfx_rrect:
	pushall
	mov [rr_x], eax
	mov [rr_y], ebx
	mov [rr_w], ecx
	mov [rr_h], edx
	mov [rr_col], r8d
	mov [rr_alpha], r9d
	mov [rr_r], r10d
	xor ebx, ebx				; row index
.row:
	cmp ebx, [rr_h]
	jae .out
	; inset of this row (rounded corners)
	xor esi, esi
	mov eax, [rr_r]
	test eax, eax
	jz .noinset
	mov ecx, ebx				; distance from the nearest top/bottom edge
	mov edx, [rr_h]
	dec edx
	sub edx, ebx
	cmp edx, ecx
	jae .dist
	mov ecx, edx
.dist:
	cmp ecx, eax
	jae .noinset
	mov edx, eax
	sub edx, ecx				; dy = r - dist  (1..r)
	imul edx, edx
	mov ecx, eax
	imul ecx, ecx
	sub ecx, edx				; r*r - dy*dy
	xor edi, edi				; isqrt
.isq:
	lea edx, [rdi + 1]
	imul edx, edx
	cmp edx, ecx
	ja .isqd
	inc edi
	jmp .isq
.isqd:
	mov esi, eax
	sub esi, edi				; inset = r - isqrt(...)
.noinset:
	mov eax, [rr_x]
	add eax, esi
	mov ecx, [rr_w]
	sub ecx, esi
	sub ecx, esi
	jle .nextrow
	push rbx
	add ebx, [rr_y]
	mov edx, 1
	call gfx_clip
	jc .skip
	mov r11d, ecx
	call gfx_ptr
	mov r8d, [rr_col]
	mov r9d, [rr_alpha]
	cmp r9d, 256
	jb .blend
	mov eax, r8d
	mov ecx, r11d
	rep stosd
	jmp .skip
.blend:
	mov ecx, r11d
.px:
	push rcx
	call px_blend
	pop rcx
	add rdi, 4
	dec ecx
	jnz .px
.skip:
	pop rbx
.nextrow:
	inc ebx
	jmp .row
.out:
	popall
	ret

; ------------------------------------------------------------------
; gfx_present -- copy a rectangle of the back buffer to the screen
;   EAX=x EBX=y ECX=w EDX=h

gfx_present:
	pushall
	call gfx_clip
	jc .out
	mov r8d, ecx
	mov r9d, edx
	call gfx_ptr
	mov r10, rdi				; source
	mov edi, ebx
	imul edi, [gFbStride]
	mov esi, eax
	shl esi, 2
	add edi, esi
	add rdi, [gFbBase]
	mov r11, rdi				; destination
.row:
	mov rsi, r10
	mov rdi, r11
	mov ecx, r8d
	cmp dword [gFmt], 0
	jne .bgr
.rgb:					; frame buffer wants R,G,B,x byte order
	lodsd
	bswap eax
	shr eax, 8
	stosd
	dec ecx
	jnz .rgb
	jmp .next
.bgr:
	rep movsd
.next:
	mov eax, [gPitch]
	add r10, rax
	mov eax, [gFbStride]
	add r11, rax
	dec r9d
	jnz .row
.out:
	popall
	ret

; ------------------------------------------------------------------
; gfx_text -- draw a string using the font in cur_font
;   EAX=x EBX=y RSI=string R8D=colour ; [txt_alpha] = 0..256

gfx_text:
	pushall
	mov [t_x], eax
	mov [t_y], ebx
	mov [t_col], r8d
	mov [t_str], rsi
.nextch:
	mov rsi, [t_str]
	movzx eax, byte [rsi]
	test eax, eax
	jz .done
	inc qword [t_str]
	cmp eax, 32
	jb .q
	cmp eax, 126
	jbe .ok
.q:
	mov eax, '?'
.ok:
	sub eax, 32
	mov rdx, [cur_font]
	lea rcx, [rdx + 2 + rax*4]
	movzx eax, byte [rcx]
	mov [t_adv], eax
	movzx eax, byte [rcx + 1]
	mov [t_w], eax
	movzx eax, word [rcx + 2]
	movzx ebx, byte [rdx]
	mov [t_h], ebx
	lea rsi, [rdx + 2 + 95*4]
	add rsi, rax				; RSI = glyph alpha data
	xor ebx, ebx				; row
.row:
	cmp ebx, [t_h]
	jae .rowsdone
	mov eax, [t_y]
	add eax, ebx
	cmp eax, [gH]
	jae .advance
	imul eax, [gPitch]
	mov rdi, [gBack]
	add rdi, rax
	mov [t_rowptr], rdi
	xor r11d, r11d
.col:
	cmp r11d, [t_w]
	jae .advance
	movzx eax, byte [rsi + r11]
	test eax, eax
	jz .nc
	mov edx, [t_x]
	add edx, r11d
	cmp edx, [gW]
	jae .nc
	mov r9d, eax
	shr eax, 7
	add r9d, eax
	imul r9d, [txt_alpha]
	shr r9d, 8
	mov rdi, [t_rowptr]
	lea rdi, [rdi + rdx*4]
	mov r8d, [t_col]
	call px_blend
.nc:
	inc r11d
	jmp .col
.advance:
	mov eax, [t_w]
	add rsi, rax
	inc ebx
	jmp .row
.rowsdone:
	mov eax, [t_adv]
	add [t_x], eax
	jmp .nextch
.done:
	popall
	ret

; gfx_text_width -- RSI = string -> EAX = width in pixels (font in cur_font)
gfx_text_width:
	push rcx
	push rdx
	push rsi
	xor ecx, ecx
	mov rdx, [cur_font]
.l:
	movzx eax, byte [rsi]
	inc rsi
	test eax, eax
	jz .d
	cmp eax, 32
	jb .q
	cmp eax, 126
	jbe .ok
.q:
	mov eax, '?'
.ok:
	sub eax, 32
	movzx eax, byte [rdx + 2 + rax*4]
	add ecx, eax
	jmp .l
.d:
	mov eax, ecx
	pop rsi
	pop rdx
	pop rcx
	ret

; gfx_text_shadow -- like gfx_text, with a soft drop shadow (for desktop labels)
gfx_text_shadow:
	pushall
	mov r10d, r8d
	push rax
	push rbx
	inc eax
	inc ebx
	xor r8d, r8d
	mov edx, [txt_alpha]
	push rdx
	mov dword [txt_alpha], 170
	call gfx_text
	pop rdx
	mov [txt_alpha], edx
	pop rbx
	pop rax
	mov r8d, r10d
	call gfx_text
	popall
	ret

; ------------------------------------------------------------------
; gfx_icon -- draw a square RGBA icon (pixels 0xAARRGGBB)
;   EAX=x EBX=y RSI=pixels ECX=size

gfx_icon:
	pushall
	mov [t_x], eax
	mov [t_y], ebx
	mov [t_w], ecx
	xor ebx, ebx				; row
.row:
	cmp ebx, [t_w]
	jae .out
	mov eax, [t_y]
	add eax, ebx
	cmp eax, [gH]
	jae .skiprow
	imul eax, [gPitch]
	mov rdi, [gBack]
	add rdi, rax
	mov [t_rowptr], rdi
	xor r11d, r11d
.col:
	cmp r11d, [t_w]
	jae .rowend
	mov r8d, [rsi + r11*4]
	mov eax, r8d
	shr eax, 24				; alpha
	jz .nc
	mov edx, [t_x]
	add edx, r11d
	cmp edx, [gW]
	jae .nc
	mov r9d, eax
	shr eax, 7
	add r9d, eax
	mov rdi, [t_rowptr]
	lea rdi, [rdi + rdx*4]
	and r8d, 0x00FFFFFF
	call px_blend
.nc:
	inc r11d
	jmp .col
.rowend:
.skiprow:
	mov eax, [t_w]
	lea rsi, [rsi + rax*4]
	inc ebx
	jmp .row
.out:
	popall
	ret

; ------------------------------------------------------------------
; gfx_mask -- draw an 8-bit alpha image in one colour
;   EAX=x EBX=y RSI=image (word width, word height, bytes) R8D=colour R9D=max alpha 0..256

gfx_mask:
	pushall
	mov [t_x], eax
	mov [t_y], ebx
	mov [t_col], r8d
	mov [t_aa], r9d
	movzx eax, word [rsi]
	mov [t_w], eax
	movzx eax, word [rsi + 2]
	mov [t_h], eax
	add rsi, 4
	xor ebx, ebx
.row:
	cmp ebx, [t_h]
	jae .out
	mov eax, [t_y]
	add eax, ebx
	cmp eax, [gH]
	jae .skip
	imul eax, [gPitch]
	mov rdi, [gBack]
	add rdi, rax
	mov [t_rowptr], rdi
	xor r11d, r11d
.col:
	cmp r11d, [t_w]
	jae .skip
	movzx eax, byte [rsi + r11]
	test eax, eax
	jz .nc
	mov edx, [t_x]
	add edx, r11d
	cmp edx, [gW]
	jae .nc
	mov r9d, eax
	shr eax, 7
	add r9d, eax
	imul r9d, [t_aa]
	shr r9d, 8
	mov rdi, [t_rowptr]
	lea rdi, [rdi + rdx*4]
	mov r8d, [t_col]
	call px_blend
.nc:
	inc r11d
	jmp .col
.skip:
	mov eax, [t_w]
	add rsi, rax
	inc ebx
	jmp .row
.out:
	popall
	ret

; ------------------------------------------------------------------
; lerp32 -- EAX = a, EDX = b, ECX = t (0..255)  ->  EAX = a + (b-a)*t/256 per channel
; Clobbers ECX, EDX, R9D

lerp32:
	push rbx
	push rsi
	mov esi, 256
	sub esi, ecx
	mov ebx, eax
	and eax, 0x00FF00FF
	imul eax, esi
	mov r9d, edx
	and r9d, 0x00FF00FF
	imul r9d, ecx
	add eax, r9d
	shr eax, 8
	and eax, 0x00FF00FF
	and ebx, 0x0000FF00
	imul ebx, esi
	and edx, 0x0000FF00
	imul edx, ecx
	add ebx, edx
	shr ebx, 8
	and ebx, 0x0000FF00
	or eax, ebx
	pop rsi
	pop rbx
	ret

; ------------------------------------------------------------------
; gfx_make_wall -- scale the small wallpaper image up to the screen (bilinear)
; into gWall

gfx_make_wall:
	pushall
	lea rsi, [rel wall_data]
	movzx r10d, word [rsi]			; wallpaper width
	movzx r11d, word [rsi + 2]		; wallpaper height
	mov [wl_w], r10d
	mov [wl_h], r11d
	; horizontal position table: 8.8 fixed point source x for every screen x
	lea rdi, [rel xt_tab]
	xor ebx, ebx
.xt:
	cmp ebx, [gW]
	jae .xtd
	mov eax, ebx
	mov ecx, [wl_w]
	dec ecx
	shl ecx, 8
	imul rax, rcx
	xor edx, edx
	mov ecx, [gW]
	dec ecx
	div rcx
	mov [rdi + rbx*4], eax
	inc ebx
	jmp .xt
.xtd:
	xor ebx, ebx				; screen row
.yl:
	cmp ebx, [gH]
	jae .done
	mov eax, ebx
	mov ecx, [wl_h]
	dec ecx
	shl ecx, 8
	imul rax, rcx
	xor edx, edx
	mov ecx, [gH]
	dec ecx
	div rcx					; EAX = 8.8 source y
	mov r10d, eax
	and r10d, 255				; fy
	shr eax, 8				; iy
	mov r11d, eax
	mov ecx, [wl_w]
	imul eax, ecx
	lea rsi, [rel wall_data + 4]
	lea rsi, [rsi + rax*4]			; source row 0
	mov dword [t_rd], 0
	lea ecx, [r11 + 1]
	cmp ecx, [wl_h]
	jae .norow1				; last wallpaper row: no row below
	mov eax, [wl_w]
	shl eax, 2
	mov [t_rd], eax
.norow1:
	mov edi, ebx
	imul edi, [gPitch]
	add rdi, [gWall]
	xor ebp, ebp
.xl:
	lea rax, [rel xt_tab]
	mov eax, [rax + rbp*4]
	mov edx, eax
	shr eax, 8				; ix
	and edx, 255				; fx
	mov [t_fx], edx
	lea rax, [rsi + rax*4]
	mov [t_p], rax
	mov edx, [rax + 4]
	mov eax, [rax]
	mov ecx, [t_fx]
	call lerp32
	mov [t_h0], eax
	mov rax, [t_p]
	mov edx, [t_rd]
	add rax, rdx
	mov edx, [rax + 4]
	mov eax, [rax]
	mov ecx, [t_fx]
	call lerp32
	mov edx, eax
	mov eax, [t_h0]
	mov ecx, r10d
	call lerp32
	mov [rdi], eax
	add rdi, 4
	inc ebp
	cmp ebp, [gW]
	jb .xl
	inc ebx
	jmp .yl
.done:
	popall
	ret

; ------------------------------------------------------------------
; mouse pointer sprite

; gfx_cursor_erase -- restore the screen under the pointer at (old_x, old_y)
gfx_cursor_erase:
	pushall
	mov eax, [old_x]
	mov ebx, [old_y]
	mov ecx, 14
	mov edx, 20
	call gfx_present
	popall
	ret

; gfx_cursor_draw -- draw the pointer sprite straight into the frame buffer at (cur_x, cur_y)
gfx_cursor_draw:
	pushall
	lea rsi, [rel cursor_data]
	movzx r8d, byte [rsi]			; width
	movzx r9d, byte [rsi + 1]		; height
	add rsi, 2
	xor ebx, ebx
.row:
	cmp ebx, r9d
	jae .out
	mov eax, [cur_y]
	add eax, ebx
	cmp eax, [gH]
	jae .out
	imul eax, [gFbStride]
	mov rdi, [gFbBase]
	add rdi, rax
	xor ecx, ecx
.col:
	cmp ecx, r8d
	jae .nextrow
	movzx eax, byte [rsi]
	inc rsi
	test eax, eax
	jz .nc
	mov edx, [cur_x]
	add edx, ecx
	cmp edx, [gW]
	jae .nc
	cmp eax, 1
	mov eax, 0x00000000			; outline
	jz .put
	mov eax, 0x00FFFFFF			; fill
.put:
	mov [rdi + rdx*4], eax
.nc:
	inc ecx
	jmp .col
.nextrow:
	inc ebx
	jmp .row
.out:
	popall
	ret

; ==================================================================
; ASSETS (generated by tools/gen_assets.py)
; ==================================================================

font_ui:	incbin "assets/font_ui.bin"
font_bold:	incbin "assets/font_bold.bin"
font_big:	incbin "assets/font_big.bin"
title_img:	incbin "assets/title.bin"
subtitle_img:	incbin "assets/subtitle.bin"
icons48:	incbin "assets/icons48.bin"
icons32:	incbin "assets/icons32.bin"
cursor_data:	incbin "assets/cursor.bin"
wall_data:	incbin "assets/wall.bin"
	times 16 db 0

; preferred graphics modes: width, height, score (higher = better)
gm_prefs:
	dd 1280, 720, 6
	dd 1366, 768, 5
	dd 1280, 800, 4
	dd 1024, 768, 3
	dd 1600, 900, 2
	dd 800, 600, 1
	dd 0, 0, 0

; ==================================================================
; DATA
; ==================================================================

gop		dq 0
gFbBase		dq 0
gBack		dq 0
gWall		dq 0
gW		dd 0
gH		dd 0
gPitch		dd 0
gFbStride	dd 0
gFmt		dd 0
gm_max		dd 0
gm_best		dd 0
gm_bestscore	dd 0
gm_size		dq 0
gm_info		dq 0
rr_x		dd 0
rr_y		dd 0
rr_w		dd 0
rr_h		dd 0
rr_col		dd 0
rr_alpha	dd 0
rr_r		dd 0
t_x		dd 0
t_y		dd 0
t_col		dd 0
t_w		dd 0
t_h		dd 0
t_adv		dd 0
t_aa		dd 0
t_fx		dd 0
t_h0		dd 0
t_rd		dd 0
t_str		dq 0
t_rowptr	dq 0
t_p		dq 0
wl_w		dd 0
wl_h		dd 0
cur_font	dq 0
txt_alpha	dd 256
cur_x		dd 0
cur_y		dd 0
old_x		dd 0
old_y		dd 0

; ==================================================================
