#!/bin/sh
# Boot GMU OS 64 in QEMU with UEFI firmware (OVMF)
cd "$(dirname "$0")"
FW=firmware/OVMF.fd
[ -f "$FW" ] || FW=/usr/share/ovmf/OVMF.fd
[ -f build/gmuos64.img ] || ./make-image.sh
exec qemu-system-x86_64 -machine q35 -m 256 -bios "$FW" \
	-drive format=raw,file=build/gmuos64.img "$@"
