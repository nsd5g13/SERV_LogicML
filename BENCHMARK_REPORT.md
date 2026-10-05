# SERV Machine Learning Benchmarks: Performance & Verification Report (Milestone 3 / R3)

**Author / Role**: `teamwork_preview_worker` (Milestone 3 Implementer / QA / Specialist)  
**Date**: 2026-09-13  
**Target Architecture**: SERV RISC-V Core (v1.5 RTL — 42-cycle in-window writeback custom popcount)  
**Repository Working Directory**: `/home/chenyoo/riscv_benchmark`  

---

## 1. Executive Summary

This report documents the empirical execution, cycle measurement, and architectural verification of three distinct Machine Learning workloads running on the SERV RISC-V processor:
1. **Random Forest (`random_forest`)** — Decision-tree classifier (10 inference samples, 10 trees, 4 features, 3 classes).
2. **Binarized Neural Network (`BNN`)** — Multi-layer neural network with sign activations and XNOR-popcount dot-products (1 inference sample, 16 hidden neurons, 3 output classes).
3. **Tsetlin Machine (`Tsetin_Machine`)** — Logic-based propositional pattern learning machine using packed clause evaluation (10 inference samples, 4 features, 10 clauses, 3 classes).

Each workload was evaluated across two operational modes on **SERV v1.5 RTL** (`fusesoc_libraries/serv_v1.5_rtl/`):
- **Software Baseline (SW)**: Pure RV32I bitwise manipulation loops to count set bits without custom hardware support.
- **Hardware Accelerated (HW Popcount)**: Hardware execution of the custom population count instruction (`.insn r 0x2B, 0, 0, rd, rs1, x0`) implemented in the SERV v1.5 ALU and state machine.

### Key Findings
- **100% Simulation Success**: All 6 benchmark configurations simulated to clean termination via Wishbone address `0x90000000` (`$finish`), exhibiting zero timeouts, hangs, or abnormal program resets.
- **Hardware Popcount Performance**: The custom instruction executed in strictly **42.0 cycles** across all invocations (Min: 42, Max: 42) with zero stall overhead on subsequent instructions and complete bit cleanliness on `rd`.
- **System-Level Speedup**: Custom hardware popcount provided tangible total-execution speedups across all three models:
  - **Random Forest**: **+6.32%** speedup (33,280 cycles saved).
  - **BNN**: **+6.35%** speedup (4,330 cycles saved).
  - **Tsetlin Machine**: **+8.72%** speedup (28,896 cycles saved).

---

## 2. Summary Table: Benchmark Execution Metrics & Speedup

Cycle counts and instruction counts are extracted directly from the post-processed execution traces (`compare_result.txt` logs). Speedup percentage is calculated as:
$$\text{Speedup (\%)} = \frac{\text{Cycles}_{\text{SW}} - \text{Cycles}_{\text{HW}}}{\text{Cycles}_{\text{SW}}} \times 100\%$$

| Benchmark Workload | Dataset / Inference Scope | Execution Mode | Total Instructions | Total Cycles | Avg Cycles / Instr | Custom `.insn` Invocations | `.insn` Avg Cycles | Cycle Reduction (Cycles Saved) | Overall Speedup (%) |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Random Forest** | 10 samples (4 feats, 10 trees) | **Software (SW)** | 9,013 | **526,208** | 58.4 | 0 | — | — | *Baseline* |
| **Random Forest** | 10 samples (4 feats, 10 trees) | **HW Popcount** | 8,381 | **492,928** | 58.8 | 20 | 42.0 | 33,280 | **+6.32%** |
| **BNN** | 1 sample (16 hid, 3 out) | **Software (SW)** | 1,327 | **68,206** | 51.4 | 0 | — | — | *Baseline* |
| **BNN** | 1 sample (16 hid, 3 out) | **HW Popcount** | 1,232 | **63,876** | 51.8 | 3 | 42.0 | 4,330 | **+6.35%** |
| **Tsetlin Machine** | 10 samples (10 clauses, 3 cls) | **Software (SW)** | 6,089 | **331,434** | 54.4 | 0 | — | — | *Baseline* |
| **Tsetlin Machine** | 10 samples (10 clauses, 3 cls) | **HW Popcount** | 5,495 | **302,538** | 55.1 | 60 | 42.0 | 28,896 | **+8.72%** |

---

## 3. Detailed Breakdown per Benchmark

### 3.1 Random Forest (`random_forest`)

#### Algorithmic Context & Popcount Call Sites
In Random Forest inference, decision trees evaluate threshold splits (`x[fidx] < split`) along branch nodes until a leaf node is reached. Each tree casts a class vote (0, 1, or 2), which is bit-packed into a 2-bit field within a 32-bit accumulator integer (`packed_votes`):
- `00` = Class 0
- `01` = Class 1
- `10` = Class 2

To determine majority vote across all 10 trees:
```c
unsigned int lo = packed_votes & 0x55555555;         // Low bit of each 2-bit field
unsigned int hi = (packed_votes >> 1) & 0x55555555;  // High bit of each 2-bit field

unsigned int count1 = popcnt(lo & ~hi);              // Count fields equal to 01
unsigned int count2 = popcnt(hi & ~lo);              // Count fields equal to 10
unsigned int count0 = (unsigned int)vote_count - count1 - count2;
```
For 10 samples evaluated sequentially, `popcnt` is called exactly 2 times per sample, yielding **20 popcount calls**.

#### Execution Comparison
- **Software Mode (`log/rf_sw_compare.txt`)**:
  - Implemented as a bit-serial shift loop: `while (val) { c += val & 1; val >>= 1; }`.
  - Loop overhead introduces 632 additional instructions across the run (9,013 vs 8,381).
  - Total Cycles: **526,208 cycles**.
- **Hardware Popcount Mode (`log/rf_hw_compare.txt`)**:
  - Replaces software loop with inline assembly: `asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0" : "=r"(rd) : "r"(val));`.
  - Disassembly confirms `.insn 4, 0x0007072b` and `.insn 4, 0x000787ab` emitted.
  - Trace confirms exactly 20 executions of `.insn` at 42 cycles each.
  - Total Cycles: **492,928 cycles**.
  - Cycle Savings: $526,208 - 492,928 = 33,280$ cycles (**+6.32%** reduction).

---

### 3.2 Binarized Neural Network (`BNN`)

#### Algorithmic Context & Popcount Call Sites
The BNN computes neuron activations using binarized weights ($w \in \{-1, +1\}$) and binarized activations ($x \in \{-1, +1\}$). Under 1-bit boolean mapping ($0 \rightarrow -1, 1 \rightarrow +1$), the inner dot product simplifies to bitwise XNOR ($\sim(x \oplus w)$) followed by counting the number of matching bits:
$$\text{DotProduct}(x, w) = 2 \times \text{popcount}(\sim(x \oplus w)) - N$$

In Layer 1 of the BNN (`layer1_uint32.c` and `helpers.c`):
```c
int popcount32(int32_t x) {
#ifdef USE_CUSTOM_POPCOUNT
    int rd;
    asm volatile(".insn r 0x2B, 0, 0, %0, %1, x0" : "=r"(rd) : "r"(x));
    return rd;
#else
    int count = 0;
    uint32_t v = (uint32_t)x;
    while (v) { v &= v - 1; count++; }
    return count;
#endif
}
```
Layer 1 has 3 output neurons evaluating packed activations for 1 sample, invoking `popcount32` **3 times**.

#### Execution Comparison
- **Software Mode (`log/bnn_sw_compare.txt`)**:
  - Implemented via Kernighan's bit-clearing loop: `v &= v - 1`.
  - Total Instructions: 1,327.
  - Total Cycles: **68,206 cycles**.
- **Hardware Popcount Mode (`log/bnn_hw_compare.txt`)**:
  - Emits `.insn r 0x2B, 0, 0` for output neuron activations.
  - Total Instructions: 1,232 (95 instructions eliminated).
  - Trace confirms exactly 3 executions of `.insn` at 42 cycles each.
  - Total Cycles: **63,876 cycles**.
  - Cycle Savings: $68,206 - 63,876 = 4,330$ cycles (**+6.35%** reduction).

---

### 3.3 Tsetlin Machine (`Tsetin_Machine`)

#### Algorithmic Context & Popcount Call Sites
A Tsetlin Machine represents knowledge via propositional logic clauses. Input features are booleanized into positive and negated literals. Clause outputs (True=1, False=0) are packed into a 32-bit unsigned integer (`packed_clause_output`), with 1 bit allocated per clause (3 classes $\times$ 10 clauses = 30 bits total).

Class scoring in `class_sum.c` computes the difference between positive and negative clause votes:
```c
for (int c = 0; c < CLASSES; c++) {
    int base = c * CLAUSES;
    int half = CLAUSES / 2;
    unsigned int pos_mask = ((1u << half) - 1u) << base;
    unsigned int neg_mask = ((1u << half) - 1u) << (base + half);

    int sum = (int)popcnt(packed & pos_mask) - (int)popcnt(packed & neg_mask);
    ...
}
```
For 3 classes per sample and 10 samples evaluated, `popcnt` is invoked:
$$3 \text{ classes} \times 2 \text{ calls/class} \times 10 \text{ samples} = \mathbf{60\text{ popcount invocations}}$$

#### Execution Comparison
- **Software Mode (`log/tm_sw_compare.txt`)**:
  - Uses software bit-clearing: `while (val) { val &= val - 1; n++; }`.
  - Total Instructions: 6,089.
  - Total Cycles: **331,434 cycles**.
- **Hardware Popcount Mode (`log/tm_hw_compare.txt`)**:
  - Emits `.insn r 0x2B, 0, 0` for all positive and negative clause evaluation masks.
  - Total Instructions: 5,495 (594 instructions eliminated).
  - Trace confirms exactly 60 executions of `.insn` at 42 cycles each.
  - Total Cycles: **302,538 cycles**.
  - Cycle Savings: $331,434 - 302,538 = 28,896$ cycles (**+8.72%** reduction).

---

## 4. Hardware Verification & SERV v1.5 RTL Popcount Characteristics

### 4.1 In-Window Writeback Architecture
SERV v1.5 RTL (`fusesoc_libraries/serv_v1.5_rtl/`) integrates an in-window writeback datapath that eliminates the historical follower stall bug:
1. **Stage 1 (`init=1`, 32 cycles)**: The custom ALU (`serv_customized_alu.v`) counts set bits of `rs1` into 6-bit accumulator `pr_partial[5:0]`. Concurrently, `o_wdata0` is driven to `0` and `o_wen0` is asserted high, clearing all 32 bits of `rd` in the register file.
2. **Stage 2 (`init=0`, 6 cycles)**: `pr_partial` is shifted out LSB-first via `cus_serial` directly into `rd` (low 6 bits).
3. **Completion & Hand-off (4 cycles)**: `custom_stage2_done` triggers at cycle count 5, early-fetching the next instruction.
4. **Instruction Timing**:
   $$32\text{ (Stage 1)} + 6\text{ (Stage 2)} + 4\text{ (Early-fetch)} = \mathbf{42\text{ clock cycles}}$$

### 4.2 Instruction Cost Consistency Audit
Empirical cycle distributions for `.insn` across all three hardware runs:
- `random_forest`: 20 `.insn` instructions $\rightarrow$ Min: 42, Max: 42, Avg: 42.0.
- `BNN`: 3 `.insn` instructions $\rightarrow$ Min: 42, Max: 42, Avg: 42.0.
- `Tsetlin Machine`: 60 `.insn` instructions $\rightarrow$ Min: 42, Max: 42, Avg: 42.0.

In all 83 total hardware popcount executions across the test suite, not a single follower instruction experienced pipeline stalls (subsequent ALU instructions executed in their baseline 36-cycle latency).

---

## 5. Verification Evidence: Normal HALT (`0x90000000`)

In standard SERV bare-metal execution, the program terminates by executing the `halt` sequence in `startup.S`:
```assembly
halt:
    li   t0, 0x90000000
    sw   zero, 0(t0)
    j    halt
```
The Wishbone bus arbiter and multiplexer (`servile/servile_mux.v`) decode addresses matching `sim_halt_adr = 32'h90000000`:
```verilog
assign halt_en = i_wb_cpu_we & (i_wb_cpu_adr == sim_halt_adr);

always @(posedge i_clk) begin
   if (i_wb_cpu_stb & !sim_ack) begin
      if (halt_en) begin
         $display("Test complete");
         $finish;
      end
   end
end
```

### Verbatim Simulation Exit Logs
All 6 runs emitted `Test complete` followed by Verilog `$finish` at `servile_mux.v:87`:

1. **`random_forest` (Software)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```
2. **`random_forest` (Hardware Popcount)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```
3. **`BNN` (Software)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```
4. **`BNN` (Hardware Popcount)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```
5. **`Tsetin_Machine` (Software)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```
6. **`Tsetin_Machine` (Hardware Popcount)**:
   ```text
   Loading RAM from firmware.hex
   Test complete
   - fusesoc_libraries/serv_v1.5_rtl/servile/servile_mux.v:87: Verilog $finish
   ```

### Instruction Trace Termination Verification
The final instruction transition in all 6 trace dumps confirms return to `startup.S` followed by the store to `0x90000000`:
```text
  0x00000210  0x00000014  ret           68
  0x00000014  0x00000018  lui           36
```
Address `0x00000014` is the `lui t0, 0x90000` instruction in `startup.S`, and `0x00000018` is `sw zero, 0(t0)`, which immediately triggers the hardware simulation termination.

---

## 6. Archival Artifacts

All benchmark logs and traces generated during Milestone 3 execution are preserved in `/home/chenyoo/riscv_benchmark/serv_project/log/`:
- `log/rf_sw_compare.txt` — Random Forest pure software trace (9,013 instructions, 526,208 cycles).
- `log/rf_hw_compare.txt` — Random Forest custom popcount trace (8,381 instructions, 492,928 cycles).
- `log/bnn_sw_compare.txt` — BNN pure software trace (1,327 instructions, 68,206 cycles).
- `log/bnn_hw_compare.txt` — BNN custom popcount trace (1,232 instructions, 63,876 cycles).
- `log/tm_sw_compare.txt` — Tsetlin Machine pure software trace (6,089 instructions, 331,434 cycles).
- `log/tm_hw_compare.txt` — Tsetlin Machine custom popcount trace (5,495 instructions, 302,538 cycles).

---

## 7. Conclusion

Requirement R3 of the SERV ML Benchmarks project is completely satisfied:
1. All three ML benchmarks (`random_forest`, `BNN`, `Tsetin_Machine`) have been successfully compiled and simulated on SERV v1.5 RTL in both software bit-manipulation and custom hardware popcount modes.
2. All 6 runs terminate cleanly via `$finish` triggered by Wishbone store to `0x90000000` with zero hangs or timeouts.
3. The custom popcount instruction exhibits rock-solid 42-cycle execution latency with clean register writeback and zero follower overhead.
4. Total execution cycles demonstrate consistent performance speedups across all models, achieving up to an **8.72% speedup** in Tsetlin Machine and **6.32%–6.35% speedup** in Random Forest and BNN.
