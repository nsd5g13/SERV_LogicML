#!/usr/bin/env python3
"""
compare_traces.py — Merge sim_log.txt with trace_dump.txt

Reads the cycle-cost log (sim_log.txt) and the instruction trace
(trace_dump.txt), then produces a combined log that shows each
instruction's mnemonic alongside its cycle cost.

Input files  (in cwd or serv_project/):
    sim_log.txt    — lines like:  0x4 -> 0x8 : 36 cycles
    trace_dump.txt — lines like:  3  0x0000000c  sb

Output file (written to cwd):
    compare_result.txt
"""

import os
import re
import sys

# ── Locate files ─────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_DIR    = os.path.join(SCRIPT_DIR, "log")
SIM_LOG    = os.path.join(LOG_DIR, "sim_log.txt")
TRACE_DUMP = os.path.join(LOG_DIR, "trace_dump.txt")
OUTPUT     = os.path.join(LOG_DIR, "compare_result.txt")

# ── Parse trace_dump.txt → {address: mnemonic} ───────────────
# Lines look like:  "       3  0x0000000c  sb"
instr_map = {}
with open(TRACE_DUMP, "r") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"\s*\d+\s+(0x[0-9a-fA-F]+)\s+(\S+)", line)
        if m:
            addr = int(m.group(1), 16)
            mnemonic = m.group(2)
            instr_map[addr] = mnemonic

# ── Parse sim_log.txt and merge ──────────────────────────────
# Lines look like:  "0x4 -> 0x8 : 36 cycles"
#
# Some instructions (e.g. sw, lbu) span two entries in sim_log:
#   0x168 -> 0xffc : 36 cycles   (first half — has a mnemonic)
#   0xffc -> 0x16c : 34 cycles   (second half — ??? in trace)
# When a ??? entry's from_addr == prev to_addr, merge them
# so the combined cycle cost is reported under the real instruction.
results = []
last_mnemonic = "???"
with open(SIM_LOG, "r") as f:
    for line in f:
        line = line.strip()
        m = re.match(r"(0x[0-9a-fA-F]+)\s*->\s*(0x[0-9a-fA-F]+)\s*:\s*(\d+)\s*cycles", line)
        if not m:
            continue
        from_addr = int(m.group(1), 16)
        to_addr   = int(m.group(2), 16)
        cycles    = int(m.group(3))
        mnemonic  = instr_map.get(from_addr, "???")

        # Merge ??? continuations into the previous entry
        if mnemonic == "???" and results and from_addr == results[-1][1]:
            prev = results[-1]
            results[-1] = (prev[0], to_addr, prev[2], prev[3] + cycles)
        else:
            results.append((from_addr, to_addr, mnemonic, cycles))

# ── Write output ─────────────────────────────────────────────
with open(OUTPUT, "w") as f:
    f.write(f"# Merged trace: {os.path.basename(SIM_LOG)} + {os.path.basename(TRACE_DUMP)}\n")
    f.write(f"# Total instructions traced: {len(results)}\n")
    f.write(f"#\n")
    f.write(f"# {'PC':>10s}  {'Next PC':>10s}  {'Instr':<8s}  {'Cycles':>6s}\n")
    f.write(f"# {'-'*10}  {'-'*10}  {'-'*8}  {'-'*6}\n")
    for from_addr, to_addr, mnemonic, cycles in results:
        f.write(f"  0x{from_addr:08x}  0x{to_addr:08x}  {mnemonic:<8s}  {cycles:>6d}\n")

    # Summary statistics
    if results:
        cycle_values = [r[3] for r in results]
        total   = sum(cycle_values)
        average = total / len(cycle_values)
        minimum = min(cycle_values)
        maximum = max(cycle_values)

        f.write(f"\n# ── Summary ──────────────────────────────\n")
        f.write(f"# Instructions : {len(results)}\n")
        f.write(f"# Total cycles : {total}\n")
        f.write(f"# Avg cycles   : {average:.1f}\n")
        f.write(f"# Min cycles   : {minimum}\n")
        f.write(f"# Max cycles   : {maximum}\n")

        # Per-instruction average
        from collections import defaultdict
        per_instr = defaultdict(list)
        for _, _, mnemonic, cycles in results:
            per_instr[mnemonic].append(cycles)

        f.write(f"\n# ── Average cycle cost per instruction ──\n")
        f.write(f"# {'Instr':<8s}  {'Count':>5s}  {'Avg':>7s}  {'Min':>5s}  {'Max':>5s}\n")
        f.write(f"# {'-'*8}  {'-'*5}  {'-'*7}  {'-'*5}  {'-'*5}\n")
        for mnemonic in sorted(per_instr):
            vals = per_instr[mnemonic]
            f.write(f"  {mnemonic:<8s}  {len(vals):>5d}  {sum(vals)/len(vals):>7.1f}  {min(vals):>5d}  {max(vals):>5d}\n")

print(f"Written {len(results)} entries to {OUTPUT}")
