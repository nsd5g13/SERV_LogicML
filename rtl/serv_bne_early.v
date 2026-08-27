/*
 * serv_bne_early.v : BNE / conditional-branch early-exit decision logic
 *
 *
 * During Stage 1 of a conditional branch, the ALU compares rs1 and rs2 one
 * bit per cycle. serv_alu raises i_mismatch_now the instant a mismatch
 * appears, without waiting for the full 32-cycle count. This module 
 * latches that event and produces o_early_done,
 * which:
 *   - Drives bufreg's parallel-write (completing the branch offset in one
 *     cycle, since Stage 1's serial shift is cut short), and
 *   - Tells serv_state to terminate Stage 1 early.
 *
 * The latch (early_exit_r) is set on the first mismatch of a conditional
 * branch's Stage 1 and cleared when not in Stage 1 (!i_init), so
 * it can never leak into the next instruction.
 *
 * Only the registered latch feeds o_early_done (not the combinational
 * mismatch) so that the path from o_early_done back through serv_state's
 * counter to the ALU is broken by a flip-flop which avoids a combinational loop.
 */
`default_nettype none
module serv_bne_early
  (
   input wire  i_clk,
   //State
   input wire  i_init,           // high during Stage 1
   //Control (from decoder)
   input wire  i_branch_op,      // this is a branch/jump
   input wire  i_cond_branch,    // and it's conditional (beq/bne/blt/...etc)
   //Detect (from ALU)
   input wire  i_mismatch_now,   // a mismatch was seen this cycle
   //Result
   output wire o_early_done);    // terminate Stage 1 early / trigger parallel write

   reg early_exit_r;

   always @(posedge i_clk)
     if (!i_init)
       early_exit_r <= 1'b0;                                   // clear outside Stage 1
     else if (i_mismatch_now & i_branch_op & i_cond_branch)
       early_exit_r <= 1'b1;                                   // latch this instr's mismatch

   assign o_early_done = i_init & i_branch_op & i_cond_branch & early_exit_r;

endmodule
