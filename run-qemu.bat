@echo off
rem Boot GMU OS 64 in QEMU (install QEMU for Windows: https://www.qemu.org/download/#windows)
rem Uses the UEFI firmware in firmware\OVMF.fd and the folder usb_files\ as a virtual USB/FAT disk.
set QEMU="C:\Program Files\qemu\qemu-system-x86_64.exe"
if not exist build\gmuos64.img goto :folder
%QEMU% -machine q35 -m 256 -bios firmware\OVMF.fd -drive format=raw,file=build\gmuos64.img
goto :eof
:folder
%QEMU% -machine q35 -m 256 -bios firmware\OVMF.fd -drive format=raw,file=fat:rw:usb_files
