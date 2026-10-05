# SERV RISC-V Simulation & Cycle-Cost Project

Compile RISC-V firmware, run it on a Verilator simulation of the SERV SoC, and get a
per-instruction cycle-cost report. Five SERV RTL variants are provided so the same
program can be compared across different CPU designs.

---

## 1. Five SERV RTL Variants

All variants live under `serv_project/fusesoc_libraries/` and share the same firmware
build & simulation flow. Pick one with `--serv-dir` (default: `serv_v1.5_rtl`).

| Directory | Description |
|---|---|
| `serv_rtl_origin` | Original upstream SERV, unmodified. |
| `serv_rtl_v1` | SERV + a custom **popcount** instruction (32-bit input, `rs1`), 68 cycles per execution. |
| `serv_v1.5_rtl` | SERV + the custom popcount instruction (32-bit input, `rs1`), **42 cycles** per execution with in-window writeback (clean `rd`, no penalty on the next instruction). **Default.** |
| `serv_bne` | SERV with an early-exit optimization for conditional branches. |
| `serv_rtl_merge` | **Unified design** merging the **42-cycle popcount** and **branch early-exit** optimizations into a single core. Achieves cumulative speedups without state machine conflicts or redundant flip-flops. |

Plain RV32I programs run on all five variants. The custom popcount instruction is available
on `serv_rtl_v1`, `serv_v1.5_rtl`, and `serv_rtl_merge`.

---

## 2. Repository Layout

```
riscv_benchmark/
├── Codespace/
│   ├── env.sh                       Environment setup (toolchain PATH)
│   └── SERV_codespace/
│       └── build_codes/             Default firmware sources (startup.S + C code)
├── serv_project/
│   ├── build.sh                     Compile firmware → firmware.hex
│   ├── run_sim.sh                   Build Verilator model + simulate + post-process
│   ├── firmware.hex                 Latest compiled firmware image
│   ├── scripts/
│   │   ├── sim_main.cpp             Testbench (this project's own, see §5)
│   │   ├── trace_dump.py            trace.bin → symbol-resolved trace
│   │   └── compare_traces.py        Merge cycle costs + trace → report
│   ├── log/                         Simulation outputs & reports
│   └── fusesoc_libraries/           SERV RTL variants & PicoRV32 baseline
│       ├── serv_v1.5_rtl/           v1.5 popcount design (default)
│       ├── serv_bne/                BNE branch early-exit design
│       ├── serv_rtl_merge/          Unified design (popcount 42-cycle + branch early-exit)
│       ├── serv_rtl_origin/         Original upstream SERV
│       ├── serv_rtl_v1/             v1 popcount design
│       └── picorv32/                PicoRV32 multi-cycle baseline (see §7)
└── AGENTS.md                        Detailed internal notes, scripts & measurement guide
```

---

## 3. Toolchain & Environment

Run once per shell (adds the in-repo RISC-V toolchain to `PATH`):

```bash
cd riscv_benchmark
source Codespace/env.sh
```

Required tools:

| Tool | Used by |
|---|---|
| `riscv64-unknown-elf-gcc` / `objcopy` / `objdump` | firmware compile & disassembly (in-repo, under `tools/riscv64`) |
| `verilator` | Verilog → C++ simulation model |
| `g++` | testbench compilation (`run_sim.sh`) |
| `python3` | post-processing scripts |
| `gtkwave` *(optional)* | view `log/sim_wave.vcd` |

---

## 4. Workflow: Build → Simulate → Report

```bash
cd serv_project

# [1] Compile firmware (sources auto-discovered from a folder under
#     Codespace/SERV_codespace/, default: build_codes/)
./build.sh --build                       # → firmware.elf / .bin / .hex
./build.sh --folder=<NAME> --build       # build from Codespace/SERV_codespace/<NAME>/

# [2] Run the simulation on a SERV RTL variant (Verilator rebuild is automatic)
./run_sim.sh                             # default RTL: serv_v1.5_rtl
./run_sim.sh --serv-dir=fusesoc_libraries/serv_bne    # pick another variant
./run_sim.sh --firmware=my.hex           # run a different image

# [3] Read the per-instruction cycle report
cat log/compare_result.txt
```

Both `build.sh` and `run_sim.sh` accept `--serv-dir=<variant>` to select which RTL to
use (`build.sh` uses it for the linker script / hex converter; `run_sim.sh` uses it for
the RTL file list). Outputs from `run_sim.sh`:

| File | Contents |
|---|---|
| `log/sim_log.txt` | PC transitions with cycle cost per instruction |
| `log/trace_dump.txt` | Symbol-resolved PC trace |
| `log/compare_result.txt` | Merged per-instruction cycle report + summary stats |
| `log/sim_wave.vcd` | Full waveform (GTKWave) |

---

## 5. Testbench

The testbench is **written by this project**: `serv_project/scripts/sim_main.cpp`
(compiled into `Vservant_sim` by `run_sim.sh`). It toggles the clock, applies reset, then
on every rising edge watches the CPU's `pc_vld`/`pc_adr`. Each PC change means the
previous instruction finished, so the elapsed cycles are that instruction's cost:

```
0x0000006c -> 0x00000070 : 42 cycles      ← custom popcount (v1.5 RTL)
```

`run_sim.sh` runs the binary with `+vcd=1 +trace_pc=1`, producing the VCD waveform and
`trace.bin`, which `trace_dump.py` / `compare_traces.py` post-process into the report.
The testbench does **not** capture UART output.

---

## 6. Running Your Own Program

1. **Create a program folder** `Codespace/SERV_codespace/<NAME>/`.
2. **Copy `startup.S`** from `Codespace/SERV_codespace/build_codes/`. It initialises the
   stack, calls `main()`, and after `main` returns writes to address `0x90000000`
   (HALT) and loops — this is what ends the simulation.
3. **Add your code** (C or assembly). Firmware is compiled freestanding with
   `-march=rv32i -mabi=ilp32 -O2 -nostdlib` — no libc, no floating point.
4. **Build & run:**
   ```bash
   cd serv_project
   ./build.sh --folder=<NAME> --build
   ./run_sim.sh
   ```
5. **Check the result.** Instruction behaviour and cycle counts are in
   `log/compare_result.txt`. To inspect a computed value, store it to a fixed RAM
   address and look up that store in `log/sim_wave.vcd` (the UART is not captured).

### Using the custom popcount (only on `serv_rtl_v1` / `serv_v1.5_rtl`)

```c
volatile static unsigned int popcnt_custom(unsigned int val) {
    unsigned int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0"
                 : "=r"(rd) : "r"(val));
    return rd;
}
```

`popcnt_custom(x)` returns the number of set bits in the 32-bit value `x`.

---

## 7. PicoRV32 Baseline Simulation & Cycle Measurement

To benchmark SERV against an industry-standard 32-bit multi-cycle RISC-V core, this repository provides a dedicated build and simulation pipeline for **PicoRV32** under `serv_project/fusesoc_libraries/picorv32/`.

### Cycle Measurement Principle (Summary)

- **Execution Model**: PicoRV32 is a multi-cycle core with standard 32-bit datapath (CPI typically ~3–4), running alongside SERV's 1-bit serial architecture (~32–68 cycles/instruction).
- **Measurement & Halt Mechanism**:
  1. Firmware is compiled freestanding (`-march=rv32ic -mabi=ilp32 -O2`) with `firmware/startup_pico.S`.
  2. When execution finishes, `startup_pico.S` signals success by writing `123456789` to address `0x20000000`, then executes `ebreak`.
  3. The `ebreak` triggers the hardware `trap` signal.
  4. The Verilator testbench (`testbench.v`) continuously increments `cycle_counter` on every `posedge clk`. Upon detecting `trap`, it prints:
     ```text
     TRAP after <cycles> clock cycles
     ALL TESTS PASSED.
     ```
- **Quick Start**:
  ```bash
  cd serv_project/fusesoc_libraries/picorv32
  ./build.sh --folder=random_forest --build --run   # Compile and simulate
  ```

> 📖 **Comprehensive Documentation**:
> A complete architectural breakdown, memory layout (128KB RAM map, MMIO, BSS zeroing), linker script safeguards, trace decoding with `showtrace.py`, and detailed cycle benchmark comparisons against SERV are thoroughly documented in [**`AGENTS.md`**](file:///home/chenyoo/riscv_benchmark/AGENTS.md#picorv32-baseline-simulation--cycle-measurement).

---

## 8. Current Status & Next Plans

### Completed Milestones
1. **Custom Popcount Optimization (`v1.5_lucky`)**:
   - Custom 2-stage popcount instruction (`.insn`, 42 cycles) with in-window writeback.
   - Zero follower instruction stall (all followers run at baseline 36 cycles) and clean 32-bit `rd`.
2. **Unified RTL Merge (`serv_rtl_merge`)**:
   - Successfully merged **v1.5 popcount** and **BNE branch early-exit** into a unified core under `serv_project/fusesoc_libraries/serv_rtl_merge/`.
   - Verified on `random_forest` (10 samples): Total execution cycles dropped to **464,213 cycles** (-11.8% vs. original SERV 526,208; -5.8% vs. v1.5 492,928).
   - Execution path is 100% identical (0 mismatch), with 1,009 accelerated branches.
3. **PicoRV32 Comparative Baseline**:
   - Automated `build.sh` and `run_sim.sh` pipeline created and verified on `random_forest` (39,901 cycles).

### Next Plans & Future Work
1. **Broader Benchmark Suite Evaluation**:
   - Run and evaluate `serv_rtl_merge` and PicoRV32 across additional workloads: `BNN` (Binarized Neural Network), `Tsetlin_Machine`, and `dhrystone`.
2. **Branch Optimization Extensions**:
   - Explore extending early-exit optimizations beyond equality/inequality (`BEQ`/`BNE`) to magnitude comparisons (`BLT`, `BGE`, `BLTU`, `BGEU`).
3. **FPGA Synthesis & Silicon Resource Accounting**:
   - Run FPGA synthesis (e.g. Vivado / Yosys) on `serv_rtl_merge` to quantify the exact LUT/FF area overhead compared to original SERV and PicoRV32.

---

See [`AGENTS.md`](file:///home/chenyoo/riscv_benchmark/AGENTS.md) for detailed internal notes, RTL implementation details, and the full script reference.
