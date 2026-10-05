#!/usr/bin/env python3
"""
trace_dump.py — Convert SERV trace.bin into a human-readable text trace.

Reads the raw 32-bit-integer binary trace and writes one line per cycle:
    [index]  0xXXXXXXXX  <symbol>       (if symbol resolved)
    [index]  0xXXXXXXXX                  (otherwise)

Also generates a pure disassembly dump file (firmware.dump) at the project root.

Optionally resolves PCs to symbols via $OBJDUMP (set by Codespace/env.sh).

Usage:
    python3 trace_dump.py                         # auto-detect paths
    python3 trace_dump.py <trace.bin> [firmware.elf] [output.txt]
    python3 trace_dump.py --clear                 # remove generated files
"""

import struct
import subprocess
import sys
import os
from pathlib import Path

# ── Default paths (relative to project root) ────────────────
SCRIPT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_TRACE  = SCRIPT_DIR / "build" / "award-winning_serv_servant_1.4.0" / "verilator_tb" / "trace.bin"
DEFAULT_ELF    = SCRIPT_DIR / "firmware.elf"
DEFAULT_OUT    = SCRIPT_DIR / "log" / "trace_dump.txt"
DEFAULT_DUMP   = SCRIPT_DIR / "firmware.dump"

# Ensure log directory exists
os.makedirs(SCRIPT_DIR / "log", exist_ok=True)

# ── Tool from environment (set by Codespace/env.sh) ─────────
# Prefer the custom-built objdump (knows the popcount mnemonic).
_CUSTOM_OBJDUMP = SCRIPT_DIR / ".." / "riscv-gnu-toolchain" / "install" / "bin" / "riscv64-unknown-elf-objdump"
OBJDUMP = os.environ.get("OBJDUMP", "")
if not OBJDUMP or not os.access(OBJDUMP, os.X_OK):
    OBJDUMP = str(_CUSTOM_OBJDUMP) if _CUSTOM_OBJDUMP.is_file() else "riscv64-unknown-elf-objdump"


def parse_args():
    trace_bin = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRACE
    elf_file  = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_ELF
    out_file  = Path(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_OUT
    return trace_bin, elf_file, out_file


def read_trace(path: Path) -> list[int]:
    """Read trace.bin as an array of 32-bit unsigned integers."""
    data = path.read_bytes()
    n = len(data) // 4
    return list(struct.unpack(f"<{n}I", data))


def build_symbol_map(elf: Path) -> dict[int, str]:
    """
    Run riscv64-unknown-elf-objdump -d on the ELF and build a PC → symbol map.
    Returns e.g. {0x20: 'bitbang', 0x30: 'bitbang.bitbang', ...}.
    """
    sym = {}
    if not elf.exists():
        return sym
    try:
        result = subprocess.run(
            [OBJDUMP, "-d", str(elf)],
            capture_output=True, text=True, timeout=30,
        )
    except FileNotFoundError:
        print(f"WARNING: {OBJDUMP} not found, skipping symbol resolution", file=sys.stderr)
        return sym

    current_func = ""
    for line in result.stdout.splitlines():
        # Function header:  00000000 <bitbang>:
        if line and line[0] == " " and "<" in line and ">:" in line:
            # e.g. "  00000020 <bitbang>:"
            parts = line.strip().split()
            if len(parts) >= 2:
                addr_str = parts[0]
                name = parts[1].strip("<>:")
                try:
                    sym[int(addr_str, 16)] = name
                except ValueError:
                    pass
        # Disassembly line:  20:  00000093  addi  x0,x0,0
        elif line.startswith(" ") and len(line.strip()) > 0:
            parts = line.strip().split()
            if parts:
                try:
                    addr = int(parts[0].rstrip(":"), 16)
                    # Only store if not already a function header
                    if addr not in sym:
                        # Use the instruction mnemonic as label
                        mnemonic = parts[2] if len(parts) > 2 else ""
                        if mnemonic:
                            sym[addr] = mnemonic
                except (ValueError, IndexError):
                    pass
    return sym


def write_dump(pcs: list[int], symbols: dict[int, str], out: Path):
    """Write the trace dump to a text file."""
    with open(out, "w") as f:
        f.write(f"# SERV trace dump\n")
        f.write(f"# {'index':>6s}  {'PC':>12s}  {'symbol'}\n")
        f.write(f"# {'-'*6}  {'-'*12}  {'-'*30}\n")
        for i, pc in enumerate(pcs):
            name = symbols.get(pc, "")
            f.write(f"  {i:6d}  0x{pc:08x}  {name}\n")
    return out


def write_pure_dump(elf: Path, out: Path):
    """
    Generate a pure disassembly dump using riscv64-unknown-elf-objdump.
    Produces a clean, unmodified dump with -M no-aliases,numeric.
    """
    try:
        result = subprocess.run(
            [OBJDUMP, "-d", "-M", "no-aliases,numeric", str(elf)],
            capture_output=True, text=True, timeout=60,
        )
        with open(out, "w") as f:
            f.write(result.stdout)
        return out
    except FileNotFoundError:
        print(f"WARNING: {OBJDUMP} not found, skipping pure dump", file=sys.stderr)
        return None
    except subprocess.TimeoutExpired:
        print(f"WARNING: objdump timed out, skipping pure dump", file=sys.stderr)
        return None


def main():
    # ── Handle --clear ──────────────────────────────────────────
    if len(sys.argv) > 1 and sys.argv[1] == "--clear":
        files = [
            SCRIPT_DIR / "log" / "trace_dump.txt",
            SCRIPT_DIR / "firmware.dump",
        ]
        removed = 0
        for f in files:
            if f.exists():
                f.unlink()
                print(f"  Removed: {f}")
                removed += 1
        if removed == 0:
            print("  No files to remove.")
        else:
            print(f"  Removed {removed} file(s).")
        return

    trace_path, elf_path, out_path = parse_args()

    if not trace_path.exists():
        print(f"ERROR: trace file not found: {trace_path}", file=sys.stderr)
        sys.exit(1)

    print(f"  Trace file : {trace_path}")
    print(f"  ELF file   : {elf_path}")
    print(f"  Output     : {out_path}")
    print()

    # Read trace
    pcs = read_trace(trace_path)

    # Build symbol map
    symbols = build_symbol_map(elf_path)
    unique_pcs = set(pcs)
    resolved = unique_pcs & set(symbols.keys())
    print(f"  Unique PCs in trace: {len(unique_pcs)}")
    print(f"  Symbol-resolved PCs: {len(resolved)}/{len(unique_pcs)}")
    print()

    # Write output
    out = write_dump(pcs, symbols, out_path)
    print(f"  Written to {out}")

    # Write pure disassembly dump
    dump = write_pure_dump(elf_path, DEFAULT_DUMP)
    if dump:
        print(f"  Pure dump: {dump}")


if __name__ == "__main__":
    main()
