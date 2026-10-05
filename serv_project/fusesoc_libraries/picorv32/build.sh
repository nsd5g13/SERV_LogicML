#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  PicoRV32 Firmware Build Script
# ═══════════════════════════════════════════════════════════════════════
#
#  Purpose:
#    Compiles RISC-V firmware for the PicoRV32 processor from C/assembly
#    sources, links with startup_pico.S, and generates ELF, raw binary,
#    disassembly dump, and Verilog memory hex files.
#
#  Features:
#    - Supports custom input program directory via --folder=<name|path>
#      (auto-discovers from Codespace/SERV_codespace/ if given a bare name)
#    - Automatically discovers all C source files in the target directory
#    - Binds PicoRV32 startup code (startup_pico.S) while safely filtering
#      out any SERV-specific startup.S to avoid duplicate _start symbols
#    - Automatically pads raw binary to 4-byte boundaries for makehex
#    - Chainable with simulation via --build --run
#
#  Usage:
#    ./build.sh --build                        Compile default firmware (firmware/)
#    ./build.sh --folder=random_forest --build Compile Codespace/SERV_codespace/random_forest/
#    ./build.sh --folder=path/to/code --build  Compile from arbitrary directory path
#    ./build.sh --folder=random_forest --build --run  Compile and immediately run simulation
#    ./build.sh --run                          Run simulation using existing firmware.hex
#    ./build.sh --clear                        Remove build artifacts
#    ./build.sh -h | --help                    Show this help message
#
#  Outputs:
#    - firmware.elf                            Linked ELF executable
#    - firmware.bin                            Raw 4-byte aligned binary
#    - firmware.hex                            128KB Verilog hex image for testbench
#    - firmware.dump                           Full disassembly dump with symbol table
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Color Output Helpers ─────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ── Configuration & Paths ────────────────────────────────────
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERV_CODESPACE="$PROJECT_ROOT/Codespace/SERV_codespace"
STARTUP_SRC="$SCRIPT_DIR/firmware/startup_pico.S"
LDSCRIPT="$SCRIPT_DIR/firmware/sections.lds"
MAKEHEX="$SCRIPT_DIR/firmware/makehex.py"
MEMORY_WORDS=32768  # 32768 words * 4 bytes = 128KB

# ── Toolchain Detection & Environment Setup ──────────────────
# Set LD_LIBRARY_PATH for required compiler libraries (libisl, libmpfr, libmpc)
if [[ -d "$PROJECT_ROOT/tools/lib" ]]; then
    export LD_LIBRARY_PATH="$PROJECT_ROOT/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Locate suitable GCC and binary utilities
CC=""
OBJDUMP=""
OBJCOPY=""
SIZE=""

# Priority 1: riscv64 toolchain under tools/riscv64/usr/bin (supports -march=rv32ic)
if [[ -x "$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-gcc" ]]; then
    CC="$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-gcc"
    OBJCOPY="$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-objcopy"
    OBJDUMP="$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-objdump"
    SIZE="$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-size"
# Priority 2: riscv32 toolchain under tools/riscv/bin (if verified working)
elif [[ -x "$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-gcc" ]] && "$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-gcc" --version >/dev/null 2>&1; then
    CC="$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-gcc"
    OBJCOPY="$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-objcopy"
    OBJDUMP="$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-objdump"
    SIZE="$PROJECT_ROOT/tools/riscv/bin/riscv32-unknown-elf-size"
# Priority 3: System PATH
elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    CC="riscv32-unknown-elf-gcc"
    OBJCOPY="riscv32-unknown-elf-objcopy"
    OBJDUMP="riscv32-unknown-elf-objdump"
    SIZE="riscv32-unknown-elf-size"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    CC="riscv64-unknown-elf-gcc"
    OBJCOPY="riscv64-unknown-elf-objcopy"
    OBJDUMP="riscv64-unknown-elf-objdump"
    SIZE="riscv64-unknown-elf-size"
else
    fail "RISC-V GCC toolchain not found. Please verify tools/ or system PATH."
fi

# Fallback for objdump wrapper in tools/riscv/bin if it points to missing path
if ! "$OBJDUMP" --version >/dev/null 2>&1; then
    if [[ -x "$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-objdump" ]]; then
        OBJDUMP="$PROJECT_ROOT/tools/riscv64/usr/bin/riscv64-unknown-elf-objdump"
    fi
fi

# ── Compiler Flags ───────────────────────────────────────────
ARCH="rv32ic"
ABI="ilp32"
COMMON_FLAGS="-march=$ARCH -mabi=$ABI -static -nostdlib -nostartfiles -ffreestanding"

# ── Clean Action ─────────────────────────────────────────────
do_clear() {
    info "Clearing build artifacts..."
    local count=0
    for f in firmware.elf firmware.bin firmware.hex firmware.dump; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            echo "  Removed: $f"
            count=$((count + 1))
        fi
    done
    if [[ $count -eq 0 ]]; then
        info "No build artifacts to remove."
    else
        ok "Cleaned $count artifact(s)."
    fi
}

# ── Compilation Action ───────────────────────────────────────
do_build() {
    local target_folder="${1:-}"
    local folder_path=""

    # 1. Resolve folder path
    if [[ -z "$target_folder" ]]; then
        folder_path="$SCRIPT_DIR/firmware"
    elif [[ -d "$target_folder" ]]; then
        folder_path="$(cd "$target_folder" && pwd)"
    elif [[ -d "$SERV_CODESPACE/$target_folder" ]]; then
        folder_path="$(cd "$SERV_CODESPACE/$target_folder" && pwd)"
    elif [[ -d "$SCRIPT_DIR/$target_folder" ]]; then
        folder_path="$(cd "$SCRIPT_DIR/$target_folder" && pwd)"
    else
        fail "Specified folder not found: $target_folder"
    fi

    echo "════════════════════════════════════════"
    echo "  PicoRV32 Firmware Build"
    echo "════════════════════════════════════════"
    info "Target folder : $folder_path"
    info "Compiler      : $CC"
    info "Arch / ABI    : $ARCH / $ABI"

    # 2. Discover source files
    local C_SRCS=()
    local ASM_SRCS=()

    # Always prepend PicoRV32 startup code as the primary entry point
    [[ -f "$STARTUP_SRC" ]] || fail "PicoRV32 startup assembly missing: $STARTUP_SRC"
    ASM_SRCS+=("$STARTUP_SRC")

    # Discover C / C++ sources in the target folder
    while IFS= read -r -d '' src; do
        C_SRCS+=("$src")
    done < <(find "$folder_path" -maxdepth 1 \( -name "*.c" -o -name "*.cpp" \) -print0 | sort -z)

    # Discover additional assembly sources, excluding any SERV-specific startup.S
    while IFS= read -r -d '' src; do
        local bname
        bname="$(basename "$src")"
        if [[ "$bname" =~ ^startup\.[sS]$ ]]; then
            warn "Ignoring SERV-specific '$bname' in $folder_path (using $STARTUP_SRC instead)"
        else
            ASM_SRCS+=("$src")
        fi
    done < <(find "$folder_path" -maxdepth 1 \( -name "*.s" -o -name "*.S" \) -print0 | sort -z)

    local total_sources=$(( ${#ASM_SRCS[@]} + ${#C_SRCS[@]} ))
    [[ $total_sources -gt 1 ]] || fail "No C/assembly sources found in folder: $folder_path"

    info "Sources to compile:"
    for s in "${ASM_SRCS[@]}"; do echo "    [ASM] $s"; done
    for s in "${C_SRCS[@]}";   do echo "    [C]   $s"; done

    # 3. Setup include paths & compiler options
    local INCLUDES="-I$SCRIPT_DIR/firmware -I$PROJECT_ROOT/Codespace -I$folder_path"
    local CFLAGS="-O2 $COMMON_FLAGS $INCLUDES"

    # 4. Compile and link to ELF
    local ELF="firmware.elf"
    local BIN="firmware.bin"
    local HEX="firmware.hex"
    local DUMP="firmware.dump"

    info "Compiling & linking -> $ELF"
    $CC $CFLAGS -T "$LDSCRIPT" -o "$ELF" "${ASM_SRCS[@]}" "${C_SRCS[@]}"
    ok "Linked: $ELF"
    $SIZE "$ELF"

    # 5. Convert ELF to raw binary and pad to 4-byte boundary
    info "Converting to binary -> $BIN"
    $OBJCOPY -O binary "$ELF" "$BIN"
    local bin_size
    bin_size=$(stat -c%s "$BIN")
    if (( bin_size % 4 != 0 )); then
        local padded_size=$(( (bin_size + 3) & ~3 ))
        dd if=/dev/zero bs=1 count=$(( padded_size - bin_size )) >> "$BIN" 2>/dev/null
        info "Padded binary to $padded_size bytes (4-byte aligned)"
    fi
    ok "Binary ready: $BIN ($(stat -c%s "$BIN") bytes)"

    # 6. Convert binary to Verilog hex (128KB memory image)
    info "Generating Verilog memory hex ($MEMORY_WORDS words) -> $HEX"
    python3 "$MAKEHEX" "$BIN" "$MEMORY_WORDS" > "$HEX"
    ok "Hex ready: $HEX ($(wc -l < "$HEX") words)"

    # 7. Generate full disassembly dump
    info "Generating disassembly dump -> $DUMP"
    {
        echo "═══════════════════════════════════════════════════════════════"
        echo "  PicoRV32 Firmware Disassembly Dump"
        echo "  Source : $folder_path"
        echo "  Date   : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "── Section Sizes ──"
        $SIZE "$ELF"
        echo ""
        echo "── Disassembly (.text) ──"
        $OBJDUMP -d -S -M numeric,no-aliases "$ELF"
        echo ""
        echo "── Symbol Table ──"
        $OBJDUMP -t "$ELF"
    } > "$DUMP"
    ok "Dump ready: $DUMP ($(wc -l < "$DUMP") lines)"

    echo "════════════════════════════════════════"
    ok "Build succeeded! Outputs: $ELF, $BIN, $HEX, $DUMP"
    echo "════════════════════════════════════════"
}

# ── Argument Parsing ─────────────────────────────────────────
TARGET_FOLDER=""
DO_BUILD=false
DO_RUN=false

if [[ $# -eq 0 ]]; then
    # Default behavior without args: build default firmware
    DO_BUILD=true
fi

for arg in "$@"; do
    case "$arg" in
        --folder=*) TARGET_FOLDER="${arg#*=}" ;;
        --build)    DO_BUILD=true ;;
        --run)      DO_RUN=true ;;
        --clear)    do_clear; exit 0 ;;
        -h|--help)
            echo "Usage: $0 [--folder=NAME|PATH] [--build] [--run] [--clear]"
            echo ""
            echo "  --folder=NAME|PATH  Source directory to compile (default: firmware/;"
            echo "                      supports bare names from Codespace/SERV_codespace/)"
            echo "  --build             Compile the firmware into firmware.hex"
            echo "  --run               Execute simulation (invokes ./run_sim.sh)"
            echo "  --clear             Remove generated firmware.* artifacts"
            echo "  -h, --help          Show this help text"
            echo ""
            echo "Examples:"
            echo "  $0 --build"
            echo "  $0 --folder=random_forest --build"
            echo "  $0 --folder=random_forest --build --run"
            exit 0
            ;;
        *)
            fail "Unknown option: $arg (see '$0 --help' for usage)"
            ;;
    esac
done

if $DO_BUILD; then
    do_build "$TARGET_FOLDER"
fi

if $DO_RUN; then
    if [[ ! -f "firmware.hex" ]]; then
        fail "firmware.hex not found. Run with --build first or add --build."
    fi
    exec ./run_sim.sh --run
fi
