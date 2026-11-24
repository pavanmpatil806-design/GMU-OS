; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2021 MikeOS Developers -- see doc/LICENSE.TXT
; GMU OS 64-bit edition
;
; PORT INPUT AND OUTPUT ROUTINES (64-bit version)
; ==================================================================


; ------------------------------------------------------------------
; os_port_byte_out -- Send byte to a port
; IN: DX = port address, AL = byte to send

os_port_byte_out:
	out dx, al
	ret


; ------------------------------------------------------------------
; os_port_byte_in -- Receive byte from a port
; IN: DX = port address; OUT: AL = byte from port

os_port_byte_in:
	in al, dx
	ret


; ------------------------------------------------------------------
; os_serial_port_enable -- Set up COM1 for transmitting data
; IN: AX = 0 for normal mode (9600 baud), or 1 for slow mode (1200 baud)

os_serial_port_enable:
	push rax
	push rdx
	push rcx
	mov cl, 12				; Divisor for 9600 baud
	cmp ax, 1
	jne .set
	mov cl, 96				; Divisor for 1200 baud
.set:
	mov dx, 3F9h
	xor al, al
	out dx, al				; No interrupts
	mov dx, 3FBh
	mov al, 80h
	out dx, al				; Divisor latch on
	mov dx, 3F8h
	mov al, cl
	out dx, al
	mov dx, 3F9h
	xor al, al
	out dx, al
	mov dx, 3FBh
	mov al, 03h				; 8 data bits, no parity, 1 stop bit
	out dx, al
	mov dx, 3FAh
	mov al, 0C7h
	out dx, al
	pop rcx
	pop rdx
	pop rax
	xor eax, eax
	ret


; ------------------------------------------------------------------
; os_send_via_serial -- Send a byte via the serial port
; IN: AL = byte to send via serial; OUT: AH = Bit 7 clear on success

os_send_via_serial:
	push rcx
	push rdx
	mov ah, al
	mov ecx, 100000
.wait:
	mov dx, 3FDh
	in al, dx
	test al, 20h				; Transmit holding register empty?
	jnz .ready
	loop .wait
	mov al, ah
	mov ah, 80h				; Timed out
	jmp .out
.ready:
	mov dx, 3F8h
	mov al, ah
	out dx, al
	xor ah, ah
.out:
	pop rdx
	pop rcx
	ret


; ------------------------------------------------------------------
; os_get_via_serial -- Get a byte from the serial port
; OUT: AL = byte that was received; OUT: AH = Bit 7 clear on success

os_get_via_serial:
	push rdx
	mov dx, 3FDh
	in al, dx
	test al, 01h				; Data ready?
	jz .nodata
	mov dx, 3F8h
	in al, dx
	xor ah, ah
	pop rdx
	ret
.nodata:
	xor al, al
	mov ah, 80h
	pop rdx
	ret


; ==================================================================
