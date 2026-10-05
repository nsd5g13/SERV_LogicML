
# SERV — BNE / Conditional-Branch Early-Exit Optimisation

# SERV — BNE / Conditional-Branch Early-Exit Optimisation

This is a fork of [olofk/serv](https://github.com/olofk/serv) (the award-winning
bit-serial RISC-V core by Olof Kindgren) with an added early exit optimistation 
for BNE instructions.

## What it does

This modification allows stops a comparison the cycle that a mismatch is found, 
instead of running all 32 cycles. It uses a modified dataflow that loads the entire 
PC offset into the bufreg in one cycle, as this is usually done over 32 cycles at 
the same time as the comparison. The counter is then set to the end of its cycle
allowing SERV to initiate and move through stage 2 naturally.

The perfomance increase is data dependant but in best cases it can run a BNE 
instruction up to 42% faster.

## Changes

The optimisation is spread across five modules, four modified and one new:


| Module | Change |
| --- | --- |
| `serv_alu.v` | Adds `o_mismatch_now`, which goes high the instant a non-zero difference bit appears during an equality comparison. |
| `serv_bne_early.v` | **New module.** Latches the mismatch and produces `o_early_done` — which triggers the early exit. Uses a registered latch to break a combinational loop, which cuases the exit to trigger 1 cycle after a mismatch is detected. |
| `serv_bufreg.v` | Becomes a **dual-purpose register**: it retains the original serial shift, and adds a single-cycle parallel write path so the branch offset can be completed when an early exit fires. |
| `serv_state.v` | On an early exit, the 32-cycle counter is set to final value (31) so Stage 1 terminates cleanly via SERV's own `o_cnt_done`, without corrupting the counter or misaligning Stage 2. |
| `serv_top.v` | Wires the above together, and captures the branch offset in parallel at fetch so it is available immediately when an early exit starts. |


