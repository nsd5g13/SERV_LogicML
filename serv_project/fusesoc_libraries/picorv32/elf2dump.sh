#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  PicoRV32 ELF → Dump Disassembly Script
# ═══════════════════════════════════════════════════════════════════════
#
#  Converts firmware.elf into a disassembly dump file using the
#  riscv32-unknown-elf toolchain.
#
#  Usage:
#    ./elf2dump.sh                  Use default firmware.elf
#    ./elf2dump.sh myfirmware.elf   Use a specific ELF file
#    ./elf2dump.sh --clean          Remove dump files
#
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── RISC-V 32-bit toolchain ──────────────────────────────────
RISCV32_BIN="${RISCV32_BIN:-$SCRIPT_DIR/../../../tools/riscv/bin}"
OBJDUMP="$RISCV32_BIN/riscv32-unknown-elf-objdump"
SIZE="$RISCV32_BIN/riscv32-unknown-elf-size"

# ── Colored output ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ── Clean ─────────────────────────────────────────────────────
if [[ "${1:-}" == "--clean" ]]; then
    rm -f firmware.dump
    echo "Cleaned: firmware.dump"
    exit 0
fi

# ── Input / Output ────────────────────────────────────────────
ELF="${1:-firmware.elf}"
DUMP="${ELF%.elf}.dump"

[[ -x "$OBJDUMP" ]] || fail "objdump not found at: $OBJDUMP"
[[ -f "$ELF" ]]      || fail "ELF not found: $ELF — run build_pico32.sh first"

# ══════════════════════════════════════════════════════════════
#  Generate dump
# ══════════════════════════════════════════════════════════════
echo "════════════════════════════════════════"
echo "  ELF → Dump (riscv32)"
echo "════════════════════════════════════════"

info "Input:  $ELF"
info "Output: $DUMP"
echo ""

# Section sizes
info "Section sizes:"
$SIZE "$ELF"
echo ""

# Full disassembly with source interleaving
info "Generating disassembly..."
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "  PicoRV32 Firmware Disassembly Dump"
    echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    echo "── Section sizes ──"
    $SIZE "$ELF"
    echo ""

    echo "── Disassembly (.text) ──"
    $OBJDUMP -d -S -M numeric,no-aliases "$ELF"
    echo ""

    echo "── Full contents (all sections) ──"
    $OBJDUMP -D -M no-aliases "$ELF"
    echo ""

    echo "── Symbol table ──"
    $OBJDUMP -t "$ELF"
    echo ""

    echo "═══════════════════════════════════════════════════════════════"
    echo "  End of dump"
    echo "═══════════════════════════════════════════════════════════════"
} > "$DUMP"

ok "Dump saved: $DUMP ($(wc -l < "$DUMP") lines)"
echo ""
ok "Done!"
