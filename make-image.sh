#!/bin/sh
# Create a bootable GPT disk image (64 MB, FAT32 EFI System Partition)
# containing GMU OS 64.  Works for QEMU and can be written to a USB stick.
# Needs: sgdisk (gdisk), mtools.
set -e
cd "$(dirname "$0")"
[ -f build/BOOTX64.EFI ] || ./build.sh
IMG=build/gmuos64.img
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count=64 status=none
sgdisk -o -n 1:2048:0 -t 1:EF00 -c 1:"GMUOS64" "$IMG" >/dev/null
export MTOOLS_SKIP_CHECK=1
mformat -i "$IMG"@@1M -F -v GMUOS64 ::
mmd   -i "$IMG"@@1M ::/EFI ::/EFI/BOOT
mcopy -i "$IMG"@@1M build/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$IMG"@@1M files/* build/HELLO64.BIN ::/
echo ">>> Created $IMG"
mdir -i "$IMG"@@1M -/ ::
