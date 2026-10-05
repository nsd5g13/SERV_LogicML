#!/bin/bash
# Usage: ./build.sh [TargetPlatform]
TargetPlatform="$1"

mkdir -p outdir
mkdir -p outdir/linker

# --- Generate Assembly (.s) from C files ---
/opt/riscv/bin/riscv64-unknown-elf-gcc -O0 -march=rv32e -mabi=ilp32e -S main.c -o outdir/main.s
/opt/riscv/bin/riscv64-unknown-elf-gcc -O0 -march=rv32e -mabi=ilp32e -S infer_one.c -o outdir/infer_one.s
/opt/riscv/bin/riscv64-unknown-elf-gcc -O0 -march=rv32e -mabi=ilp32e -S RF_model.c -o outdir/RF_model.s
/opt/riscv/bin/riscv64-unknown-elf-gcc -O0 -march=rv32e -mabi=ilp32e -S samples.c -o outdir/samples.s

# --- Assemble .s → .o ---
/opt/riscv/bin/riscv64-unknown-elf-as -march=rv32e -mabi=ilp32e outdir/main.s -o outdir/main.o
/opt/riscv/bin/riscv64-unknown-elf-as -march=rv32e -mabi=ilp32e outdir/infer_one.s -o outdir/infer_one.o
/opt/riscv/bin/riscv64-unknown-elf-as -march=rv32e -mabi=ilp32e outdir/RF_model.s -o outdir/RF_model.o
/opt/riscv/bin/riscv64-unknown-elf-as -march=rv32e -mabi=ilp32e outdir/samples.s -o outdir/samples.o

# --- Assemble startup ---
/opt/riscv/bin/riscv64-unknown-elf-as -march=rv32e -mabi=ilp32e startup/${TargetPlatform}_crt0.S -o outdir/linker/crt0.o

# --- link all .o → ELF ---
/opt/riscv/bin/riscv64-unknown-elf-ld \
  -T linker/${TargetPlatform}_link.ld \
  -m elf32lriscv \
  outdir/linker/crt0.o \
  outdir/main.o \
  outdir/infer_one.o \
  outdir/RF_model.o \
  outdir/samples.o \
  -e _start \
  -o outdir/RF.elf

# --- Disassemble and Dump ---
/opt/riscv/bin/riscv64-unknown-elf-objdump -d outdir/RF.elf > outdir/RF.dump

# bin
/opt/riscv/bin/riscv64-unknown-elf-objcopy -j .text -O binary outdir/RF.elf outdir/RF_imem.bin
/opt/riscv/bin/riscv64-unknown-elf-objcopy -j .data -O binary outdir/RF.elf outdir/RF_dmem.bin

# hex
hexdump -v -e '"%08x\n"' outdir/RF_imem.bin > outdir/imem.hex
hexdump -v -e '/1 "%02x\n"' outdir/RF_dmem.bin > outdir/dmem.hex

# mv
cp -r outdir/* /home/sduan/RISP/riscv_minus_minus-tapeout-3/outputdir/firmware/${TargetPlatform}/RF/.
