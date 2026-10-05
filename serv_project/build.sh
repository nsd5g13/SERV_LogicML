#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  SERV Firmware Build & Simulate Script
# ═══════════════════════════════════════════════════════════════════════
#
#  Purpose:
#    Compiles RISC-V firmware from C/assembly source files, links it
#    with the SERV startup code, then optionally launches a FuseSoC-
#    driven Verilator simulation to run the firmware on the SERV core.
#
#  Tools used:
#    - riscv64-unknown-elf-gcc   Compile & link RISC-V rv32i firmware
#    - riscv64-unknown-elf-objcopy  ELF → raw binary conversion
#    - riscv64-unknown-elf-size     Print firmware section sizes
#    - python3 (makehex.py)         Binary → Verilog hex format
#    - fusesoc                      Build & run Verilator simulation
#
#  Usage:
#    ./build.sh --build               Compile firmware (default: build_codes/)
#    ./build.sh --run                 Run simulation (firmware must exist)
#    ./build.sh --build --run         Compile then simulate
#    ./build.sh --clear               Remove build artifacts
#    ./build.sh --folder=Wk3 --build  Build from SERV_codespace/Wk3/ instead
#    ./build.sh --serv-dir=fusesoc_libraries/serv_bne --build   Use BNE SERV variant
#
#  SERV variant selection (SERV_DIR):
#    Default : fusesoc_libraries/serv_v1.5_rtl   (v1.5 in-window-writeback custom-popcount SERV)
#    BNE     : fusesoc_libraries/serv_bne  (teammate's conditional-branch
#              early-exit SERV)
#    Override via --serv-dir=<path> or the SERV_DIR environment variable.
#    Used for sw/link.ld and sw/makehex.py.
#
#  Default folder mode:
#    Without --folder, auto-discovers sources from
#    Codespace/SERV_codespace/build_codes/
#    With --folder=<name>, uses Codespace/SERV_codespace/<name>/ instead.
#    Assembly files (.s/.S) are placed before C/C++ files automatically.
#    The folder is also added to -I so local #includes work.
#
#  Inputs (sources from SERV_codespace/build_codes/ by default):
#    - startup.S / popcount.c / etc.
#
#  Outputs (generated files in serv_project/):
#    - firmware.elf              Linked ELF binary
#    - firmware.bin              Raw binary (objcopy)
#    - firmware.hex              Verilog hex image (loaded by simulation RAM)
#    - build/…/trace.bin         PC trace from simulation (if --run)
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Folder mode ─────────────────────────────────────────────
# Default: auto-discover from build_codes/
# Override with --folder=<name> to use a different folder
# ──────────────────────────────────────────────────────────────
FOLDER=""
DEFAULT_FOLDER="build_codes"
SERV_CODESPACE="../Codespace/SERV_codespace"
# SERV RTL variant (popcount vs BNE early-exit). Overridable via --serv-dir=...
# or the SERV_DIR environment variable. Used for sw/link.ld and sw/makehex.py.
SERV_DIR="${SERV_DIR:-fusesoc_libraries/serv_v1.5_rtl}"
# ──────────────────────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────

# Project root (script's own directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Toolchain (prefers env.sh exports, falls back to riscv64 prefix) ──
_prefix="${RISCV64_PREFIX:-riscv64-unknown-elf-}"
if ! command -v "${_prefix}gcc" >/dev/null 2>&1; then
    if [[ -d "$SCRIPT_DIR/../tools/riscv64/usr/bin" ]]; then
        export PATH="$SCRIPT_DIR/../tools/riscv64/usr/bin:$PATH"
    fi
fi
CC="${CC:-${_prefix}gcc}"
CXX="${CXX:-${_prefix}g++}"
OBJCOPY="${OBJCOPY:-${_prefix}objcopy}"
SIZE="${SIZE:-${_prefix}size}"
OBJDUMP="${OBJDUMP:-${_prefix}objdump}"
FUSESOC="${FUSESOC:-fusesoc}"

# Custom binutils (as/objdump with popcount support) built from
# riscv-gnu-toolchain/binutils. -B makes gcc pick our `as` first.
CUSTOM_BINUTILS_BIN="$SCRIPT_DIR/../riscv-gnu-toolchain/install/bin"
[[ -x "$CUSTOM_BINUTILS_BIN/riscv64-unknown-elf-as" ]] && BFLAG="-B$CUSTOM_BINUTILS_BIN" || BFLAG=""

# Ensure toolchain shared libraries (libisl, libmpfr, libmpc) are discoverable in container/snap envs
_libdir="$SCRIPT_DIR/../tools/lib"
if [[ -d "$_libdir" ]]; then
    export LD_LIBRARY_PATH="$_libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# ── Compiler flags ───────────────────────────────────────────
ARCH=rv32i
ABI=ilp32
COMMON_FLAGS="-march=$ARCH -mabi=$ABI -static -nostdlib -nostartfiles -ffreestanding"
INCLUDES="-I$SCRIPT_DIR/../Codespace"
CFLAGS="-O2 $COMMON_FLAGS $INCLUDES"
LDSCRIPT="$SERV_DIR/sw/link.ld"
MAKEHEX="$SERV_DIR/sw/makehex.py"

# ── Output files ─────────────────────────────────────────────
ELF="firmware.elf"
BIN="firmware.bin"
HEX="firmware.hex"

# ── Simulation settings ──────────────────────────────────────
FUSESOC_CORE="award-winning:serv:servant:1.4.0"
BAUD=57600
SIM_TIMEOUT=${SIM_TIMEOUT:-300}
TRACE_DIR="$SCRIPT_DIR/build/award-winning_serv_servant_1.4.0/verilator_tb"

# ══════════════════════════════════════════════════════════════
#  Colored output helpers
# ══════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ══════════════════════════════════════════════════════════════
#  Classify source file type -> sets COMPILER and XFLAG
# ══════════════════════════════════════════════════════════════
classify_file() {
    local ext="${1##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    case "$ext" in
        c)             COMPILER="$CC";  XFLAG="-x c" ;;
        cc|cpp|cxx|c++) COMPILER="$CXX"; XFLAG="-x c++" ;;
        S|s|asm)       COMPILER="$CC";  XFLAG="-x assembler-with-cpp" ;;
        *)             COMPILER="$CC";  XFLAG=""
                       warn "Unknown extension '.$ext', using gcc default" ;;
    esac
}

# ══════════════════════════════════════════════════════════════
#  BUILD: Compile firmware from SOURCES array
#  Strategy: single GCC invocation (compile + link).
#  .S files are always placed BEFORE .c/.cpp files so the
#  linker puts _start at the correct address.
# ══════════════════════════════════════════════════════════════
do_build() {
    info "Building firmware..."
    echo ""

    # Re-evaluate linker script and makehex paths in case --serv-dir was specified
    LDSCRIPT="$SERV_DIR/sw/link.ld"
    MAKEHEX="$SERV_DIR/sw/makehex.py"

    [[ -f "$LDSCRIPT" ]] || fail "Linker script not found: $LDSCRIPT"
    [[ -f "$MAKEHEX" ]]  || fail "makehex.py not found: $MAKEHEX"

    # ── Resolve folder: use --folder or default to build_codes/ ──
    local USE_FOLDER="${FOLDER:-$DEFAULT_FOLDER}"
    local FOLDER_PATH="$SERV_CODESPACE/$USE_FOLDER"
    [[ -d "$FOLDER_PATH" ]] || fail "Folder not found: $FOLDER_PATH"

    SOURCES=()
    local EXT_PATTERN="*.s *.S *.c *.cc *.cpp *.cxx *.c++"
    for ext_pat in $EXT_PATTERN; do
        for f in "$FOLDER_PATH"/$ext_pat; do
            [[ -f "$f" ]] && SOURCES+=("$f")
        done
    done

    [[ ${#SOURCES[@]} -eq 0 ]] && fail "No source files found in $FOLDER_PATH"

    # Add folder to include path so local headers work
    INCLUDES="-I$SCRIPT_DIR/../Codespace -I$FOLDER_PATH"
    CFLAGS="-O2 $COMMON_FLAGS $INCLUDES"

    if $USE_POPCOUNT; then
        CFLAGS="$CFLAGS -DUSE_CUSTOM_POPCOUNT"
        info "Hardware popcount enabled (-DUSE_CUSTOM_POPCOUNT)"
    fi

    info "Folder: $FOLDER_PATH"

    # ── Partition sources: assembly first, then C/C++ ──────
    local ASM_SRCS=()
    local C_SRCS=()
    declare -A SEEN
    local TOTAL=0
    local SKIPPED=0

    for src in "${SOURCES[@]}"; do
        local abs
        abs="$(realpath "$src" 2>/dev/null || echo "$SCRIPT_DIR/$src")"

        # Skip duplicates
        if [[ -n "${SEEN[$abs]+_}" ]]; then
            warn "Duplicate skipped: $src"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        SEEN["$abs"]=1

        # Skip missing files
        if [[ ! -f "$src" ]]; then
            warn "File not found, skipping: $src"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        local ext="${src##*.}"
        ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
        case "$ext" in
            S|s|asm) ASM_SRCS+=("$src") ;;
            *)       C_SRCS+=("$src") ;;
        esac
        TOTAL=$((TOTAL + 1))
    done

    # ── Fallback startup assembly if none provided in target folder ──
    if [[ ${#ASM_SRCS[@]} -eq 0 ]]; then
        local FALLBACK_STARTUP="$SERV_CODESPACE/build_codes/startup.S"
        if [[ -f "$FALLBACK_STARTUP" ]]; then
            info "No assembly file found in $FOLDER_PATH; using fallback startup: $FALLBACK_STARTUP"
            ASM_SRCS+=("$FALLBACK_STARTUP")
            TOTAL=$((TOTAL + 1))
        else
            fail "No assembly file in $FOLDER_PATH and fallback startup not found at $FALLBACK_STARTUP"
        fi
    fi

    [[ $TOTAL -eq 0 ]] && fail "No source files to compile"

    # Concatenate: assembly first, then C/C++
    local ALL_SRCS=("${ASM_SRCS[@]}" "${C_SRCS[@]}")

    info "Sources (assembly → C):"
    for f in "${ALL_SRCS[@]}"; do info "  $f"; done
    echo ""

    # ── Single GCC command: compile + link ─────────────────
    info "Compiling + linking -> $ELF"
    $CC $BFLAG $CFLAGS -T "$LDSCRIPT" -o "$ELF" "${ALL_SRCS[@]}"
    ok "Linked: $ELF"

    echo ""
    $SIZE "$ELF"
    echo ""

    # ── ELF -> binary -> hex ───────────────────────────────
    info "objcopy -> $BIN"
    $OBJCOPY -O binary "$ELF" "$BIN"
    ok "Binary: $BIN ($(stat -c%s "$BIN") bytes)"

    info "makehex -> $HEX"
    python3 "$MAKEHEX" "$BIN" 4096 > "$HEX"
    local hex_lines
    hex_lines=$(wc -l < "$HEX")
    ok "Hex: $HEX ($hex_lines words)"

    echo ""
    ok "Build done! Outputs: $ELF / $BIN / $HEX"
}

# ══════════════════════════════════════════════════════════════
#  RUN: Launch Verilator simulation
# ══════════════════════════════════════════════════════════════
do_run() {
    [[ -f "$HEX" ]] || fail "Firmware not found: $HEX — run ./build.sh --build first"

    # Clean up old trace files before simulation
    rm -f "$TRACE_DIR/trace.bin" "$TRACE_DIR/trace.vcd"

    info "Starting Verilator simulation..."
    info "  Core:     $FUSESOC_CORE"
    info "  Firmware: $SCRIPT_DIR/$HEX"
    info "  Baud:     $BAUD"
    info "  Trace:    $TRACE_DIR/trace.bin"
    echo ""

    timeout "${SIM_TIMEOUT}s" \
        "$FUSESOC" run --target=verilator_tb "$FUSESOC_CORE" \
            --uart_baudrate="$BAUD" \
            --firmware="$SCRIPT_DIR/$HEX" \
            --trace_pc \
        || {
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                warn "Simulation timed out (${SIM_TIMEOUT}s) — terminated"
            else
                fail "Simulation failed (exit code: $exit_code)"
            fi
        }

    # Verify trace.bin was generated
    if [[ -f "$TRACE_DIR/trace.bin" ]]; then
        local trace_size
        trace_size=$(stat -c%s "$TRACE_DIR/trace.bin")
        ok "Trace saved: $TRACE_DIR/trace.bin ($((trace_size / 4)) PC entries)"
    else
        warn "trace.bin not found at $TRACE_DIR/trace.bin"
    fi
}

# ══════════════════════════════════════════════════════════════
#  CLEAN: Remove build artifacts
# ══════════════════════════════════════════════════════════════
do_clear() {
    info "Cleaning build artifacts..."
    rm -f "$ELF" "$BIN" "$HEX" build_*.o "$TRACE_DIR/trace.bin" "$TRACE_DIR/trace.vcd"
    ok "Removed: $ELF / $BIN / $HEX / build_*.o / trace.*"
}

# ══════════════════════════════════════════════════════════════
#  Main: parse command-line arguments
# ══════════════════════════════════════════════════════════════
usage() {
    echo "Usage: $0 [--folder=NAME] [--serv-dir=DIR] [--popcount] [--zbb] [--build] [--run] [--clear]"
    echo ""
    echo "  --folder=NAME   Build from Codespace/SERV_codespace/NAME/ (default: build_codes/)"
    echo "  --serv-dir=DIR  SERV RTL dir for sw/link.ld & sw/makehex.py"
    echo "                  (default: fusesoc_libraries/serv_v1.5_rtl;"
    echo "                   use fusesoc_libraries/serv_bne for the BNE variant)"
    echo "  --popcount      Enable custom hardware popcount (-DUSE_CUSTOM_POPCOUNT)"
    echo "  --zbb           [ABANDONED - kept only to reproduce the experiment]"
    echo "                  Compile with -march=rv32i_zbb. Do NOT use for real builds."
    echo "                  Enabling zbb globally hands the whole extension to GCC, which"
    echo "                  then emits clz/ctz/min/max/rol/andn/orn/xnor/rev8 -- none of"
    echo "                  which this RTL implements, and all of which fail SILENTLY."
    echo "                  Measured: random_forest's 'lo & ~hi' became andn, which SERV"
    echo "                  evaluates as a plain and -> all 10 samples misclassified as 0."
    echo "                  Supported route: a local '.option arch, +zbb' block around the"
    echo "                  cpop in the inline asm (see infer_one.c / popcount_cus.c)."
    echo "  --build         Compile firmware (deduplicates sources automatically)"
    echo "  --run           Launch Verilator simulation"
    echo "  --clear         Remove all build artifacts"
    echo ""
    echo "Default: auto-discovers .s/.S/.c/.cpp files from build_codes/."
    echo "Use --folder to build from a different folder instead."
    echo ""
    echo "Examples:"
    echo "  $0 --build                         # compile from build_codes/"
    echo "  $0 --folder=random_forest --build  # compile software popcount"
    echo "  $0 --folder=random_forest --popcount --build  # compile hardware popcount"
    echo "  $0 --folder=BNN --build            # compile BNN (auto startup fallback)"
    echo "  $0 --folder=Tsetin_Machine --popcount --build # compile TM with popcount"
    echo "  $0 --serv-dir=fusesoc_libraries/serv_bne --build   # BNE SERV variant"
    echo "  $0 --clear                         # clear artifacts"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

DO_BUILD=false
DO_RUN=false
USE_POPCOUNT=false

for arg in "$@"; do
    case "$arg" in
        --folder=*)   FOLDER="${arg#*=}" ;;
        --serv-dir=*) SERV_DIR="${arg#*=}" ;;
        --popcount)   USE_POPCOUNT=true ;;
        --zbb)        ARCH=rv32i_zbb ;;
        --build)      DO_BUILD=true ;;
        --run)        DO_RUN=true ;;
        --clear)      do_clear; exit 0 ;;
        --help|-h)    usage; exit 0 ;;
        *) fail "Unknown argument: $arg (use --help for usage)" ;;
    esac
done

# ARCH is assigned above the option parser, so the arch-dependent flags must be
# re-derived here after --zbb may have switched it to rv32i_zbb.
COMMON_FLAGS="-march=$ARCH -mabi=$ABI -static -nostdlib -nostartfiles -ffreestanding"

if $DO_BUILD; then do_build; fi
if $DO_RUN;   then do_run;   fi
