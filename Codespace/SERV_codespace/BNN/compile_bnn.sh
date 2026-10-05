#!/bin/bash
# Usage: ./compile_bnn.sh [--popcount]
#   (no flag)     → build for the ORIGINAL SERV (software popcount fallback)
#   --popcount    → build for the MODIFIED SERV (hardware popcount instruction)
#
# Run from anywhere — paths resolve relative to this script's directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Popcount target ───────────────────────────────────────────
POPCOUNT_CFLAG=""
for arg in "$@"; do
    case "$arg" in
        --popcount) POPCOUNT_CFLAG="-DUSE_CUSTOM_POPCOUNT" ;;
        *) echo "ERROR: unknown argument '$arg' (use --popcount for the modified SERV)" >&2; exit 1 ;;
    esac
done

# ── Toolchain (override with e.g. RISCV_PREFIX=riscv32-unknown-elf- ./compile_bnn.sh) ──
RISCV_PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf-}"
CC="${CC:-${RISCV_PREFIX}gcc}"
AS="${AS:-${RISCV_PREFIX}as}"
LD="${LD:-${RISCV_PREFIX}ld}"
OBJDUMP="${OBJDUMP:-${RISCV_PREFIX}objdump}"
OBJCOPY="${OBJCOPY:-${RISCV_PREFIX}objcopy}"

mkdir -p outdir
mkdir -p outdir/linker

COMMON_FLAGS="-march=rv32e -mabi=ilp32e $POPCOUNT_CFLAG"

# --- Generate Assembly (.s) from C files ---
"$CC" $COMMON_FLAGS -O -S main_bnn.c -o outdir/main.s
"$CC" $COMMON_FLAGS -Oz -S helpers.c -o outdir/helpers.s
"$CC" $COMMON_FLAGS -Oz -S layer0.c -o outdir/layer0.s
"$CC" $COMMON_FLAGS -Oz -S layer1_uint32.c -o outdir/layer1_uint32.s
"$CC" $COMMON_FLAGS -Oz -S samples_bnn.c -o outdir/samples.s

# --- Assemble .s → .o ---
"$AS" -march=rv32e -mabi=ilp32e outdir/main.s -o outdir/main.o
"$AS" -march=rv32e -mabi=ilp32e outdir/helpers.s -o outdir/helpers.o
"$AS" -march=rv32e -mabi=ilp32e outdir/layer0.s -o outdir/layer0.o
"$AS" -march=rv32e -mabi=ilp32e outdir/layer1_uint32.s -o outdir/layer1_uint32.o
"$AS" -march=rv32e -mabi=ilp32e outdir/samples.s -o outdir/samples.o

# --- Assemble startup ---
STARTUP_SRC="startup/${TargetPlatform}_crt0.S"
if [[ ! -f "$STARTUP_SRC" ]]; then
  STARTUP_SRC="Codespace/SERV_codespace/build_codes/startup.S"
fi
[[ -f "$STARTUP_SRC" ]] || { echo "ERROR: no startup file found ($STARTUP_SRC)" >&2; exit 1; }
"$CC" -x assembler-with-cpp -march=rv32e -mabi=ilp32e -c "$STARTUP_SRC" -o outdir/linker/crt0.o

# --- link all .o → ELF ---
LDSCRIPT="linker/${TargetPlatform}_link.ld"
if [[ ! -f "$LDSCRIPT" ]]; then
  LDSCRIPT="serv_project/fusesoc_libraries/serv/sw/link.ld"
fi
[[ -f "$LDSCRIPT" ]] || { echo "ERROR: no linker script found ($LDSCRIPT)" >&2; exit 1; }

"$LD" \
  -T "$LDSCRIPT" \
  -m elf32lriscv \
  outdir/linker/crt0.o \
  outdir/main.o \
  outdir/helpers.o \
  outdir/layer0.o \
  outdir/layer1_uint32.o \
  outdir/samples.o \
  -e _start \
  -o outdir/BNN.elf

# --- Disassemble and Dump ---
"$OBJDUMP" -d outdir/BNN.elf > outdir/BNN.dump

# bin
"$OBJCOPY" -j .text -O binary outdir/BNN.elf outdir/BNN_imem.bin
"$OBJCOPY" -j .data -O binary outdir/BNN.elf outdir/BNN_dmem.bin

# hex
hexdump -v -e '"%08x\n"' outdir/BNN_imem.bin > outdir/imem.hex
hexdump -v -e '/1 "%02x\n"' outdir/BNN_dmem.bin > outdir/dmem.hex

# Copy outputs to the target platform directory (optional — path from another machine)
DEST_DIR="/home/sduan/RISP/riscv_minus_minus-tapeout-3/outputdir/firmware/${TargetPlatform}"
if [[ -n "$TargetPlatform" && -d "$DEST_DIR" ]]; then
  cp -r outdir/* "$DEST_DIR/BNN/."
  echo "Copied outputs to $DEST_DIR/BNN/"
else
  echo "NOTE: copy target '$DEST_DIR' not found — skipping copy. Outputs are in outdir/"
fi
