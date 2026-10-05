# DEPRECATED: rf_v2_lucky

This directory is deprecated and has been unified into:
`Codespace/SERV_codespace/random_forest/`

## Background & Unification

Previously, `rf_v2_lucky` was used to evaluate Random Forest using the custom popcount instruction (`.insn r 0x2B, 0, 0, %0, %1, x0`) on the SERV v1.5 RTL (`v1.5_lucky` in-window writeback optimization).

Requirement R2 unifies both software bit-manipulation and hardware popcount into `Codespace/SERV_codespace/random_forest/infer_one.c` via the preprocessor macro `USE_CUSTOM_POPCOUNT`.

## How to Build & Simulate

From `serv_project/`:

- **Standard Software Popcount (RV32I)**:
  ```bash
  ./build.sh --folder=random_forest --build
  ./run_sim.sh --run
  # Expected runtime: 526,208 cycles
  ```

- **Hardware Popcount (Custom Instruction)**:
  ```bash
  ./build.sh --folder=random_forest --popcount --build
  ./run_sim.sh --run
  # Expected runtime: 492,928 cycles
  ```

This directory is preserved solely for historical provenance and git tag `v1.5_lucky` continuity. All active benchmarking should target `Codespace/SERV_codespace/random_forest/`.
