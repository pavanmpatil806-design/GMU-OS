# GMU OS 64

GMU OS 64 is a small 64-bit operating system written as an educational learning project at GM University, Davangere. It is a UEFI application derived from MikeOS, with a graphical desktop, command-line interface, C compiler and editor, simple 64-bit programs, and support for FAT32/FAT16 storage devices.

This project is **not** a general-purpose operating system. It does not provide Linux or Windows compatibility, virtual memory management, processes, protected multi-user accounts, or broad hardware driver support. It is best understood as a compact operating-system teaching example that runs on real 64-bit PCs or in QEMU.

## Contents

- [What this project contains](#what-this-project-contains)
- [How it starts](#how-it-starts)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Build the project](#build-the-project)
- [Run in QEMU](#run-in-qemu)
- [Run from a USB drive](#run-from-a-usb-drive)
- [Using the desktop](#using-the-desktop)
- [Using the command line](#using-the-command-line)
- [Working with files and USB drives](#working-with-files-and-usb-drives)
- [Running and writing 64-bit programs](#running-and-writing-64-bit-programs)
- [Using the C compiler](#using-the-c-compiler)
- [Printing](#printing)
- [Using the disk image](#using-the-disk-image)
- [Project layout](#project-layout)
- [How the code works](#how-the-code-works)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [License](#license)

## What this project contains

The project currently provides:

- A hand-written PE32+ UEFI executable for x86-64
- A graphical 1280x720 desktop when graphics firmware support is available
- A text command-line interface
- Keyboard and mouse input
- A FAT32/FAT16 file system rooted at the boot volume
- Detection of additional USB storage devices
- File operations: list, copy, rename, delete, create, and print
- Command history using the Up and Down arrow keys
- 64-bit flat binary programs with a small system-call interface
- A built-in C-like compiler and editor
- Basic USB printer detection and printing
- Time, date, calculator, and system information commands
- QEMU scripts and an included OVMF firmware image

## How it starts

The firmware loads the kernel as a UEFI application from:

```text
\EFI\BOOT\BOOTX64.EFI
```

The startup sequence is:

1. UEFI loads `BOOTX64.EFI` and starts `efi_main`.
2. The kernel stores the UEFI system table and boot services.
3. The watchdog timer is disabled.
4. The text console and extended keyboard protocol are initialized.
5. GMU OS allocates memory and finds the filesystem from which it booted.
6. It scans for other connected USB storage devices.
7. It checks for `AUTORUN.BIN`:
   - If present, it loads and executes that file.
   - Otherwise, it starts the graphical desktop.
8. If graphical mode is unavailable or `NOGUI.TXT` exists on the boot device, it starts the text interface.

GMU OS runs after UEFI has already initialized the processor and hardware. It does not switch the PC from BIOS mode or 16-bit real mode. This differs from the original 16-bit MikeOS design.

## Prerequisites

### To build from source

The build scripts require **NASM** (the Netwide Assembler).

- Linux or WSL: use a NASM package from your distribution.
- Windows: install NASM and make sure `nasm.exe` is available in `PATH`.

The generated source assets are already included in `source/assets/`, so NASM is the only tool required for the normal kernel build.

### To create the disk image

Creating `build/gmuos64.img` requires Linux tools:

- `sgdisk` or `gdisk`
- `mtools`
- `dd`

The scripts support Linux and WSL. They are not a native Windows disk-image builder.

### To run in QEMU

Install QEMU.

- Linux package typically named `qemu-system-x86`
- Windows: QEMU for Windows
- WSL: install QEMU inside Linux/WSL

The project includes `firmware/OVMF.fd`, so the normal scripts do not require a system OVMF package.

### To run from a real PC

You need:

- A 64-bit PC with UEFI firmware
- A FAT32 USB flash drive
- Access to the UEFI boot menu
- Secure Boot disabled if the PC refuses unsigned UEFI executables

`BOOTX64.EFI` is unsigned. A PC with Secure Boot enabled may prevent it from starting.

## Quick start

### Linux or WSL

From the project directory:

```sh
chmod +x build.sh make-image.sh run-qemu.sh
./build.sh
./make-image.sh
./run-qemu.sh
```

The first command creates `build/BOOTX64.EFI` and sample `.BIN` programs. The second creates `build/gmuos64.img`. The final command boots the image in QEMU.

### Windows

Open Command Prompt in the project directory and run:

```bat
buildwin.bat
run-qemu.bat
```

`buildwin.bat` creates the EFI executable and sample programs, and prepares `usb_files/`. `run-qemu.bat` requires QEMU to be installed at:

```text
C:\Program Files\qemu\qemu-system-x86_64.exe
```

If QEMU is installed somewhere else, update `run-qemu.bat` or start QEMU using the manual command in [Run in QEMU](#run-in-qemu).

## Build the project

### Linux build

`build.sh`:

1. Changes into the project directory.
2. Creates `build/`.
3. Assembles `source/kernel.asm` into `build/BOOTX64.EFI`.
4. Assembles every `.asm` file in `programs/` into an uppercase `.BIN` filename in `build/`.

Run:

```sh
./build.sh
```

The direct NASM command used for the kernel is:

```sh
nasm -O0 -w+orphan-labels -I source/ -f bin \
  -o build/BOOTX64.EFI source/kernel.asm
```

The direct NASM command for `hello64.asm` is:

```sh
nasm -O0 -f bin -I source/ -I programs/ \
  -o build/HELLO64.BIN programs/hello64.asm
```

### Windows build

Run:

```bat
buildwin.bat
```

It produces:

```text
build\BOOTX64.EFI
build\HELLO64.BIN
usb_files\EFI\BOOT\BOOTX64.EFI
usb_files\HELLO64.BIN
usb_files\<contents of the files folder>
```

The script does not require a C compiler or a separate linker. NASM builds the entire kernel as a custom PE32+ UEFI executable.

### Optional: regenerate desktop assets

The desktop graphics files are already in `source/assets/`. You normally do not need to regenerate them.

To regenerate them, install Python, Pillow, and NumPy, then run:

```sh
python3 tools/gen_assets.py
```

This script recreates fonts, the wallpaper, icons, and the mouse cursor under `source/assets/`. It assumes an Inter font is installed at:

```text
/usr/share/fonts/opentype/inter/
```

It will not run on a machine that does not contain that font directory.

## Run in QEMU

### Linux or WSL

Build and create the image first:

```sh
./build.sh
./make-image.sh
./run-qemu.sh
```

`run-qemu.sh`:

- Creates the disk image if `build/gmuos64.img` does not exist.
- Searches for `/usr/share/ovmf/OVMF.fd` if the project copy cannot be used.
- Starts QEMU with the 64 MB image.

You can pass additional QEMU arguments after the script name:

```sh
./run-qemu.sh -serial stdio
```

### Windows

After building:

```bat
run-qemu.bat
```

The script uses `firmware\OVMF.fd` and `build\gmuos64.img`. If the image does not exist, it falls back to exposing `usb_files\` as a FAT disk.

### Manual QEMU command

```sh
qemu-system-x86_64 \
  -machine q35 \
  -m 256 \
  -bios firmware/OVMF.fd \
  -drive format=raw,file=build/gmuos64.img
```

On Windows, quote paths containing spaces:

```bat
"C:\Program Files\qemu\qemu-system-x86_64.exe" ^
  -machine q35 -m 256 ^
  -bios firmware\OVMF.fd ^
  -drive format=raw,file=build\gmuos64.img
```

### Exit QEMU

Use QEMU's close button or monitor controls. The guest can run `SHUTDOWN` from the command line or use the desktop shutdown menu.

## Run from a USB drive

This is the full real-hardware procedure.

### 1. Back up the USB drive

This process formats the disk image or the drive and can erase existing data. Back up anything you need first.

### 2. Build the project

On Linux or WSL:

```sh
./build.sh
```

On Windows:

```bat
buildwin.bat
```

### 3. Format the USB drive as FAT32

Windows users can:

1. Open File Explorer.
2. Right-click the USB drive.
3. Select **Format**.
4. Choose **FAT32**.
5. Start the format.

The boot volume must be readable by UEFI and is the volume that GMU OS uses for its files.

### 4. Copy the files

Copy the **contents** of `usb_files/`, not the `usb_files` folder itself, to the root of the USB drive.

After copying, the EFI executable must exist at:

```text
<USB ROOT>\EFI\BOOT\BOOTX64.EFI
```

For example:

```text
E:\EFI\BOOT\BOOTX64.EFI
E:\HELLO64.BIN
E:\README.TXT
```

Do not rename `BOOTX64.EFI` or place it outside `EFI\BOOT`.

### 5. Select the USB from the PC firmware

Restart the PC and open the firmware boot menu. The key differs between manufacturers:

- F12
- F10
- F9
- Esc

Choose the entry that identifies the USB device as UEFI, for example:

```text
UEFI: SanDisk USB
```

### 6. Disable Secure Boot if necessary

Open BIOS/UEFI Setup and locate the Security or Boot section. If Secure Boot rejects the unsigned executable, temporarily disable Secure Boot and restart.

### Alternative: write the disk image

`build/gmuos64.img` is a 64 MB GPT disk containing a FAT32 EFI system partition.

You can write it using:

- Rufus in **DD Image** mode
- balenaEtcher
- an equivalent raw-disk image writer

Writing this image erases the target drive.

Do not copy the image file onto the existing filesystem and expect it to become bootable. It must be written to the drive at the raw disk level.

## Using the desktop

The desktop chooses a 1280x720 mode if the firmware offers it. It uses UEFI Graphics Output Protocol rather than VGA text mode.

### Mouse

The desktop supports:

- Pointer movement
- Left-click selection
- Double-click activation
- The Start/G button
- Desktop and taskbar icons

The mouse is only shown if the UEFI firmware exposes a usable mouse or pointing device. A firmware mouse may not be available on every laptop or embedded PC.

### Keyboard desktop controls

Keyboard input works even when mouse support is unavailable:

- Arrow keys move the mouse pointer.
- Tab moves to the next clickable item.
- Enter activates or opens the focused item.
- Esc closes a menu or window.

The desktop is useful for navigation, but the terminal and command line provide the most complete interface.

### Desktop icons

Available icons include:

- My Computer
- Documents
- Pictures
- Terminal
- C Compiler / Editor
- File Manager
- Settings
- Recycle
- Printer

Some items are placeholders for future development. Double-click **Terminal** to enter the command line. Enter `EXIT` to return from the terminal to the desktop.

### Force text mode

Create a file named `NOGUI.TXT` in the root of the boot volume to force text mode.

You can also leave it out and GMU OS will start text mode automatically if the desktop cannot initialize.

### Desktop fallback

The desktop can fall back to text mode when:

- Graphics Output Protocol is unavailable.
- A suitable screen mode is unavailable.
- Memory allocation fails.
- `NOGUI.TXT` exists.

## Using the command line

The command prompt is controlled with normal ASCII text input. Commands are generally case-insensitive.

Start examples:

```text
HELP
DIR
HELLO64
CC HELLO.C
C
```

Press Up or Down in the command prompt to recall the last 16 commands.

### General commands

| Command | Description |
|---|---|
| `HELP` | Show the command summary |
| `HELP <topic>` | Show help for a command |
| `DIR` | List files on the boot volume |
| `DIR *.C` | Filter files using an extension |
| `DIR USB` | Find and list files on other USB drives |
| `LS` | List files |
| `CAT FILE.TXT` | Display a text file |
| `SIZE FILE.TXT` | Display file size |
| `DEL FILE.TXT` | Delete a file |
| `COPY A.TXT B.TXT` | Copy a file |
| `REN OLD.TXT NEW.TXT` | Rename a file |
| `PASTE` | Paste a file copied into the clipboard |
| `PRINT FILE.TXT` | Send a text file to a printer |
| `PRINTER` | Detect and describe a printer |
| `CC FILE.C` | Compile and run a C file |
| `C` | Open or return to the C editor |
| `TIME` | Show current time |
| `DATE` | Show current date |
| `CAL` | Show date and time |
| `VER` | Show GMU OS version |
| `ABOUT` | Show project information |
| `GMUINFO` | Show project information |
| `PBL` | Show PBL project information |
| `CLS` | Clear the screen |
| `SHUTDOWN` | Ask UEFI to power off |
| `EXIT` | Exit the command-line interface |

`EXIT` behavior depends on how the command line was entered. From the desktop terminal icon, it returns to the desktop. In the standalone text startup path, it follows the kernel's text-interface behavior.

### Running a program

Programs can be started by full name:

```text
HELLO64.BIN
```

Or by name with its `.BIN` extension omitted:

```text
HELLO64
```

Parameters can follow the name:

```text
HELLO64 first second
```

The kernel passes the parameter text to the program.

GMU OS rejects old 16-bit binaries and displays a compatibility error. Programs must use the GMU64 flat-binary format.

## Working with files and USB drives

GMU OS is modeled after early MikeOS file handling: only the root directory is used. Subdirectory support is available for several operations when a directory path is used, but the normal command examples operate from the root.

### Boot drive names

Files on the boot drive can be addressed normally:

```text
CAT README.TXT
```

They can also be addressed explicitly:

```text
CAT BOOT:README.TXT
```

`BOOT:` means the volume from which GMU OS started.

### Additional USB drives

GMU OS asks UEFI to find and connect all volumes and then scans for FAT volumes not equal to the boot drive.

Additional volumes are named:

```text
USB1:
USB2:
USB3:
```

List them with:

```text
DIR USB
```

Use a name without spaces:

```text
CAT USB1:README.TXT
SIZE USB2:DATA.C
COPY USB1:DATA.C DATA.C
COPY DATA.C USB1:DATA.C
```

The following drive names work as file prefixes:

```text
BOOT:FILE.TXT
USB1:FILE.TXT
USB2:FILE.TXT
```

### Clipboard and file selection

Copy a source file into the internal clipboard:

```text
COPY FILE.TXT
```

Then paste it to the boot drive:

```text
PASTE
PASTE NEWNAME.TXT
```

Paste to another volume:

```text
PASTE USB2:
PASTE USB2:NEWNAME.TXT
```

`DIR` can enter an interactive file picker. Use the arrow keys to select a file and Enter to copy it to the clipboard. Esc cancels the selection.

### Supported storage volumes

UEFI file-system protocols are used instead of direct disk-sector access. FAT12, FAT16, and FAT32 support depends on the firmware.

NTFS and exFAT are not supported by the GMU OS disk routines. USB drives intended for GMU OS should be FAT32 or FAT16.

The OS hides system and metadata folders such as:

- `System Volume Information`
- `$` folders

### File limits

The kernel uses a 1 MB program/file allocation area. A practical file limit also comes from the design of individual routines.

Printing is separately limited to 256 KB and plain text files.

## Running and writing 64-bit programs

The example program is `programs/hello64.asm`.

### 64-bit binary format

A GMU OS binary must:

1. Begin with the 8-byte signature `GMU64BIN`.
2. Be position-independent 64-bit code.
3. Be loaded from or copied to the boot volume.
4. End with `RET`.

The kernel:

- Loads the file into the program area.
- Verifies the signature.
- Places the parameter string in `RSI`.
- Places the system-call table address in `RDI`.
- Calls code after the 8-byte signature.

Example entry:

```asm
BITS 64
DEFAULT REL

db 'GMU64BIN'
%include "mikedev64.inc"

start:
    OS_INIT
    mov [param], rsi

    lea rsi, [rel msg]
    oscall os_print_string
    ret

param dq 0
msg db 'Hello!', 13, 10, 0
```

Build it with:

```sh
nasm -O0 -f bin -I source/ -I programs/ \
  hello64.asm -o HELLO64.BIN
```

### System calls

Programs include `mikedev64.inc`, which:

- Defines all available vector names.
- Provides `OS_INIT`.
- Provides the `oscall` macro.

The vector list is in `source/vectors.inc`. It must remain in the same order in the kernel and external programs.

Example use:

```asm
OS_INIT
lea rsi, [rel message]
oscall os_print_string
```

Available calls include screen output, cursor movement, keyboard input, file operations, time and date, random numbers, dialogs, drawing, and serial access.

Not every MikeOS 16-bit call has been ported. Unsupported calls return an error or are marked as unavailable. In particular, BASIC execution and the original 16-bit register-dump calls are not implemented in 64-bit mode.

## Using the C compiler

GMU OS includes a compact C compiler. It does not compile native machine-code programs; it parses C source and executes bytecode inside GMU OS.

### Compile a file

Place a C file on the boot drive and run:

```text
CC HELLO.C
```

To compile a file from another USB drive:

```text
CC USB1:SORT.C
```

### Open the editor

Open the editor with an empty buffer:

```text
C
```

Open an existing file:

```text
C HELLO.C
```

You can also open the editor from the desktop C Compiler icon.

### Editor keys

| Key | Action |
|---|---|
| Enter | Compile and run |
| Shift+Enter | Insert a new line |
| Tab | Insert a new line if Shift cannot be detected |
| Arrow keys | Move the cursor |
| Home | Move to the start of a line |
| End | Move to the end of a line |
| Page Up / Page Down | Move through the editor |
| Backspace | Delete before the cursor |
| Delete | Delete after the cursor |
| F2 | Save |
| F3 | Clear and create new text |
| Esc | Leave the editor |

The text is retained when you leave with Esc.

After a compiled program finishes, press a key to return to the editor.

### Supported C features

The compiler supports:

- `int`, `char`, and `void`
- Global variables
- Local variables
- Global and local integer arrays
- Array initializers using `{ ... }`
- Functions
- Function parameters
- Recursive functions
- `if` / `else`
- `while`
- `for`, including integer declarations
- `break`
- `continue`
- `return`
- Arithmetic and bitwise operators
- Logical operators
- Comparisons
- Ternary `?:`
- Comma expressions
- `++`, `--`
- `+=`, `-=`, `*=`, `/=`, `%=` 
- `//` and `/* ... */` comments
- `#include` lines, ignored by the parser

Built-in functions include:

- `printf`
- `putchar`
- `puts`
- `getchar`
- `exit`

Supported `printf` formats include:

```text
%d
%i
%x
%c
%s
%%
%5d
```

### Unsupported C features

The compiler does not currently support:

- Pointers
- Character arrays and string variables
- Structures
- Floating-point types
- `switch`
- `do-while`
- `goto`
- `#define`
- Multiple source files

### Example C files

The `files/` and `usb_files/` directories contain examples:

```text
HELLO.C
NUMBERS.C
CONTROL.C
GLOBALS.C
SORT.C
HANOI.C
CHARS.C
MEDIUM.C
PERF.C
BAD1.C
BAD2.C
BAD3.C
```

Example commands:

```text
CC HELLO.C
CC NUMBERS.C
CC SORT.C
CC HANOI.C
```

Compiler errors use the format:

```text
CC: line N: message
```

Runtime errors use:

```text
RUNTIME ERROR: ...
```

## Printing

GMU OS can detect USB printers through UEFI USB protocols and send text.

Printer support is experimental. It has been implemented with simulated testing rather than guaranteed compatibility with every printer model.

### Detect a printer

Connect and switch on a USB printer, then run:

```text
PRINTER
```

The OS reports:

- Printer name
- Detected language: PCL, PostScript, or plain text

### Print a file

Print a named text file:

```text
PRINT FILE.TXT
```

To print a file selected with the interactive `DIR` picker:

```text
DIR
PRINT
```

Printing from another USB volume is also possible with a drive prefix:

```text
PRINT USB1:FILE.TXT
```

### Printer compatibility

The printer routines support:

- USB printers
- PCL laser printers
- PostScript printers
- Plain text printers

They do not support:

- PDF files
- Word documents
- Images
- Files larger than 256 KB
- Network printers
- Bluetooth printers
- Cheap inkjets that require a proprietary Windows GDI driver

If the OS says a printer was not found, confirm that:

- It is switched on.
- It is USB-connected.
- It exposes a supported device interface.
- It is not starting in an unsupported GDI-only mode.

## Using the disk image

`make-image.sh` creates `build/gmuos64.img`.

Run:

```sh
./make-image.sh
```

The script:

1. Builds `build/BOOTX64.EFI` if missing.
2. Deletes an existing image.
3. Creates a 64 MB empty file.
4. Creates a GPT partition table.
5. Creates a 1:EF00 EFI system partition.
6. Formats the partition as FAT32.
7. Copies `BOOTX64.EFI`.
8. Copies files and `HELLO64.BIN`.

The resulting layout is roughly:

```text
build/gmuos64.img
  EFI/
    BOOT/
      BOOTX64.EFI
  <sample files>
  HELLO64.BIN
```

The image can be:

- Opened directly by QEMU.
- Written to a USB drive with Rufus in DD mode.
- Written using balenaEtcher or another raw-disk writer.

## Project layout

```text
.
|-- .gitignore
|-- LICENSE-MikeOS.TXT
|-- README.md
|-- README.TXT
|-- build.sh                 Linux/WSL build script
|-- buildwin.bat             Windows build script
|-- make-image.sh            Create GPT/FAT32 disk image
|-- run-qemu.sh              Start QEMU on Linux/WSL
|-- run-qemu.bat             Start QEMU on Windows
|
|-- build/                   Generated EFI, BIN, and disk files
|-- firmware/OVMF.fd         UEFI firmware for QEMU
|-- files/                   Files copied to the USB/image
|-- usb_files/               Prepared USB file layout
|
|-- programs/
|   |-- hello64.asm          Example 64-bit program
|   \-- mikedev64.inc        Program system-call interface
|
|-- source/
|   |-- kernel.asm           PE32+ header, UEFI entry, startup
|   |-- uefi.inc             UEFI structures and macros
|   |-- vectors.inc          System-call vector list
|   |-- assets/              Generated desktop graphics
|   \-- features/
|       |-- cli.asm          Command line
|       |-- cedit.asm        C editor
|       |-- ccomp.asm        C compiler
|       |-- disk.asm         Filesystem and USB volume handling
|       |-- gfx.asm          Graphics primitives
|       |-- gui.asm          Desktop
|       |-- keyboard.asm     Keyboard input
|       |-- prn.asm          Printer support
|       `-- ...              Other kernel features
|
`-- tools/
    |-- gen_assets.py         Desktop asset generator
    `-- qtest.py              QEMU automation helper
```

### Important source files

| File | Purpose |
|---|---|
| `source/kernel.asm` | PE header, UEFI entry point, startup, OS main loop |
| `source/uefi.inc` | UEFI offsets and NASM macros |
| `source/vectors.inc` | System-call table indices |
| `source/features/cli.asm` | Command-line parser and built-in commands |
| `source/features/disk.asm` | Boot volume and USB disk handling |
| `source/features/gui.asm` | Desktop startup and event handling |
| `source/features/gfx.asm` | Graphics drawing and embedded assets |
| `source/features/cedit.asm` | Source editor |
| `source/features/ccomp.asm` | C compiler and bytecode runner |
| `source/features/prn.asm` | Printer discovery and output |
| `programs/mikedev64.inc` | External-program interface |

## How the code works

### UEFI instead of BIOS

The 16-bit MikeOS code used BIOS interrupts and real-mode memory. GMU OS64 replaces these with UEFI protocols:

- Text output through `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL`
- Text input through `EFI_SIMPLE_TEXT_INPUT_PROTOCOL`
- File operations through `EFI_FILE_PROTOCOL`
- Graphics through `EFI_GRAPHICS_OUTPUT_PROTOCOL`
- Device and volume discovery through UEFI boot services

UEFI starts this kernel in 64-bit long mode, so the kernel uses NASM `BITS 64` and 64-bit registers.

### PE32+ executable

`source/kernel.asm` contains a hand-written DOS header, PE header, section table, relocation data, and EFI entry information.

This means NASM can create `BOOTX64.EFI` directly without Microsoft's compiler or linker. The executable is a binary image, not a normal native executable linked for Linux or Windows.

### Memory

The kernel allocates one block of loader pages for file and program storage. The block is at most 1 MB in size as defined by `FILE_MAX`.

Desktop graphics allocate additional backing and wallpaper buffers.

### System-call table

The kernel fills `vec_table` with pointers to its internal functions. External 64-bit programs receive that table in `RDI`.

`source/vectors.inc` defines the order. Do not insert or remove a vector in the middle of this file unless both the kernel and program include agree. Changing this order changes all system-call indices.

### Filesystem

UEFI provides a root directory interface for the boot volume. The kernel opens this root in `disk_mount`.

Additional USB volumes are found by enumerating every simple-file-system handle. Each volume is assigned `USB1:`, `USB2:`, and so on.

File names are resolved by a small volume-prefix parser. If no prefix is present, the boot volume is used.

### Program execution

External programs are flat binaries. The signature is checked before the kernel jumps to code after the signature.

The program must not jump into kernel memory or assume a conventional process layout. It uses the vector table and kernel memory operations for OS functionality.

### Desktop graphics

The desktop assets are compiled into the kernel with `incbin` statements. At runtime, the graphics module:

- Finds a suitable UEFI graphics mode.
- Allocates backing buffers.
- Generates or loads the wallpaper.
- Draws icons and taskbar elements.
- Polls keyboard and pointer state.
- Rechecks the screen mode after text or editor windows are closed.

## Troubleshooting

### `nasm is not recognized`

NASM is not installed or is not in `PATH`.

- Windows: add NASM's installation folder to the system `PATH`.
- Linux: install NASM with your distribution's package manager.
- WSL: NASM must be installed inside WSL, not only in Windows.

Test with:

```sh
nasm -v
```

### `build/BOOTX64.EFI` is not created

Run the build from the project directory. Check NASM output for source or missing-file errors.

Example:

```sh
cd /path/to/gmuos64
./build.sh
```

On Windows:

```bat
cd C:\path\to\gmuos64
buildwin.bat
```

### `make-image.sh` says a command is missing

Install `sgdisk`, `mtools`, and `dd`. On Debian or Ubuntu:

```sh
sudo apt update
sudo apt install gdisk mtools nasm qemu-system-x86
```

Package names vary by distribution.

### QEMU reports an invalid BIOS or firmware error

Confirm `firmware/OVMF.fd` exists:

```sh
ls -l firmware/OVMF.fd
```

If missing, install OVMF and change `run-qemu.sh` or the manual command to point to the installed firmware file.

### QEMU starts but shows no desktop

Try forcing text mode by placing `NOGUI.TXT` in `usb_files/` or adding it to the disk image volume. Build and boot again.

You can also test whether QEMU graphics are available by starting with `-vga std`.

### USB starts in Windows but not in UEFI

Check that:

```text
EFI\BOOT\BOOTX64.EFI
```

is directly under the root. Check that the partition is FAT32. Verify that the firmware boot entry is UEFI and not Legacy/CSM-only.

### Secure Boot blocks GMU OS

Temporarily disable Secure Boot. An unsigned educational EFI executable cannot be guaranteed to start with Secure Boot enabled.

### The desktop does not find the mouse

This is a firmware compatibility issue rather than a USB mouse driver issue. GMU OS uses UEFI pointing-device support and keyboard fallback. Use the arrow keys, Tab, and Enter.

### Other USB drives are not visible

Confirm that:

- Each drive is FAT32 or FAT16.
- The drive is connected before or during scanning.
- UEFI exposes it as a block and filesystem device.
- The drive is not mounted by the firmware in a restricted way.
- It does not have NTFS or exFAT formatting.

Run `DIR USB` again after connecting a drive.

### `CC` fails to compile a C file

Check for:

- Unsupported C features.
- Missing semicolons.
- Missing braces.
- Division by zero or array issues.
- A file that contains CR/LF or unsupported characters.

The diagnostic should include a source line number.

### A 64-bit program says it is not supported

The file must begin with exactly:

```text
GMU64BIN
```

Do not copy an old 16-bit MikeOS `.BIN` or a Linux or Windows executable. Those formats are incompatible.

## Limitations

GMU OS 64 intentionally has several limitations:

- It is a learning operating system, not a production OS.
- It has no virtual memory or process scheduler.
- It has no protected multi-user environment.
- It uses a 1 MB program/file area.
- It supports the root filesystem and a limited directory model.
- It does not support NTFS or exFAT.
- It does not run original 16-bit MikeOS binaries.
- It does not include the original BASIC interpreter.
- `os_dump_string`, `os_dump_registers`, and `os_run_basic` are unsupported.
- The C compiler is bytecode-based and limited.
- Graphics and printer support vary between firmware and devices.
- Secure Boot requires signing or firmware-specific configuration.
- USB printer support is experimental.

## License

GMU OS 64 is a derivative learning edition based on MikeOS.

MikeOS copyright:

```text
Copyright (C) 2006 - 2022 MikeOS Developers
```

See `LICENSE-MikeOS.TXT` for the complete MikeOS license terms.
