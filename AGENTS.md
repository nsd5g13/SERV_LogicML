<!-- engineering-log hook | 请勿删改本段 -->
> **本项目受《工程日志规程》约束。**
> 工程日志**只允许追加**，不得编辑、不得删除任何已有条目。
> 凡涉及日志的读取、追加、蒸馏、审核、镜像，**必须先加载 skill：`engineering-log`**。

# AGENTS.md — SERV RISC-V Popcount Optimization

## Project Overview

**SERV** — the world's smallest RISC-V CPU. This project compiles firmware, runs it on a Verilator simulation of the SERV SoC, and produces detailed per-instruction cycle-cost reports.

**Key goals & Status**:
1. **Custom Popcount Optimization**: **ACHIEVED** — Custom popcount instruction runs at **42 cycles** with an **in-window writeback**: `rd` is clean (no high-bit garbage) and the following instruction has zero stall (runs at baseline 36 cycles). Saved as git tag **`v1.5_lucky`** (commit `271570b`).
2. **Unified RTL Merge (`serv_rtl_merge`)**: **ACHIEVED & FULLY VERIFIED** — Successfully unified the **42-cycle popcount** and **BNE branch early-exit** designs into `serv_project/fusesoc_libraries/serv_rtl_merge/` without any state-machine conflicts or redundant registers. Verified on `random_forest` (10 samples): Total cycles **464,213** (saving **61,995 cycles / -11.8%** vs. original SERV 526,208; saving **28,715 cycles / -5.8%** vs. v1.5_lucky 492,928). All 8,381 instructions have 0 path mismatches.
3. **PicoRV32 Comparative Baseline**: **ACHIEVED** — Automated compilation and simulation pipeline in `serv_project/fusesoc_libraries/picorv32/`. Runs `random_forest` in **39,901 clock cycles** (multi-cycle baseline).

**Next Plans / Future Milestones**:
- **Multi-Model Benchmark Suite**: Evaluate `serv_rtl_merge` and PicoRV32 across additional machine learning and standard workloads (`BNN`, `Tsetlin_Machine`, `dhrystone`).
- **Branch Optimization Extensions**: Evaluate feasibility of early-exit evaluation on signed and magnitude comparisons (`BLT`, `BGE`, `BLTU`, `BGEU`).
- **FPGA Synthesis & Resource Accounting**: Quantify LUT/FF resource utilization across `serv_rtl_origin`, `serv_v1.5_rtl`, `serv_bne`, and `serv_rtl_merge` to verify low silicon overhead.

## ⚠️ RTL Directory Map

```
serv_project/fusesoc_libraries/
├── serv_rtl_merge/         ← Unified merged design (popcount 42-cycle + BNE early-exit) [ACTIVE]
├── serv_v1.5_rtl/          ← v1.5 popcount design (42-cycle in-window writeback)
├── serv_bne/               ← BNE branch early-exit design
├── serv_rtl_origin/        ← Original upstream SERV, unmodified
├── serv_rtl_v1/            ← v1 popcount design (68-cycle)
└── picorv32/               ← PicoRV32 multi-cycle comparative baseline
```

**Do NOT read** (not relevant for this task):
- `serv_project/fusesoc_libraries/serv_rtl_origin/` (original SERV, unoptimized)
- Subdirectories outside `serv/rtl/`: `serv/servant/`, `serv/bench/`, `serv/sw/` (shared infrastructure / testbenches — read-only, do not change)
- `Codespace/`, `serv_project/scripts/`, and other top-level directories

> Core files for the popcount writeback: `serv_state.v`, `serv_top.v`, `serv_rf_ram_if.v`, `serv_customized_alu.v`, `serv_customized_state.v` (all under `serv/rtl/`).
> One exception: `servile/servile.v` contains the `i_rf_wr_busy` wiring (the real datapath); if you change `serv_rf_ram_if`/`serv_top` ports, check it in sync.

## ★ Current cpop route (2026-09-19) — READ BEFORE TOUCHING POPCOUNT

The custom popcount is triggered by the **official Zbb `cpop` encoding**
(`opcode=0010011` OP-IMM, `funct3=001`, `imm[11:0]=0x602`) — **not** the old
private custom-1 encoding `.insn r 0x2B, 0, 0`, which the RTL no longer
recognises. `serv_decode.v` in `serv_rtl_merge` matches that encoding
(commit `dac74f9`).

Firmware triggers it with a **local assembler scope** in the inline asm:

```c
asm volatile(".option push\n"
             ".option arch, +zbb\n"
             "cpop %0, %1\n"
             ".option pop\n"
             : "=r"(rd) : "r"(val));
```

### ⛔ Global `-march=...zbb` is ABANDONED — do not revive it

`-march` is a **promise** to the compiler, not a request. It makes GCC's
instruction selection free to use the whole extension. With `-march=rv32i_zbb`
GCC emitted, alongside `cpop`:

| source pattern | emitted | this RTL |
|---|---|---|
| `__builtin_popcount` | `cpop` | ✅ implemented |
| `a & ~b` | **`andn`** | ❌ silently computed as a plain `and` |
| `__builtin_clz` / `ctz` | `clz` / `ctz` | ❌ |
| `a<b?a:b` / `a>b?a:b` | `minu` / `maxu` | ❌ |
| rotate, `a\|~b`, `~(a^b)`, `bswap` | `rol` / `orn` / `xnor` / `rev8` | ❌ |

**Measured failure (2026-09-19)**: `random_forest` built with `--zbb` produced
`andn` × 2 (from `popcnt(lo & ~hi)` / `popcnt(hi & ~lo)`). SERV evaluates
`andn` as a plain `and` — `serv_alu.v` maps `bool_op=11` to `rs1 & op_b`. Since
`lo` and `hi` occupy disjoint bit positions, `lo & hi == 0`, so both vote
counts collapsed to 0 and **all 10 samples were classified as class 0** — with
no trap, no diagnostic, and `cpop` still reporting a healthy 42 cycles.

### Why the local `.option` form is the safe one

Keeping `-march=rv32i` globally makes other Zb instructions **impossible to
emit** — the compiler does not know Zbb exists. `.option` is an *assembler*
directive, so it only lets `as` parse the `cpop` mnemonic inside that block.
GAS then tags exactly that region with a `$xrv32i2p1_zbb1p0` **mapping
symbol**, and objdump disassembles **per mapping symbol** — so the dump shows
`cpop` instead of a bare `.insn`. (The ELF `Tag_RISCV_arch` stays `rv32i2p1`;
it is *not* what drives the display. Verified by building two objects with
byte-identical attributes and identical code bytes that still disassembled
differently.)

`build.sh --zbb` is kept **only to reproduce the experiment**. Do not use it
for real builds.

### Verified state on the merged RTL

| firmware | instructions / cycles | cpop | other Zb | result |
|---|---|---|---|---|
| `random_forest` (`--popcount`) | 8381 / 464213 | 20 × 42 | **0** | `[2,2,1,2,2,2,2,0,0,1]` = `predicted_class.txt` |
| `build_codes` | 1648 / 83657 | 1 × 42 | **0** | `popcount_sink = 0x14` |

## Current Design (v1.5_temp, commit `32f3f64`) — HISTORICAL: writeback superseded by v1.5_lucky

> ⚠️ The `custom_wr_active`/`wr_timer`/`custom_rd` out-of-band 36-cycle writeback described here is the **old mechanism**, removed in v1.5_lucky (commit `271570b`) and replaced by the "in-window writeback" (stage1 zero-fill + stage2 count write; see the **v1.5_lucky** section at the end). The stage1/stage2/`custom_stage2_done`/early-fetch structure is still valid.

The popcount instruction is a custom 2-stage instruction:

- **Stage 1** (`i_init=1`, 32 cycles): `cus_alu` accumulates set-bits of `rs1` into the 6-bit `pr_partial[5:0]`, while the PC shifts in PC+4 (`o_ctrl_pc_en = o_init ? o_cnt_en : 0`).
- **Stage 2** (`i_init=0`, **fixed 6 cycles**): `pr_partial` is shifted out LSB-first via `o_serial`; the count is written back to the RF.
- **Total**: 32 + 6 + fetch overhead ≈ **42 cycles**.

### Stage-2 control (serv_state.v)

- `custom_stage2_done = i_is_customized & !o_init & (o_cnt==3'd1) & cnt_r[1] & o_cnt_en` — fires at stage-2 count 5 (6th cycle), **data-independent** (no `is_acc_done` dependency).
- `o_cnt_done = (o_cnt[4:2]==7) & cnt_r[3] | custom_stage2_done`.
- At `custom_stage2_done`: the counter (`o_cnt` + `cnt_lsb`) is cleared (so the next instruction starts at count 0), and `ibus_cyc` is asserted to **early-fetch** the next instruction.
- `init_done` is **held** at `custom_stage2_done` and cleared on the early fetch's `i_ibus_ack` — this prevents the custom instruction from re-entering stage 1 (which would re-fire `o_rf_wreq` in a loop).
- `o_rf_wreq = ... | (i_is_customized & last_init)` — the write is triggered **once** at the stage-1→2 boundary (`last_init`).
- `o_rf_rreq` is deferred only while the **custom** writeback is draining (`custom_wr_drain`, set on `o_rf_wreq & i_is_customized`, cleared on `!i_rf_wr_busy`) so the next instruction's read does not reset `rcnt` mid-write. Ordinary writeback ops (branch/jump/lw/sw/shift) also raise `i_rf_wr_busy` but are NOT deferred (original SERV tolerated them — see bug 7).

### Writeback (serv_top.v — bypasses the main ALU) — superseded by v1.5_lucky

The popcount result is **not** routed through the main ALU. Instead (old scheme):

- `cus_alu.o_serial = pr_partial[0]` feeds `o_wdata0` directly.
- `custom_wr_active` is a **36-cycle one-shot** (set at `o_rf_wreq & is_customized & !custom_wr_active`, never re-triggered) that covers the whole serial RF write window.
- During the window:
  - `o_wdata0 = cus_serial` (count bits then zeros) — immune to `bufreg`/`op_b` corruption.
  - `o_wen0 = 1` — held high because the RF write enable is gated by `i_cnt_en`, which drops after the 6-cycle stage 2 (otherwise only the low 6 bits get written and the upper 26 bits retain the old register value).
  - `o_wreg0 = custom_rd` — the custom rd is latched at the write request, because the next instruction decodes before the serial write ends (otherwise the upper words get written to the wrong register).
- After the window, `o_wdata0`/`o_wen0`/`o_wreg0` revert to the normal RF path.
- `op_b = op_b_raw`, `alu_buf = bufreg_q` (plain sources — the ALU is no longer in the writeback path).

### RF write-busy wiring (servile.v — the important gotcha)

The SoC's real datapath is `servile` instantiating `serv_rf_ram_if` + `serv_top` **directly**; `serv_rf_top` is NOT used by the simulation. So `o_wr_busy` must be wired inside `servile.v`:

```
serv_rf_ram_if.o_wr_busy → rf_wr_busy → serv_top.i_rf_wr_busy
```

`serv_rf_ram_if` asserts `o_wr_busy` for ~34 cycles after each write request (`wr_busy_cnt`).

## Bugs found & fixed during this work

1. **Counter not fully cleared** — `o_cnt` stayed nonzero, so the next instruction started at count 4 and computed PC+4 wrong (`0x50→0x500`). Fixed by clearing `o_cnt` + `cnt_lsb` at `custom_stage2_done`.
2. **Double RF write trigger** — both `last_init` and `o_cnt_done & init_done` fired, resetting `rcnt` and zeroing the result. Kept only `i_is_customized & last_init`.
3. **`wr_busy` wired to the wrong module** — it was connected in `serv_rf_top` (unused); the real path is `servile`. Fixed in `servile.v`.
4. **`o_wen0` gated by `i_cnt_en`** — after stage 2 the counter is cleared so only the low 6 bits were written; upper 26 bits kept the old value (`0x4AC8`). Fixed by forcing `o_wen0` high during `custom_wr_active`.
5. **Write register stolen by next instruction** — `o_wreg0` changed to the next instr's rd mid-write; fixed by latching `custom_rd`.
6. **Custom instruction re-entering stage 1** — `init_done` cleared at stage-2 end made `o_init` flip back to 1, re-running the counter and re-firing `o_rf_wreq` forever. Fixed by holding `init_done` until the early fetch's `i_ibus_ack`.
7. **Global +1 on every writeback op's successor (v1.5 structural regression)** — deferring `o_rf_rreq` on the raw `i_rf_wr_busy` applied to ALL instructions, but ordinary writeback ops (branch/jump/lw/sw/shift/`.insn`) also assert `o_rf_wreq` → `wr_busy` → the next instruction's read was held 1 cycle. On identical v2 firmware, **5853/8381 instructions ran +1** vs v1 RTL (70%!), everywhere in the code, independent of popcount — proof the v1.5 writeback machinery had broken the original SERV state structure. **Fix (2026-09-03)**: added `custom_wr_drain` in serv_state.v — defer the read ONLY while the custom writeback is draining. Result: total 499281 → **493488**, all 8341 ordinary instructions cycle-identical to v1 RTL.

## Key RTL Signals

| Signal | Location | Meaning |
|---|---|---|
| `custom_stage2_done` | serv_state.v | stage-2 count 5 (6-cycle end) |
| `o_serial` / `cus_serial` | serv_customized_alu.v / serv_top.v | raw serial count bits (`pr_partial[0]`) |
| `custom_win` | serv_top.v | in-window writeback window (stage1+stage2) |
| `custom_wr_drain` | serv_state.v | custom writeback still draining (defer next read only then) |
| `o_wr_busy` / `i_rf_wr_busy` | serv_rf_ram_if.v / servile.v / serv_state.v | RF writeback in progress |
| `rf_rreq_pending` | serv_state.v | deferred read while custom writeback draining |

## Key Files & Commands

### Build & Simulation Pipeline

```bash
cd riscv_benchmark
./setup.sh                          # Fetch submodules, verify tools
source Codespace/env.sh             # Load toolchain into PATH

cd serv_project
./build.sh --build                  # Compile firmware into firmware.hex
./run_sim.sh                        # Clean + build Verilator model + simulate
cat log/compare_result.txt          # Merged trace with per-instruction cycle info
```

### Popcount Test

```bash
./serv_project/run_popcount_test.sh           # Default max_val=10000, timeout=60s
./serv_project/reproduce_range_popcount.sh
```

### Current Test Firmware

`Codespace/SERV_codespace/build_codes/popcount_cus.c` — computes `popcount_sink = popcnt_custom(0x000fffff)` (20) and prints it via UART as `popcount_sink = 0x00000014`:

```
popcount_sink = 0x00000014
```

(The old description said `popcnt_custom(19149)` → `0x08`; the test value has since changed to `0x000fffff`. Verified 2026-09-19: merged RTL, 1648 instr / 83657 cycles, `cpop` 1× @42, `popcount_sink` reads back `0x14`.)

UART output appears on the GPIO/`q` line (bit-banged by `asm_uart_putchar` in `startup.S`). The testbench does NOT capture UART; inspect `q` in `log/sim_wave.vcd` or add capture if needed.

### RTL Files of Interest

- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_customized_alu.v` — 6-bit `pr_partial` accumulator, `o_serial` output
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_customized_state.v` — `i_init` → `o_mode`/`o_clr` (mode gated on `i_cnt_en`)
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_state.v` — stage-2 control, counter, write/read requests
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_top.v` — in-window writeback (`o_wdata0`/`o_wen0`/`o_wreg0`, `custom_win`)
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_rf_ram_if.v` — `o_wr_busy`, `wr_busy_cnt`
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/servile/servile.v` — **real** datapath wiring of `i_rf_wr_busy`
- `serv_project/fusesoc_libraries/serv_v1.5_rtl/rtl/serv_decode.v` — identifies custom instructions (opcode `01010`)

## Git State

- **serv repo** (RTL): tag **`v1.5_lucky`** = commit `271570b` (in-window writeback; see section at end). Chain: `fe99b81` (bug-7 custom_wr_drain scope fix, 499281→493488) → `5e5ee9a` (force-stop writeback probe: follower 98→70 but rd high bits garbage) → `271570b` (in-window writeback: stage1 zero-fill + stage2 count write; rd clean and follower has no stall). Earlier: `32f3f64`=v1.5_temp, `29e4e38`, `6a7f684`, `f808bc5`.
- **top repo** (firmware/scripts): main = `b0a8fd0`.
- v1 RTL snapshot kept at `serv_project/serv_rtl_v1/` (gitignored); results saved as `log/v1_results` (68 cyc/insn, 666 total) and `log/v1.5_results` (42 cyc/insn, 614 total).
- `Codespace/SERV_codespace/Codehub/popcount.c` — older software/custom comparison test (reference only).

## Verification Outputs

- `log/sim_log.txt` — PC transitions with cycle counts per instruction
- `log/trace_dump.txt` — Symbol-resolved PC trace
- `log/compare_result.txt` — Merged trace with per-instruction cycle info and summary stats
- `log/sim_wave.vcd` — full waveform (GTKWave) for RTL debugging
- `log/popcount_test.txt` — popcount test results (pass/fail per value)

## Historical direction (2026-09-03) — writeback serialization — ✅ RESOLVED by v1.5_lucky (see section at end)

### Problem (2026-09-02 original → 2026-09-03 global +1 fixed, see bug 7)

`.insn` (popcount) itself is 42 cycles ✓, but **the single instruction right after it is slowed by ~28 cycles**:

- Evidence: in `log/C_v2_popcount_v15fixed.txt` (fixed v1.5), the `not` (0x13c) right after `.insn` (0x138) is **64 cycles**, while a `not` after an ordinary `and` (0x130) is **36 cycles**. **Only the instruction immediately after `.insn`** is affected (20 total, all `not`/`add`); the other 8341 ordinary instructions are cycle-identical to v1 RTL.
- In the A/B measurements (original/BNE, no popcount) every `not` is 36.
- Cause: the popcount writeback window `custom_wr_active` (36 cycles) kept draining after the instruction itself ended (out-of-band writeback); the next instruction's RF read was deferred by `rf_rreq_pending` (now only during `custom_wr_drain`) until the writeback cleared → 36 + ~28 writeback wait = 64.

### Goal

Make the popcount writeback **truly overlap** the execution of the following instruction and recover the ~28 cycles. `.insn` effective cost is currently ≈ 42 + 28 = ~70; after overlap it should return to ~42. The fixed version's total is 493488 ≈ v1 RTL's 493448 (difference 40 = 20×(.insn saves 26 − follower pays 28)); popcount is fast but the writeback serialization cancels it out.

### Difficulties (pitfalls hit before)

- Earlier attempt "don't defer the RF read" (remove serialization) → the writeback was reset mid-write by the next instruction's read (`rcnt` reset), **corrupting the result** (e.g. `0x4AC8`).
- So `rf_rreq_pending` cannot simply be deleted; finer read/write coordination of the RF is needed.

### Candidate ideas (unverified at the time)

1. **Decouple RF read/write**: give `serv_rf_ram_if` independent counters/timing for read and write so a read can start during a writeback without resetting the writeback's `rcnt` alignment. Change in `serv/rtl/serv_rf_ram_if.v`.
2. **Decouple writeback data from `o_rd`**: already done (`o_wdata0 = custom_wr_active ? cus_serial : rf_wdata0`). If read/write can be decoupled, the next instruction's ALU activity on `o_rd` no longer pollutes the writeback.
3. **Shorten the writeback window**: `custom_wr_active` is currently 36 cycles (covering the whole 32-bit serial RF write). Could we write only the low words in the 6 count bits and force the high bits to zero, shortening the window? Requires changes to `serv_top.v`'s `o_wen0`/`o_wreg0`/`o_wdata0` logic + `serv_rf_ram_if.v`.

### Verification method

- Reproduce: `./serv_project/run_sim.sh --serv-dir=fusesoc_libraries/serv_v1.5_rtl` (popcount version) with v2 firmware; check in `log/compare_result.txt` whether the instruction after `.insn` is still ~63.
- Goal: after the fix the next instruction returns to ~36-40 and the popcount result stays correct (the `C` measurement's total cycles should drop noticeably).

### Related measurement archives

- `log/A_v1_origin.txt` — v1 on original SERV, Total cycles 526208
- `log/D_v1_fixed15.txt` — v1 on v1.5_fixed, Total cycles 526208 (9013 lines with **0 diff** vs A row-by-row → the pure RV32I path is exactly identical to the original; regression evidence for the fix's correctness)
- `log/B_v1_bne.txt` — v1 on BNE, Total cycles 493157
- `log/C_v2_popcount_v1rtl.txt` — **official C measurement**: v2 on v1 RTL (`serv_rtl_v1`, 68-cycle .insn), Total cycles 493448 ← use this one
- `log/C_v2_popcount_v15fixed.txt` — v2 on fixed v1.5 (`custom_wr_drain` fix), .insn 42, Total cycles 493488 (global +1 removed; only the 20 followers pay the writeback serialization)
- `log/C_v2_popcount.txt` — **void** (measurement polluted by the v1.5 writeback bug), v2 on v1.5, 499281, for reference only

> Note: v1 RTL has `.insn` at 68 cycles (v1.5 at 42) but a slightly LOWER total (493448 < 493488), because v1 has **no** v1.5 writeback serialization (followers are not slowed by ~28 cycles). The v1.5 writeback serialization cost is real and was the target of the next optimization — now resolved by v1.5_lucky.

## v1.5_lucky — In-window writeback (2026-09-03, ✅ done, tag `v1.5_lucky`)

### What was achieved (on top of v1.5_fixed `fe99b81`)
- **Goal 1 (follower stall) and Goal 2 (rd garbage) solved together**: `.insn` stays at 42 cycles, rd is clean across all 32 bits, and the following instruction has zero stall.
- Core design: moved the popcount writeback from the "out-of-band 36-cycle window after the instruction" to "completed inside the instruction's own window" (only `serv/rtl/serv_top.v` changed; net −2 flip-flops):
  1. **stage1 (init=1, 32 cycles)**: `o_wdata0` is driven to 0 and `o_wen0` forced to 1; zeros are streamed into all of rd through the normal serial write port. LSB-first; each word is first read into `rdata0` (~rcnt 2j+1) before its zero-write commits (~rcnt 4+2j) → **rd==rs1 safe** (same mechanism as ordinary ALU rd==rs1).
  2. At the stage1→2 boundary the retained `o_rf_wreq` resets rcnt → **stage2 (init=0, 6 cycles)** re-aligns and writes the 6-bit count (`cus_serial`) into word0..2.
  3. `custom_win` (1 flop): set on `is_customized & cnt_en & init`, cleared on `is_customized & !init & cnt_done`; while set `o_wen0=1`, `o_wreg0=rf_wreg0` (immdec holds rd for the whole instruction, so the `custom_rd` latch is deleted); the RF write port is released right after stage 2's last beat.
  4. Deleted `custom_wr_active`/`wr_timer`/`custom_rd`. `serv_state.v`/`serv_rf_ram_if.v` untouched (`wr_busy_cnt=6` + `custom_wr_drain` kept; wreq is used only for the rcnt re-align and no longer blocks anything now that there is no out-of-band write).

### Verification
- build_codes (single `.insn`@0x6c, `popcnt x15,x15` of 0x0fffffff → 28): `.insn`=42; follower `sw`=70 (was 98); VCD reconstruction of x15=**0x0000001C** (all 16 words written, upper 26 bits zero); instruction count 1647 exactly matching v1 RTL; total 91094 = v1(91120) − 26.
- **v2 (random_forest, 10 samples, 20 `.insn` executions)**: Total cycles **492928** = v1 RTL `C_v2_popcount_v1rtl.txt` (493448) − 20×26; row-by-row comparison over 8381 rows shows **0 differences** except the 20 `.insn` rows (68→42), including all followers back at 36.
- Archives: `log/C_v2_popcount_v15lucky.txt` (compare_result), `log/C_v2_simlog_v15lucky.txt`, `log/C_v2_tracedump_v15lucky.txt`.
- v2 firmware build dir: `Codespace/SERV_codespace/rf_v2_lucky/` (C/H sources from random_forest/modified_scripts + startup.S/main.c from base random_forest; note the modified main.c has a leftover `stdio.h` include and cannot be compiled as-is).

## Unified Merge RTL Design (`serv_rtl_merge`) — ✅ COMPLETED & VERIFIED

### 1. Architecture & Design Implementation
The two optimization branches were successfully merged into a dedicated standalone RTL directory (`serv_project/fusesoc_libraries/serv_rtl_merge/`), preserving the original RTL directories intact:

| Module | Modifications for Unified Core |
|---|---|
| `rtl/serv_bne_early.v` | Brought in from `serv_bne` (47 lines). Evaluates branch mismatch condition and asserts `o_branch_early_done` with a 1-bit register (`early_exit_r`) to break combinational paths. |
| `rtl/serv_alu.v` | Added combinational mismatch output: `assign o_mismatch_now = a ^ b;` (0 flip-flops added). |
| `rtl/serv_bufreg.v` | Added `i_parallel_we` and `i_parallel_data[31:0]` for single-cycle parallel branch target offset pre-loading. |
| `rtl/serv_state.v` | Added `i_branch_early_done` port and single-pulse latch `early_done_r`. Harmonized counter jump: branch early-exit jumps counter to `{7, 1000}` (count 31), while popcount stage-2 completion clears counter to `{0, 0000}`. Early-fetch and `init_done` logic operate smoothly without conflict. |
| `rtl/serv_top.v` | Instantiates `serv_bne_early`, captures 32-bit `branch_offset_par` during instruction decode, connects parallel branch write port, and preserves `v1.5_lucky`'s in-window writeback (`custom_win`). |
| `servile/servile.v` | Preserved real datapath wiring of `i_rf_wr_busy`. |

### 2. Comprehensive Verification on Random Forest (10 Samples)
Firmware: `rf_v2_lucky` (8,381 instructions executed, containing 20 hardware popcount invocations and thousands of conditional branches):

| Design Variant | Total Instructions | Total Cycles | Average CPI | Cycles Saved vs. Origin | Cycles Saved vs. v1.5_lucky |
|---|:---:|:---:|:---:|:---:|:---:|
| **Original SERV (`serv_rtl_origin`)** | 8,381 | 526,208 | 62.8 | Baseline (0) | - |
| **BNE Early-Exit (`serv_bne`)** | 8,381 | 493,157 | 58.8 | -33,051 (-6.3%) | - |
| **Popcount v1.5 (`serv_v1.5_rtl`)** | 8,381 | 492,928 | 58.8 | -33,280 (-6.3%) | Baseline (0) |
| **🌟 Unified Merge (`serv_rtl_merge`)** | **8,381** | **464,213** | **55.4** | **-61,995 (-11.8%)** | **-28,715 (-5.8%)** |

#### Key Verification Insights:
- **Cumulative Speedup**: Both optimizations work in complete synergy. The merged core captures all 33,280 cycles saved by popcount, plus 28,715 cycles saved by branch early-exit, totaling **61,995 saved cycles (-11.8%)**.
- **Execution Path Consistency**: Row-by-row trace comparison over all 8,381 instructions confirms **0 path mismatches** (100% functional match).
- **Cycle Cost Distribution**:
  - Popcount (`.insn`): 20/20 run at exactly **42 cycles**.
  - Follower (`not`): 20/20 run at baseline **36 cycles** (zero stall).
  - Branch instructions: Exactly 1,009 branch executions (`beq`, `bne`, `bnez`, `beqz`) were accelerated by early exit.
- **Log Archives**: Full comparison results saved in `log/E_v2_rf_merge_result.txt`, `log/E_v2_rf_merge_simlog.txt`, and `log/E_v2_rf_merge_tracedump.txt`.

## PicoRV32 Baseline Simulation & Cycle Measurement

### 1. Overview & Purpose
PicoRV32 is an industry-standard, size-optimized 32-bit RISC-V CPU core implementing the RV32I / RV32IC instruction set with a multi-cycle datapath (average CPI of ~3.0–4.0).

In this project, PicoRV32 serves as an **external comparative baseline** alongside SERV:
- **SERV**: 1-bit serial CPU prioritizing minimal silicon area (~2.1k LUTs), executing RV32I instructions in ~32–68 clock cycles each.
- **PicoRV32**: Full 32-bit multi-cycle CPU providing standard performance, finishing instructions in 3–4 clock cycles.

Benchmarking identical firmware on both cores allows quantifying the exact cycle performance penalty incurred by bit-serial execution versus the silicon area saved, as well as evaluating the performance impact of software algorithms (e.g., software popcount in decision forest models).

### 2. Hardware Architecture & Simulation Setup
The PicoRV32 simulation infrastructure is located in `serv_project/fusesoc_libraries/picorv32/`:
- **Model generation**: Generated via FuseSoC (`picorv32_0-r1/test-verilator`) into C++ simulation binary `build/picorv32_0-r1/test-verilator/Vpicorv32_wrapper`.
- **Memory Map (128 KB RAM)**:
  - `0x00000000 – 0x00017FFF` (96 KB): Reserved for program code (`.text`), read-only constants (`.rodata`), initialized data (`.data`), and zero-initialized BSS (`.bss`).
  - `0x00018000 – 0x0001FFFF` (32 KB): Dedicated stack space. Initial stack pointer `sp` is set to `0x00020000` in `startup_pico.S` and grows downwards.
  - `0x10000000`: MMIO console character output port. `asm_uart_putchar` writes 1 byte here; `testbench.v` outputs the character to console via `$write("%c", latched_wdata)`.
  - `0x20000000`: MMIO test status register. Writing magic token `123456789` (`0x075BCD15`) asserts internal flag `tests_passed = 1`.
  - **Memory Protection**: The Verilog testbench asserts strict boundary checks. Any read or write access to an address $\ge \text{0x00020000}$ (except the two MMIO ports) immediately aborts simulation with `OUT-OF-BOUNDS MEMORY READ/WRITE FROM <addr>` and `$finish`.

### 3. Cycle Measurement Principle & Trap Halt Mechanism
In SERV, simulation termination is handled via an MMIO write to `0x90000000` (HALT). In PicoRV32, execution termination and cycle accounting are controlled via the **hardware `trap` signal**:

1. **Cycle Counter**:
   In `testbench.v`, a dedicated 32-bit hardware register `cycle_counter` increments on every clock cycle:
   ```verilog
   always @(posedge clk) begin
       cycle_counter <= cycle_counter + 1;
   end
   ```
2. **Execution & Halt Lifecycle (`firmware/startup_pico.S`)**:
   - `_start` sets `sp = 0x00020000`.
   - Zero-initializes the BSS segment (`_sbss` to `_ebss`).
   - Calls `main()`.
   - After `main()` returns, writes success token `123456789` to MMIO `0x20000000`.
   - Executes `ebreak`. In PicoRV32, `ebreak` triggers a trap exception and asserts the external CPU `trap` line.
3. **Trap Detection & Reporting**:
   On clock edge, `testbench.v` monitors the `trap` line:
   ```verilog
   if (resetn && trap) begin
       $display("TRAP after %1d clock cycles", cycle_counter);
       if (tests_passed) begin
           $display("ALL TESTS PASSED.");
           $finish;
       end else begin
           $display("ERROR!");
           ...
       end
   end
   ```
4. **Automated Parsing**:
   `run_sim.sh` executes the binary with `+firmware=firmware.hex +noerror`, captures the testbench output, extracts `TRAP after <cycles>` via regex, and prints the formatted cycle summary.

### 4. Critical Bug Analysis & Resolution: Linker Section Alignment
During the initial port of `random_forest`, the simulation failed with:
```text
OUT-OF-BOUNDS MEMORY READ FROM e90d193c
- src/picorv32_0-r1/testbench.v:393: Verilog $finish
```

#### Root Cause Investigation
1. **Linker wildcard leak**: The original `sections.lds` used `*(*);` to aggregate all sections into `.memory`. This included the ELF `.comment` section containing the GCC compiler metadata string `"GCC: (14.2.0+19)"` immediately after the `.rodata` section.
2. **Decision forest traversal**: In `Codespace/SERV_codespace/random_forest/RF_model.c`, the `trees` array contains 160 rows (10 trees with delimiters). In `infer_one.c`, the outer loop traverses through each tree. After leaf evaluation in tree 9 (the 10th tree), the loop skips the `{0, 0, 0, 0}` delimiter and inspects row 160 (`trees[160]`).
3. **Corrupted node interpretation**: Because `"GCC: (14.2.0+19)"` was placed at row 160, `trees[160][0]` read ASCII characters `0x3a434347` (977,486,663) as `feature`. `infer_one()` then attempted to index `x[feature]`, calculating byte address `x + (0x3a434347 << 2) = 0xe90d193c`.
4. **Why SERV succeeded**: In SERV's memory map, unallocated RAM beyond the binary is initialized to zero in simulation. `trees[160]` read four zero words, safely exiting the while loop. In PicoRV32, the `.comment` string was non-zero and caused an access exceeding the 128 KB memory limit.

#### Linker & Startup Fixes
- **`firmware/sections.lds`**:
  - Explicitly discard non-allocatable compiler metadata:
    ```lds
    /DISCARD/ : {
        *(.comment)
        *(.comment.*)
        *(.note*)
        *(.riscv.attributes)
        *(.eh_frame*)
    }
    ```
  - Added 16-byte zero padding after `.rodata` to guarantee clean array termination:
    ```lds
    *(.rodata .rodata.*);
    . = ALIGN(16);
    LONG(0); LONG(0); LONG(0); LONG(0);
    ```
  - Defined explicit boundaries `_sbss` and `_ebss` for BSS.
- **`firmware/startup_pico.S`**:
  - Added explicit BSS clearing loop before calling `main()`:
    ```assembly
        la   t0, _sbss
        la   t1, _ebss
        bgeu t0, t1, 2f
    1:  sw   zero, 0(t0)
        addi t0, t0, 4
        bltu t0, t1, 1b
    2:
    ```
- **`showtrace.py`**: Updated objdump selection to prioritize `tools/riscv64/usr/bin/riscv64-unknown-elf-objdump`.

### 5. Script Reference & Usage Guide
The PicoRV32 scripts are located in `serv_project/fusesoc_libraries/picorv32/` and mirror the user interface of SERV's scripts:

#### Compilation (`build.sh`)
```bash
./build.sh --build                               # Build default firmware (firmware/)
./build.sh --folder=random_forest --build        # Build from Codespace/SERV_codespace/random_forest
./build.sh --folder=/path/to/code --build        # Build from arbitrary directory
./build.sh --folder=random_forest --build --run  # Build and immediately run simulation
./build.sh --clear                               # Clean firmware artifacts (.elf, .bin, .hex, .dump)
```
- Automatically excludes any SERV-specific `startup.S` and binds `firmware/startup_pico.S`.
- Compiles with `-march=rv32ic -mabi=ilp32 -O2 -static -nostdlib -nostartfiles -ffreestanding`.
- Converts ELF to raw binary, pads to 4-byte boundaries, and generates 32,768-word (128 KB) `firmware.hex` via `makehex.py`.
- Generates symbol-resolved disassembly dump `firmware.dump`.

#### Simulation (`run_sim.sh`)
```bash
./run_sim.sh                              # Run simulation using firmware.hex
./run_sim.sh --run                        # Run without rebuilding Verilator model
./run_sim.sh --build                      # Build Verilator model only (Vpicorv32_wrapper)
./run_sim.sh --clean                      # Clean build/ directory
./run_sim.sh --clear                      # Clean logs and trace files
./run_sim.sh --trace                      # Enable +trace +vcd and decode testbench.trace
./run_sim.sh --firmware=custom.hex        # Use custom hex image
```
- Runs with `+firmware=firmware.hex +noerror`.
- When `--trace` is specified, generates `testbench.vcd` (GTKWave) and decodes `testbench.trace` via `showtrace.py` into `log/pico_trace.txt`.

### 6. Benchmark Results & Architecture Comparison
Running the pure software `random_forest` benchmark (10 input samples, 10 decision trees, software popcount loop, no custom instructions):

| Metric | PicoRV32 | SERV (v1.5 / v1 RTL) | Comparison / Notes |
|---|---|---|---|
| **Architecture** | 32-bit Multi-Cycle | 1-bit Bit-Serial | Parallel ALU vs. Serial ALU |
| **ISA** | RV32IC | RV32I | Compressed instructions supported |
| **Binary Size** | 3,152 bytes | 3,252 bytes | RV32C saves ~3.1% code size |
| **Average CPI** | ~3.5 cycles/insn | ~54.7 cycles/insn | Multi-cycle vs. 32-bit shift window |
| **Total Cycles (10 samples)** | **39,901 cycles** | **493,488 cycles** | **PicoRV32 is 12.37× faster in cycles** |
| **Classification Output** | `[2, 2, 1, 2, 2, 2, 2, 0, 0, 1]` | `[2, 2, 1, 2, 2, 2, 2, 0, 0, 1]` | Exact 100% match with `predicted_class.txt` |

This comparison highlights that SERV sacrifices ~12.4× cycle throughput in exchange for an ultra-compact footprint (~2,100 LUTs on FPGA), whereas PicoRV32 provides high cycle efficiency at the cost of wider datapaths and register multiplexers.

## Appendix — scripts, environment & toolchain reference (moved out of README)

> `README.md` is the short public-facing doc for readers (e.g. the teacher). This
> appendix keeps the detailed per-script reference that was removed from it.

### Environment & first-time setup
- `source Codespace/env.sh` adds the in-repo RISC-V toolchain to PATH
  (`tools/riscv64/usr/bin`, prefix `riscv64-unknown-elf-`).
- `./setup.sh` (repo root): `git submodule update --init --recursive`, then verifies
  that the working RTL dirs under `serv_project/fusesoc_libraries/` are non-empty.
  Note: that whole directory is git-ignored **except** the four SERV variants, which
  are committed directly (`serv_v1.5_rtl`, `serv_bne`, `serv_rtl_origin`,
  `serv_rtl_v1`). The upstream clones `fusesoc_cores/ mdu/ picorv32/` stay ignored.
- Toolchain requirements:
  | Tool | Used by |
  |---|---|
  | `riscv64-unknown-elf-gcc/objcopy/objdump` | build.sh (compile/link/hex), trace_dump.py (symbols) |
  | `verilator` (>=5) | run_sim.sh Verilator compile |
  | `g++` | run_sim.sh testbench compile |
  | `fusesoc` | build.sh `--run` path only (optional; primary sim is run_sim.sh) |
  | `python3` | makehex.py, trace_dump.py, compare_traces.py |
  | `gtkwave` (optional) | viewing log/sim_wave.vcd |

### Pipeline
```
build.sh  (.c/.S, -march=rv32i, freestanding)  ->  firmware.hex
run_sim.sh (clean -> verilator+g++ -> Vservant_sim)  ->  sim_log.txt + sim_wave.vcd + trace.bin
trace_dump.py + compare_traces.py  ->  log/trace_dump.txt + log/compare_result.txt
```
RTL variant is selected with `--serv-dir=<dir>` on both build.sh and run_sim.sh
(default `fusesoc_libraries/serv_v1.5_rtl`). `run_sim.sh` compiles the variant's
own file list and adds conditional sources: `serv_customized_{alu,state}.v`
(v1/v1.5 popcount) or `serv_bne_early.v` (bne).

### scripts reference
- `scripts/sim_main.cpp` — self-written Verilator testbench. Toggles wb_clk, applies
  active-high reset, monitors `pc_vld`/`pc_adr` each rising edge and logs
  `last_pc -> current_pc : N cycles` to `log/sim_log.txt`. Enabled with
  `+vcd=1` (writes log/sim_wave.vcd) and `+trace_pc=1` (writes
  build/…/verilator_tb/trace.bin). Simulation ends on the SoC halt (program writes
  `0x90000000`) or after 10M cycles. Does NOT capture UART.
- `scripts/trace_dump.py` — trace.bin (32-bit PCs) -> symbol-resolved
  `log/trace_dump.txt`; also regenerates `firmware.dump` (objdump `-M no-aliases,numeric`).
- `scripts/compare_traces.py` — merges sim_log.txt (cycle costs) with trace_dump.txt
  (mnemonics) into `log/compare_result.txt`; merges two-part instructions (sw/lbu …)
  and prints summary stats + per-instruction averages.
- `scripts/cycle_cost.sh <start> <end>` — cycle cost between two PCs from
  compare_result.txt (bare hex, `0x…`, or full-width accepted); writes
  `log/cycle_cost_<s>_<e>.txt`.
- `scripts/asm_sweep.sh` — O0–O3/Os sweep over input values, diffs vs a baseline.
- `scripts/instr_counter.sh` — counts instruction mnemonics in firmware.elf
  (whole or between two labels); output `log/instr_count.log`.
- `serv_project/sim_wave.sh` — build+simulate then open the VCD in GTKWave.
- `scripts/run_popcount_test.sh` / `scripts/reproduce_range_popcount.sh` — popcount
  correctness helpers (default SERV_DIR `fusesoc_libraries/serv_v1.5_rtl`).

### Program layout & termination conventions (teacher-facing)
- Program folders live under `Codespace/SERV_codespace/`; each needs a `startup.S`
  (template: `Codespace/SERV_codespace/build_codes/startup.S`), which sets
  `sp = 8192`, raises the GPIO, calls `main()`, then on return writes `0x90000000`
  (HALT) and loops — the SoC stops the simulation on that write.
- Firmware flags: `-march=rv32i -mabi=ilp32 -O2 -static -nostdlib -nostartfiles
  -ffreestanding`. Assembly files are linked before C so `_start` is at 0.
- Custom popcount is invoked from C via a **locally scoped** `cpop` — see the
  "★ Current cpop route" section at the top for the full rationale:
  ```c
  volatile static unsigned int popcnt_custom(unsigned int val) {
      unsigned int rd;
      asm volatile(".option push\n"
                   ".option arch, +zbb\n"
                   "cpop %0, %1\n"
                   ".option pop\n"
                   : "=r"(rd) : "r"(val));
      return rd;
  }
  ```
  Requires an RTL variant that recognises the **official** `cpop` encoding
  (`serv_rtl_merge` since `dac74f9`). The old private encoding
  `.insn r 0x2B, 0, 0` is **no longer recognised** — using it now yields
  whatever the decoder makes of opcode `01010`, silently.
