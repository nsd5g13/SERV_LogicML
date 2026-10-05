#!/bin/bash
# ============================================================
#  riscv_benchmark — one-time setup script
#  Run this after cloning the repository or you miss mdu/fusesoc_cores/serv again
#
#  Usage:  ./setup.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo ""
echo "========================================"
echo "  riscv_benchmark setup"
echo "========================================"
echo ""

# ── Step 1: Initialize git submodules ────────────────────────
info "Initializing git submodules..."
if git submodule update --init --recursive 2>&1; then
    ok "Submodules ready"
else
    fail "Failed to initialize submodules. Check your network connection."
fi

echo ""

# ── Step 2: Verify submodule content ─────────────────────────
info "Verifying submodule content..."
MISSING=0
for dir in \
    serv_project/fusesoc_libraries/serv_v1.5_rtl \
    serv_project/fusesoc_libraries/mdu \
    serv_project/fusesoc_libraries/fusesoc_cores; do
    if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
        ok "  $dir"
    else
        warn "  $dir is empty!"
        MISSING=1
    fi
done

if [[ $MISSING -eq 1 ]]; then
    fail "Some submodules are empty. Try: git submodule update --init --recursive"
fi

echo ""

# ── Step 3: Source environment ───────────────────────────────
info "Loading environment..."
if [[ -f "Codespace/env.sh" ]]; then
    source "Codespace/env.sh" 2>/dev/null
    ok "Environment loaded"
else
    warn "Codespace/env.sh not found"
fi

echo ""

# ── Step 4: Verify tools ────────────────────────────────────
info "Checking required tools..."
TOOLS_OK=1
for tool_cmd in \
    "riscv64-unknown-elf-gcc:RISC-V GCC" \
    "python3:Python 3" \
    "fusesoc:FuseSoC" \
    "verilator:Verilator" \
    "make:Make"; do
    tool="${tool_cmd%%:*}"
    name="${tool_cmd#*:}"
    if command -v "$tool" &>/dev/null; then
        ok "  $name: $(command -v "$tool")"
    else
        warn "  $name: not found"
        TOOLS_OK=0
    fi
done

echo ""

if [[ $TOOLS_OK -eq 1 ]]; then
    echo "========================================"
    ok "Setup complete! All tools ready."
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  cd serv_project"
    echo "  ./build.sh --build --run"
else
    echo "========================================"
    warn "Setup complete, but some tools are missing."
    echo "========================================"
    echo ""
    echo "You may need to install missing tools or"
    echo "open a new terminal for PATH changes to take effect."
fi
echo ""
