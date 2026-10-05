#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  PicoRV32 Verilator Simulation Script
# ═══════════════════════════════════════════════════════════════════════
#
#  Purpose:
#    Runs the Verilator simulation model of the PicoRV32 processor with
#    the specified firmware image (firmware.hex), extracts and analyzes
#    total clock cycle cost upon TRAP halt, and logs the execution output.
#
#  Features:
#    - Verilator model auto-build: automatically checks and compiles
#      the Vpicorv32_wrapper binary if not yet built
#    - Precise cycle count reporting: captures and formats the hardware
#      clock cycles from the testbench trap handler
#    - Optional trace disassembly: if --trace is provided, decodes the
#      raw data bus trace into human-readable instruction execution flow
#    - Structured logging: stores simulation logs in log/ directory
#
#  Usage:
#    ./run_sim.sh                              Run simulation with firmware.hex
#    ./run_sim.sh --run                        Run simulation without rebuilding
#    ./run_sim.sh --build                      Build Verilator C++ model only
#    ./run_sim.sh --clean                      Remove Verilator build directory
#    ./run_sim.sh --clear                      Remove log files and traces
#    ./run_sim.sh --trace                      Enable +trace and decode testbench.trace
#    ./run_sim.sh --firmware=my_firmware.hex   Use custom firmware hex image
#    ./run_sim.sh -h | --help                  Show this help message
#
#  Outputs:
#    - log/pico_sim.log                        Full simulation console log
#    - log/pico_trace.txt                      Decoded instruction trace (if --trace)
#    - testbench.vcd                           VCD waveform (if --trace)
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Color Output Helpers ─────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ── Configuration & Paths ────────────────────────────────────
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_DIR="build/picorv32_0-r1/test-verilator"
BINARY="./${BUILD_DIR}/Vpicorv32_wrapper"
FIRMWARE="firmware.hex"
LOG_DIR="log"
SIM_LOG="$LOG_DIR/pico_sim.log"
TRACE_LOG="$LOG_DIR/pico_trace.txt"

# Ensure host compiler and verilator tools from tools/bin are in PATH
export PATH="$PROJECT_ROOT/tools/bin:$PROJECT_ROOT/tools/riscv64/usr/bin:$PROJECT_ROOT/tools/riscv/bin:$PATH"
export LD_LIBRARY_PATH="$PROJECT_ROOT/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

mkdir -p "$LOG_DIR"

# ── Parse Arguments ──────────────────────────────────────────
DO_CLEAN=false
DO_BUILD=false
DO_RUN=false
DO_CLEAR=false
ENABLE_TRACE=false

for arg in "$@"; do
    case "$arg" in
        --clean)        DO_CLEAN=true ;;
        --build)        DO_BUILD=true ;;
        --run)          DO_RUN=true ;;
        --clear)        DO_CLEAR=true ;;
        --trace)        ENABLE_TRACE=true ;;
        --firmware=*)   FIRMWARE="${arg#*=}" ;;
        -h|--help)
            echo "Usage: $0 [--clean] [--build] [--run] [--clear] [--trace] [--firmware=FILE]"
            echo ""
            echo "  No args        Build model (if missing) and run simulation"
            echo "  --clean        Remove Verilator build artifacts (${BUILD_DIR})"
            echo "  --build        Build Verilator C++ model only"
            echo "  --run          Run simulation without building model"
            echo "  --clear        Remove logs and trace files in log/"
            echo "  --trace        Enable waveform (+vcd) and decoded trace log"
            echo "  --firmware=X   Specify custom hex firmware (default: firmware.hex)"
            echo "  -h, --help     Show this help text"
            exit 0
            ;;
        *)
            fail "Unknown option: $arg (see '$0 --help' for usage)"
            ;;
    esac
done

# Default: if no explicit action flag given, build (if needed) and run
if ! $DO_CLEAN && ! $DO_BUILD && ! $DO_RUN && ! $DO_CLEAR; then
    DO_BUILD=true
    DO_RUN=true
fi

# ── Action: CLEAR LOGS ───────────────────────────────────────
do_clear() {
    info "Clearing log files..."
    local count=0
    for f in "$SIM_LOG" "$TRACE_LOG" testbench.trace testbench.vcd; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            echo "  Removed: $f"
            count=$((count + 1))
        fi
    done
    if [[ $count -eq 0 ]]; then
        info "No log files to clear."
    else
        ok "Cleaned $count file(s)."
    fi
}

do_clean() {
    info "Cleaning Verilator build directory..."
    if [[ -d "build" ]]; then
        rm -rf "build"
        ok "Removed build/"
    else
        info "build/ directory already clean."
    fi
}

do_build() {
    if [[ ! -f "$BINARY" ]]; then
        info "Verilator binary not found. Compiling Vpicorv32_wrapper..."
        if [[ ! -d "$BUILD_DIR" ]]; then
            info "Running FuseSoC to setup Verilator fileset..."
            fusesoc run --target=test --tool=verilator --setup picorv32
        fi
        info "Building C++ executable in $BUILD_DIR..."
        make -C "$BUILD_DIR" -j"$(nproc)"
        ok "Built binary: $BINARY"
    else
        info "Verilator binary already up-to-date: $BINARY"
    fi
}

do_run() {
    [[ -f "$BINARY" ]]   || fail "Verilator binary missing: $BINARY (run with --build first)"
    [[ -f "$FIRMWARE" ]] || fail "Firmware hex file missing: $FIRMWARE (run build.sh first)"

    echo "════════════════════════════════════════"
    echo "  PicoRV32 Simulation Execution"
    echo "════════════════════════════════════════"
    info "Binary   : $BINARY"
    info "Firmware : $FIRMWARE"
    info "Trace    : $( $ENABLE_TRACE && echo "ENABLED (+trace +vcd)" || echo "DISABLED" )"
    echo ""

    local SIM_ARGS=("+firmware=$FIRMWARE" "+noerror")
    if $ENABLE_TRACE; then
        SIM_ARGS+=("+trace" "+vcd")
    fi

    # Execute simulation and capture output
    set +e
    "$BINARY" "${SIM_ARGS[@]}" 2>&1 | tee "$SIM_LOG"
    local SIM_RC=$?
    set -e

    echo ""
    echo "════════════════════════════════════════"
    echo "  Simulation Summary"
    echo "════════════════════════════════════════"

    # Extract cycle count from testbench output
    local CYCLES
    CYCLES=$(grep -oP 'TRAP after \K[0-9]+' "$SIM_LOG" | tail -n 1 || true)

    if [[ -n "$CYCLES" ]]; then
        echo -e "${GREEN}${BOLD}  STATUS       : SUCCESS (Halted via TRAP)${NC}"
        echo -e "${CYAN}${BOLD}  TOTAL CYCLES : ${CYCLES} cycles${NC}"
    else
        echo -e "${RED}${BOLD}  STATUS       : INCOMPLETE / FAILED${NC}"
        warn "Could not find 'TRAP after <cycles>' in simulation log."
        echo "Check $SIM_LOG for details."
    fi

    # Check for UART / character console output in log
    local UART_OUT
    UART_OUT=$(grep -vP '^(Built with|Recommended:|TRAP after|ERROR!|- src/|\+)' "$SIM_LOG" | tr -d '\r' | sed '/^$/d' || true)
    if [[ -n "$UART_OUT" ]]; then
        echo "── Program Output ──"
        echo "$UART_OUT"
    fi

    # ── Post-process trace if --trace was requested ──────────
    if $ENABLE_TRACE && [[ -f "testbench.trace" && -f "firmware.elf" ]]; then
        info "Decoding testbench.trace using showtrace.py..."
        python3 showtrace.py testbench.trace firmware.elf > "$TRACE_LOG" 2>/dev/null || true
        ok "Decoded trace saved to $TRACE_LOG ($(wc -l < "$TRACE_LOG") lines)"
    fi

    echo "════════════════════════════════════════"
    ok "Simulation finished. Detailed log: $SIM_LOG"
    echo "════════════════════════════════════════"
}

if $DO_CLEAR; then
    do_clear
    exit 0
fi

if $DO_CLEAN; then
    do_clean
    exit 0
fi

if $DO_BUILD; then
    do_build
fi

if $DO_RUN; then
    do_run
fi
