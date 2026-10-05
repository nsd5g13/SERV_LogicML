#!/bin/bash
# =================================================================
# Static instruction counter for firmware.elf
# Counts every unique mnemonic across ALL functions/sections,
# or between two user-defined labels if both exist in the ELF.
#
# Usage:
#   ./instr_counter.sh [firmware.elf] [start_label] [end_label]
#   ./instr_counter.sh --clear
#
# When labels are given and both exist, only instructions between
# start_label (inclusive) and end_label (exclusive) are counted.
# Otherwise falls back to counting the entire ELF.
# Use --clear to remove the generated log file.
#
# Output: log/instr_count.log
# =================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/log"
LOG_FILE="${LOG_DIR}/instr_count.log"

# ── Handle --clear ─────────────────────────────────────────
if [[ "${1:-}" == "--clear" ]]; then
    if [[ -f "$LOG_FILE" ]]; then
        rm -f "$LOG_FILE"
        echo "Removed: $LOG_FILE"
    else
        echo "No log file to remove."
    fi
    exit 0
fi

ELF_FILE="${1:-$SCRIPT_DIR/firmware.elf}"
START_LABEL="${2:-}"
END_LABEL="${3:-}"
OBJDUMP="${OBJDUMP:-riscv64-unknown-elf-objdump}"

if [[ ! -f "$ELF_FILE" ]]; then
    echo "ERROR: ELF file not found: $ELF_FILE" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

$OBJDUMP -d "$ELF_FILE" | awk -v elf="$ELF_FILE" \
                               -v start="$START_LABEL" \
                               -v end="$END_LABEL" '
BEGIN {
    if (start != "" && end != "") {
        mode = 'bet' 'ween'
        counting = 0
    } else {
        mode = 'a' 'll'
        counting = 1
    }
    found_start = 0
    found_end   = 0
}

# ── Match function / label headers ────────────────────────────
/<[A-Za-z0-9_$.]+>:/ {
    label = $0
    sub(/.*</, "", label)   # strip everything before <
    sub(/>.*/, "", label)   # strip everything after  >

    if (mode == 'bet' 'ween') {
        if (label == start) {
            counting    = 1
            found_start = 1
        }
        if (label == end && found_start) {
            counting  = 0
            found_end = 1
        }
    }
}

# ── Count instructions ────────────────────────────────────────
/^[[:space:]]*[0-9a-f]+:/ {
    if (counting && $3 != "") inst_count[$3]++
}

END {
    # ── Fallback: labels requested but not both found ─────────
    if (mode == 'bet' 'ween' && (!found_start || !found_end)) {
        if (!found_start)
            printf "Warning: start label \"%s\" not found\n", start > "/dev/stderr"
        if (!found_end)
            printf "Warning: end label \"%s\" not found\n", end > "/dev/stderr"
        printf "Falling back to full ELF count\n" > "/dev/stderr"
        # We skipped everything; re-run is handled by the shell below
        exit 2
    }

    # ── Print results ─────────────────────────────────────────
    total = 0
    for (ins in inst_count) total += inst_count[ins]

    print "========================================="
    print " Static instruction count"
    print " ELF: " elf
    if (mode == 'bet' 'ween')
        printf " Range: <%s> → <%s>\n", start, end
    print " Total instructions: " total
    print "========================================="
    for (ins in inst_count)
        printf "%-10s : %d\n", ins, inst_count[ins]
}
' > "$LOG_FILE" 2>&1 || {
    # awk exit 2 = labels not found, re-count entire ELF
    $OBJDUMP -d "$ELF_FILE" | awk -v elf="$ELF_FILE" '
    /^[[:space:]]*[0-9a-f]+:/ {
        if ($3 != "") inst_count[$3]++
    }
    END {
        total = 0
        for (ins in inst_count) total += inst_count[ins]
        print "========================================="
        print " Static instruction count (full ELF)"
        print " ELF: " elf
        print " Total instructions: " total
        print "========================================="
        for (ins in inst_count)
            printf "%-10s : %d\n", ins, inst_count[ins]
    }' > "$LOG_FILE"
}

echo "Log written to: $LOG_FILE"