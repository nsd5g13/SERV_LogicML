#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  Reproduce the memory-range popcount custom-instruction test
#
#  Tests popcount rd, rs1(start), rs2(byte_offset) over a 10-word array
#  (offset=36) plus boundary cases (offset 0/4/8/7, misaligned start,
#  offset=2048 max) and verifies the custom-instruction result equals the
#  software popcount.
#
#  Usage: ./reproduce_range_popcount.sh
#
#  The custom-instruction result is printed via UART to the terminal:
#    range: 0x00000568 offset=36 (10 words)
#    custom = 154 (0x0000009a)
#    sw     = 154 (0x0000009a)
#    RESULT: PASS
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")"

echo "════════════════════════════════════════════════"
echo "  Range Popcount Reproduction"
echo "════════════════════════════════════════════════"

# [1/3] Build firmware (default build_codes folder)
echo ""
echo "[1/3] Building firmware..."
./build.sh --build > /tmp/rep_build.log 2>&1
echo "  firmware.hex generated ($(wc -l < firmware.hex) words)"

# [2/3] Run fusesoc simulation (rebuilds Verilator model on first run)
echo ""
echo "[2/3] Running fusesoc simulation (UART output below)..."
SIM_TIMEOUT=120 timeout 250 ./build.sh --run > /tmp/rep_sim.log 2>&1 || {
    echo "  [ERROR] simulation failed — see /tmp/rep_sim.log"
    exit 1
}

# [3/3] Show UART results + confirm completion
echo ""
echo "════════════════════════════════════════════════"
echo "  CUSTOM INSTRUCTION RESULT (from UART)"
echo "════════════════════════════════════════════════"
grep -E "range:|custom =|sw     =|RESULT" /tmp/rep_sim.log || echo "  [WARN] no UART output captured"

if grep -q "Test complete" /tmp/rep_sim.log; then
    echo ""
    echo "  Simulation completed normally"
else
    echo "  [WARN] no 'Test complete'"
fi

# Automated PASS/FAIL check from PC trace (PC 0x88 = 'P' branch)
python3 << 'PYEOF'
data = open('build/award-winning_serv_servant_1.4.0/verilator_tb/trace.bin','rb').read()
import struct
pcs = [struct.unpack('<I', data[i:i+4])[0] for i in range(0, len(data), 4)]
seen = []
for p in pcs:
    if not seen or seen[-1] != p:
        seen.append(p)
if 0x88 in seen:
    print("  ==> PASS (custom result == software result)")
else:
    print("  ==> FAIL")
PYEOF
