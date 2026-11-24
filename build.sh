#!/bin/sh
# Build GMU OS 64 (UEFI) -- needs only NASM
set -e
cd "$(dirname "$0")"
mkdir -p build
echo ">>> Assembling GMU OS 64 (BOOTX64.EFI)..."
nasm -O0 -w+orphan-labels -I source/ -f bin -o build/BOOTX64.EFI source/kernel.asm
ls -l build/BOOTX64.EFI
echo ">>> Assembling sample 64-bit programs..."
for i in programs/*.asm; do
	nasm -O0 -f bin -I source/ -I programs/ "$i" -o build/$(basename "$i" .asm | tr a-z A-Z).BIN
done
ls -l build/
