@echo off
rem Build GMU OS 64 (UEFI) on Windows -- needs only NASM (https://www.nasm.us)
rem Result: build\BOOTX64.EFI and the ready-to-copy folder usb_files\

if not exist build mkdir build
echo >>> Assembling GMU OS 64 (BOOTX64.EFI)...
nasm -O0 -w+orphan-labels -I source/ -f bin -o build\BOOTX64.EFI source\kernel.asm || goto :error

echo >>> Assembling sample 64-bit programs...
for %%i in (programs\*.asm) do nasm -O0 -f bin -I source/ -I programs/ %%i -o build\%%~ni.BIN || goto :error

echo >>> Preparing usb_files\ ...
if not exist usb_files\EFI\BOOT mkdir usb_files\EFI\BOOT
copy /Y build\BOOTX64.EFI usb_files\EFI\BOOT\BOOTX64.EFI >nul
copy /Y files\*.* usb_files\ >nul
copy /Y build\HELLO64.BIN usb_files\HELLO64.BIN >nul

echo >>> Done!  Copy the CONTENTS of usb_files\ to the root of a FAT32 USB stick.
goto :eof

:error
echo *** Build failed
exit /b 1
