# Original User Request

## Initial Request — 2026-09-13T00:06:29+01:00

# Teamwork Project: SERV Machine Learning Benchmarks Optimization & Unification

Benchmark and optimize three Machine Learning algorithms (Random Forest, BNN, Tsetlin Machine) on the SERV RISC-V processor under both software bit-manipulation and custom hardware popcount instruction execution.

Working directory: /home/chenyoo/riscv_benchmark

## Requirements

### R1. Build Script Macro & Startup Integration (`serv_project/build.sh`)
- Extend `serv_project/build.sh` to support a flag `--popcount` that injects `-DUSE_CUSTOM_POPCOUNT` into compilation flags (`CFLAGS`).
- Ensure graceful handling of test folders without local startup files: provide a fallback to standard SERV startup code (`Codespace/SERV_codespace/build_codes/startup.S`) when no assembly file (`.s`/`.S`) is present in the target directory.
- Maintain full backwards compatibility with existing options (`--folder=...`, `--build`, `--run`, `--serv-dir=...`).

### R2. C Code Macro Unification for Random Forest (`random_forest`)
- Merge `Codespace/SERV_codespace/random_forest` and `Codespace/SERV_codespace/rf_v2_lucky` into a single unified `random_forest` codebase.
- In `infer_one.c`, use `#ifdef USE_CUSTOM_POPCOUNT` to switch between custom instruction (`.insn r 0x2B, 0, 0`) and software popcount, matching the convention used in `BNN/helpers.c` and `Tsetin_Machine/class_sum.c`.
- Ensure startup assembly and header inclusions are clean and freestanding (no host `stdio.h` or undefined references).

### R3. Benchmark Execution & Cycle Count Measurement
- Run all three ML workloads on SERV v1.5 RTL (`fusesoc_libraries/serv_v1.5_rtl`) across both modes:
  1. `random_forest` (Software vs Custom Popcount)
  2. `BNN` (Software vs Custom Popcount)
  3. `Tsetin_Machine` (Software vs Custom Popcount)
- Record total simulation cycle count for each of the 6 runs from testbench termination.
- Produce a structured comparison summary report detailing cycles and speedup ratios.

## Acceptance Criteria

### Scripting & Build
- [ ] `./build.sh --folder=random_forest --build` compiles pure software binary (no `.insn`).
- [ ] `./build.sh --folder=random_forest --popcount --build` compiles hardware popcount binary containing `.insn r 0x2B, 0, 0`.
- [ ] `./build.sh --folder=BNN --build` and `./build.sh --folder=Tsetin_Machine --build` compile successfully without manual `startup.S` copying.

### Code Unification
- [ ] `random_forest/infer_one.c` unified with `#ifdef USE_CUSTOM_POPCOUNT`.
- [ ] Redundant `rf_v2_lucky` directory can be safely archived or deprecated.

### Benchmarking & Verification
- [ ] All 6 benchmark configurations simulate to normal HALT (`0x90000000`) without timeout or hang.
- [ ] Total simulation cycle counts recorded for:
  - RF SW vs RF HW Popcount
  - BNN SW vs BNN HW Popcount
  - TM SW vs TM HW Popcount
- [ ] A final Markdown summary table is generated with cycle numbers and HW speedup percentages.
