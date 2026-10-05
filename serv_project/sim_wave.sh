#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  SERV Waveform Viewer
# ═══════════════════════════════════════════════════════════════════════
#
#  Purpose:
#    Convenience wrapper that rebuilds the simulation, runs it, and
#    automatically opens the resulting VCD waveform in GTKWave. Useful
#    for signal-level debugging of the SERV CPU and SoC peripherals.
#
#  Tools used:
#    - run_sim.sh --clear --build   Clean build the Verilator model
#    - run_sim.sh --run             Run simulation (generates VCD)
#    - gtkwave                      Open waveform viewer (GUI)
#
#  Usage:
#    ./sim_wave.sh                     Build, run, and view waveform
#    ./sim_wave.sh --firmware=my.hex   Use a different firmware file
#
#  Steps:
#    1-2. Clean old artifacts & build Verilator model with VCD tracing
#    3.   Run simulation → generates log/sim_wave.vcd
#    4.   Open log/sim_wave.vcd in GTKWave
#
#  Outputs:
#    - log/sim_wave.vcd   VCD waveform file (viewable in GTKWave)
#    - log/sim_log.txt    Simulation log (from run_sim.sh post-process)
#    - log/compare_result.txt  Merged trace analysis (from run_sim.sh)
#
#  Prerequisite:
#    GTKWave must be installed:  sudo apt install gtkwave
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Parse optional firmware argument ─────────────────────────
FIRMWARE_ARG=""
DO_CLEAR=false
for arg in "$@"; do
    case "$arg" in
        --firmware=*) FIRMWARE_ARG="--firmware=${arg#*=}" ;;
        --clear)      DO_CLEAR=true ;;
        -h|--help)
            echo "Usage: $0 [--firmware=FILE] [--clear]"
            echo ""
            echo "  --firmware=FILE   Specify a .hex firmware file (default: firmware.hex)"
            echo "  --clear           Remove log files and VCD"
            echo ""
            echo "This script builds Verilator with VCD tracing, runs the simulation,"
            echo "and opens the waveform in GTKWave."
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $arg"
            exit 1
            ;;
    esac
done

VCD_FILE="log/sim_wave.vcd"

# ── Clear logs if requested ──────────────────────────────────
if $DO_CLEAR; then
    echo "════════════════════════════════════════"
    echo "  CLEAR LOGS"
    echo "════════════════════════════════════════"
    
    FILES_TO_DELETE=(
        "log/sim_log.txt"
        "log/trace_dump.txt"
        "log/compare_result.txt"
        "log/sim_wave.vcd"
    )
    
    DELETED=0
    for file in "${FILES_TO_DELETE[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo "  Removed: $file"
            DELETED=$((DELETED + 1))
        fi
    done
    
    if [[ $DELETED -eq 0 ]]; then
        echo "  No log files to remove."
    else
        echo "  Removed $DELETED file(s)."
    fi
    exit 0
fi

# ── Step 1/2: Clean + Build ──────────────────────────────────
echo "╔══════════════════════════════════════════════╗"
echo "║  Step 1-2: Clean & Build (with --trace)      ║"
echo "╚══════════════════════════════════════════════╝"
./run_sim.sh --clear --build

# ── Step 3: Run simulation ───────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Step 3: Running simulation → generating VCD ║"
echo "╚══════════════════════════════════════════════╝"
./run_sim.sh --run $FIRMWARE_ARG

# ── Step 4: Verify and open waveform ─────────────────────────
echo ""
if [[ -f "$VCD_FILE" ]]; then
    local_size=$(stat -c%s "$VCD_FILE" 2>/dev/null || echo "0")
    echo "╔══════════════════════════════════════════════╗"
    echo "║  Step 4: Opening waveform in GTKWave         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo "  VCD file : $VCD_FILE (${local_size} bytes)"
    echo ""

    if command -v gtkwave &>/dev/null; then
        gtkwave "$VCD_FILE" &
        echo "[OK] GTKWave launched (PID: $!)"
    else
        echo "[WARN] gtkwave not found in PATH."
        echo "  Install with: sudo apt install gtkwave"
        echo "  Or manually open: $VCD_FILE"
    fi
else
    echo "[ERROR] VCD file not generated: $VCD_FILE"
    echo "  Check simulation output above for errors."
    exit 1
fi

echo ""
echo "Done!"
