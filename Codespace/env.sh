#!/usr/bin/env bash
# ============================================================
#  riscv_benchmark — unified development environment
#  Source this file to add all project tools to PATH.
#
#  Usage:
#    source ~/riscv_benchmark/Codespace/env.sh
#
#  Auto-loaded when opening ~/riscv_benchmark in VS Code
#  via .bashrc integration.
# ============================================================

# ── Guard: avoid re-sourcing ─────────────────────────────────
if [[ "${_RISCV_BENCH_ENV_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || true
fi

# ── Helper: prepend PATH only once ───────────────────────────
_path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

# ============================================================
#  Project directories
# ============================================================
export RISCV_BENCHMARK="$HOME/riscv_benchmark"
export CODESPACE_DIR="$RISCV_BENCHMARK/Codespace"
export SERV_PROJECT="$RISCV_BENCHMARK/serv_project"

# ============================================================
#  Local tool paths (only added if they exist)
# ============================================================
_tools() {
    local dir="$RISCV_BENCHMARK/tools/$1"
    [[ -d "$dir" ]] && _path_prepend "$dir"
}

_tools "riscv/bin"
_tools "riscv64/usr/bin"
_tools "verilator/usr/bin"
_tools "make/usr/bin"
_tools "fusesoc-venv/bin"
_tools "gcc-host/usr/bin"
_path_prepend "$HOME/.local/bin"

# ============================================================
#  RISC-V bare-metal toolchain
# ============================================================
export RISCV64_PREFIX="riscv64-unknown-elf-"
export RISCV32_PREFIX="riscv32-unknown-elf-"
export RISCV_ARCH="rv32imc_zicsr_zifencei"
export RISCV_ABI="ilp32"

# ============================================================
#  Host tools (prefer local, fall back to system)
# ============================================================
export PYTHON="/usr/bin/python3"
export VERILATOR="$(command -v verilator 2>/dev/null || echo "$RISCV_BENCHMARK/tools/verilator/usr/bin/verilator")"
export FUSESOC="$(command -v fusesoc 2>/dev/null || echo "$HOME/.local/bin/fusesoc")"
# Prefer the custom-built objdump (knows the popcount mnemonic), fall back to PATH.
_CUSTOM_OBJDUMP="$RISCV_BENCHMARK/riscv-gnu-toolchain/install/bin/riscv64-unknown-elf-objdump"
if [[ -x "$_CUSTOM_OBJDUMP" ]]; then
    export OBJDUMP="$_CUSTOM_OBJDUMP"
else
    export OBJDUMP="$(command -v riscv64-unknown-elf-objdump 2>/dev/null || echo "riscv64-unknown-elf-objdump")"
fi

# ============================================================
#  Aliases
# ============================================================
alias rb='cd "$RISCV_BENCHMARK"'
alias codes='cd "$CODESPACE_DIR"'
alias servp='cd "$SERV_PROJECT"'

# ============================================================
#  Mark as loaded
# ============================================================
export _RISCV_BENCH_ENV_LOADED=1

# ── Quiet confirmation ───────────────────────────────────────
echo "[riscv_benchmark env] PATH updated, tools ready."
