#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  Cycle Cost Calculator
# ═══════════════════════════════════════════════════════════════════════
#
#  Purpose:
#    Reads log/compare_result.txt and calculates the total cycle cost
#    between two user-specified PC addresses.
#
#  Usage:
#    ./scripts/cycle_cost.sh <start_addr> <end_addr>
#    ./scripts/cycle_cost.sh --clear
#
#  Examples:
#    ./scripts/cycle_cost.sh 48 6c
#    ./scripts/cycle_cost.sh 0x48 0x6c
#    ./scripts/cycle_cost.sh 0x00000048 0x0000006c
#    ./scripts/cycle_cost.sh --clear
#
#  The addresses are user-defined — pass any two addresses that appear
#  in compare_result.txt. They will be normalized to match the format
#  in the file (0x000000XX).
#
#  Output:
#    - Terminal: instruction-by-instruction breakdown + summary
#    - log/cycle_cost_<start>_<end>.txt: pure dump of the result
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPARE_FILE="$PROJECT_DIR/log/compare_result.txt"

# ── Colors ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Usage ──────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <start_addr> <end_addr>"
    echo ""
    echo "Calculate cycle cost between two PC addresses in compare_result.txt."
    echo ""
    echo "Arguments:"
    echo "  start_addr   Start PC (e.g. 48, 0x48, 0x00000048)"
    echo "  end_addr     End PC   (e.g. 6c, 0x6c, 0x0000006c)"
    echo ""
    echo "Examples:"
    echo "  $0 48 6c"
    echo "  $0 0x48 0x6c"
    echo "  $0 0x00000048 0x0000006c"
    echo ""
    echo "Output: log/cycle_cost_<start>_<end>.txt"
    exit 1
}

# ── Handle --clear ─────────────────────────────────────────────────────
if [[ "${1:-}" == "--clear" ]]; then
    echo "Clearing cycle_cost dump files..."
    rm -f "$PROJECT_DIR"/log/cycle_cost_*.txt
    echo "Done. Removed: $PROJECT_DIR/log/cycle_cost_*.txt"
    exit 0
fi

[[ $# -ne 2 ]] && usage
[[ "$1" == "-h" || "$1" == "--help" ]] && usage

# ── Validate input ─────────────────────────────────────────────────────
if [[ ! -f "$COMPARE_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} compare_result.txt not found: $COMPARE_FILE"
    echo "  Run ./run_sim.sh first to generate the trace."
    exit 1
fi

# ── Normalize address to 0x000000XX format ────────────────────────────
normalize_addr() {
    local addr="$1"
    # Strip 0x/0X prefix
    addr="${addr#0x}"
    addr="${addr#0X}"
    # Strip leading zeros
    addr="${addr##+(0)}"
    [[ -z "$addr" ]] && addr="0"
    printf "0x%08x" "0x$addr"
}

START_ADDR=$(normalize_addr "$1")
END_ADDR=$(normalize_addr "$2")

# Short names for dump filename
START_SHORT=$(echo "$START_ADDR" | sed 's/^0x0*//')
END_SHORT=$(echo "$END_ADDR" | sed 's/^0x0*//')
DUMP_FILE="$PROJECT_DIR/log/cycle_cost_${START_SHORT}_${END_SHORT}.txt"

# ── Header ─────────────────────────────────────────────────────────────
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Cycle Cost Analysis${NC}"
echo -e "  Start: ${CYAN}${START_ADDR}${NC}"
echo -e "  End:   ${CYAN}${END_ADDR}${NC}"
echo -e "  Source: ${COMPARE_FILE}"
echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
echo ""

# ── Parse and calculate with awk ──────────────────────────────────────
awk -v start="$START_ADDR" -v end="$END_ADDR" -v dump_file="$DUMP_FILE" '
BEGIN {
    in_range = 0
    total_cycles = 0
    instruction_count = 0
    found_start = 0
    found_end = 0

    # Header for dump file
    printf "# Cycle cost: %s -> %s\n", start, end > dump_file
    printf "#\n" > dump_file
    printf "# %-14s %-14s %-10s %s\n", "PC", "Next PC", "Instr", "Cycles" > dump_file
    printf "# %-14s %-14s %-10s %s\n", "--------------", "--------------", "----------", "------" > dump_file
}

# Skip comment lines and blank lines
/^#/ { next }
/^[[:space:]]*$/ { next }

{
    pc      = $1
    next_pc = $2
    instr   = $3
    cycles  = $4 + 0

    # ── Detect start address ──────────────────────────────────────
    if (pc == start && !in_range) {
        in_range = 1
        found_start = 1
        total_cycles += cycles
        instruction_count++
        instr_count[instr]++
        instr_cycles[instr] += cycles
        printf "  \033[32m▶ START\033[0m  %s  %-8s  %d cycles\n", pc, instr, cycles
        printf "  %-14s %-14s %-10s %d\n", pc, next_pc, instr, cycles > dump_file
        next
    }

    # ── Detect end address ────────────────────────────────────────
    if (pc == end && in_range) {
        found_end = 1
        in_range = 0
        total_cycles += cycles
        instruction_count++
        instr_count[instr]++
        instr_cycles[instr] += cycles
        printf "  \033[31m◀ END\033[0m    %s  %-8s  %d cycles\n", pc, instr, cycles
        printf "  %-14s %-14s %-10s %d\n", pc, next_pc, instr, cycles > dump_file
        next
    }

    # ── Accumulate cycles in range ────────────────────────────────
    if (in_range) {
        total_cycles += cycles
        instruction_count++
        instr_count[instr]++
        instr_cycles[instr] += cycles
        printf "  %-14s %-14s %-10s %d\n", pc, next_pc, instr, cycles
        printf "  %-14s %-14s %-10s %d\n", pc, next_pc, instr, cycles > dump_file
    }
}

END {
    printf "\n" > dump_file

    # ── Error handling ────────────────────────────────────────────
    if (!found_start) {
        printf "\n  \033[31m[ERROR]\033[0m Start address %s not found in trace\n", start
        printf "# ERROR: Start address %s not found\n", start > dump_file
        exit 1
    }
    if (!found_end) {
        printf "\n  \033[31m[ERROR]\033[0m End address %s not found in trace\n", end
        printf "# ERROR: End address %s not found\n", end > dump_file
        exit 1
    }

    # ── Summary to terminal ───────────────────────────────────────
    printf "\n\033[1m── Summary ──────────────────────────────────────\033[0m\n"
    printf "  Total cycles:    \033[32m%d\033[0m\n", total_cycles
    printf "  Instructions:    %d\n", instruction_count
    if (instruction_count > 0)
        printf "  Average CPI:     %.2f\n", total_cycles / instruction_count

    # ── Instruction breakdown to terminal ─────────────────────────
    printf "\n\033[1m── Instruction Breakdown ─────────────────────────\033[0m\n"
    printf "  \033[1m%-10s  %8s  %12s  %10s\033[0m\n", "Instr", "Count", "Total Cycles", "Avg Cycles"
    printf "  %-10s  %8s  %12s  %10s\n", "----------", "--------", "------------", "----------"

    # Collect and sort instruction names
    n = asorti(instr_count, sorted)
    for (i = 1; i <= n; i++) {
        name = sorted[i]
        cnt = instr_count[name]
        cyc = instr_cycles[name]
        avg = cyc / cnt
        printf "  %-10s  %8d  %12d  %10.2f\n", name, cnt, cyc, avg
    }

    # ── Summary to dump file ──────────────────────────────────────
    printf "#\n" > dump_file
    printf "# Summary:\n" > dump_file
    printf "#   Total cycles:    %d\n", total_cycles > dump_file
    printf "#   Instructions:    %d\n", instruction_count > dump_file
    if (instruction_count > 0)
        printf "#   Average CPI:     %.2f\n", total_cycles / instruction_count > dump_file

    # ── Instruction breakdown to dump file ────────────────────────
    printf "#\n" > dump_file
    printf "# Instruction Breakdown:\n" > dump_file
    printf "# %-10s  %8s  %12s  %10s\n", "Instr", "Count", "Total Cycles", "Avg Cycles" > dump_file
    printf "# %-10s  %8s  %12s  %10s\n", "----------", "--------", "------------", "----------" > dump_file

    for (i = 1; i <= n; i++) {
        name = sorted[i]
        cnt = instr_count[name]
        cyc = instr_cycles[name]
        avg = cyc / cnt
        printf "# %-10s  %8d  %12d  %10.2f\n", name, cnt, cyc, avg > dump_file
    }
}
' "$COMPARE_FILE"

# ── Done ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[INFO]${NC}  Dump written to: $DUMP_FILE"
