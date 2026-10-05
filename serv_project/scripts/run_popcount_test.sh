#!/usr/bin/env bash
# Usage:
#   ./run_popcount_test.sh [max_val=10000] [sim_timeout=60]
#   ./run_popcount_test.sh --serv-dir=fusesoc_libraries/serv_bne  (optional, BNE variant)
#
# Tests 0..max_val step 10, compares custom popcnt vs software popcnt.
# Output: log/popcount_test.txt (clean log, summary first)

set -euo pipefail
cd "$(dirname "$0")"

# SERV RTL variant (popcount vs BNE early-exit). Overridable via --serv-dir=...
# or the SERV_DIR environment variable. Used for sw/link.ld and sw/makehex.py.
SERV_DIR="${SERV_DIR:-fusesoc_libraries/serv_v1.5_rtl}"

# Parse optional --serv-dir=... flag (positional max_val/timeout still allowed)
MAX_TEST="${1:-10000}"
TIMEOUT="${2:-60}"
if [[ "${MAX_TEST}" == --serv-dir=* ]]; then
    SERV_DIR="${MAX_TEST#*=}"
    MAX_TEST="${2:-10000}"
    TIMEOUT="${3:-60}"
fi

LOGFILE="log/popcount_test.txt"
RAWLOG="log/popcount_test_raw.txt"
mkdir -p log

echo "=== Popcount Test: 0 to ${MAX_TEST} step 10 (SERV_DIR=${SERV_DIR}) ==="

# Build firmware
riscv64-unknown-elf-gcc \
    -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles -ffreestanding \
    -O2 -I../Codespace \
    -DMAX_TEST=${MAX_TEST} \
    -T ${SERV_DIR}/sw/link.ld \
    -o firmware.elf \
    ../Codespace/SERV_codespace/build_codes/startup.S \
    ../Codespace/SERV_codespace/build_codes/popcount.c

riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
python3 ${SERV_DIR}/sw/makehex.py firmware.bin 4096 > firmware.hex

# Run simulation
set +e
timeout "${TIMEOUT}s" ./build.sh --run 2>&1 > "$RAWLOG" || true
RC=$?
set -e

# Extract clean test output: only UART lines from firmware
# (filter out build noise, Entering/Leaving directory, prompts, timestamps, etc.)
grep "^P \|^F \|^=== SUMMARY\|^Total:\|^Pass:\|^Fail:\|^ALL PASSED\|^FAIL details" "$RAWLOG" > "$LOGFILE" || true

# Count results
FAIL=$(grep -c "^F " "$LOGFILE" || true)
TOTAL=$(grep -c "^[PF] " "$LOGFILE" || true)
PASS=$((TOTAL - FAIL))

# Build final log: summary first, then details
{
    echo "=== POPCOUNT TEST REPORT ==="
    echo "Range: 0 to ${MAX_TEST} step 10"
    echo ""
    echo "=== SUMMARY ==="
    echo "Tests: $TOTAL"
    echo "Pass:  $PASS"
    echo "Fail:  $FAIL"
    [ $RC -eq 124 ] && echo "Status: TIMEOUT after ${TIMEOUT}s (incomplete)"
    [ $RC -ne 124 ] && [ $FAIL -eq 0 ] && echo "Status: ALL PASSED"
    [ $FAIL -gt 0 ] && echo "Status: FAILURES DETECTED"

    if [ "$FAIL" -gt 0 ]; then
        echo ""
        echo "--- FAIL DETAILS ---"
        grep "^\s*F " "$LOGFILE"
    fi

    echo ""
    echo "=== DETAILED RESULTS ==="
    cat "$LOGFILE"
} > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"

echo "Done. Log: $LOGFILE"
