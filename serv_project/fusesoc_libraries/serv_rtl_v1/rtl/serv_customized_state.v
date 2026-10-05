// Signal translation layer between SERV state machine and the custom ALU.
// Takes control signals from serv_state and serv_decode and translates them
// into the control signals needed by cus_alu for popcount execution.
// Uses the same clock as serv_state -- no independent clock generation.

module serv_customized_state (
    input wire i_clk,
    input wire i_rst,
    input wire i_is_customized,
    input wire i_init,
    input wire i_cnt_en,
    input wire i_cnt_done,
    input wire i_cnt0,
    output reg o_mode,
    output reg o_clr
);

// Delay i_init by one cycle to detect the rising edge.
// init_rising pulses for exactly one cycle when i_init goes high,
// which marks the start of stage one in a two-stage instruction.
reg init_r;
wire init_rising = i_init & ~init_r;

always @(posedge i_clk) begin
    if (i_rst) begin
        init_r <= 1'b0;
    end else begin
        init_r <= i_init;
    end
end

// Translate i_init to the mode signal for cus_alu:
// When servicing a custom instruction (i_is_customized asserted):
//   - i_init = 1 (stage one)  -> o_mode = 1 (accumulate rs1 bits)
//   - i_init = 0 (stage two)  -> o_mode = 0 (shift accumulated result out)
// When NOT servicing a custom instruction, always drive o_mode low.
always @(*) begin
    if (i_is_customized)
        o_mode = i_init;
    else
        o_mode = 1'b0;
end

// Generate a one-cycle synchronous clear pulse for the cus_alu accumulator
// at the very start of stage one, before the first rs1 bit is accumulated.
// This reset must complete before i_cnt_en goes high and the bit-serial
// counter begins counting, to ensure no bits are missed.
// i_cnt_en, i_cnt_done, and i_cnt0 are reserved for future use -- they will
// allow the translation logic to be extended for arbitrary-width popcount
// implementations beyond the current 32-bit case.
always @(posedge i_clk) begin
    if (i_rst) begin
        o_clr <= 1'b0;
    end else begin
        o_clr <= i_is_customized & init_rising;
    end
end

endmodule
