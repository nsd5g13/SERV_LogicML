/*
* Modified version of serv_bufreg.v, with a dual-function WRITE modification 
* 
* Based on serv_bufgreg.v,
*
* Modifications for BNE early exit support:
*   Parallel write mode added to the data register. Two new inputs added:
*
*     i_parallel_we        - when high, perform a single-cycle parallel write
*     i_parallel_data[31:0]- the value written when i_parallel_we is high
*
*  When a mismatch is detected during stage 1 and an ealry exit is triggered,
*  stage 1 ends imediatly meaning the offset has not been fully shifted into 
*  bufreg. This modified bufreg sets i_parallel_we high for one cycle, allowing 
*  the offset to be parallel written into the data register from i_parallel_data
*  in one cycle, allowing stage 2 to proceed with the correct offset.
*  
*   The read path (o_q serial shift-out) is unchanged.
*   When i_parallel_we is low, behaviour is identical to the original,
*   all existing instructions are therefore unaffected.
*
*/


`default_nettype none
module serv_bufreg #(
      parameter [0:0] MDU = 0,
      parameter W = 1,
      parameter B = W-1
)(
   input wire      i_clk,
   //State
   input wire      i_cnt0,
   input wire 	      i_cnt1,
   input wire 	      i_cnt_done,
   input wire 	      i_en,
   input wire 	      i_init,
   input wire           i_mdu_op,
   output wire [1:0]    o_lsb,
   //Control
   input wire 	      i_rs1_en,
   input wire 	      i_imm_en,
   input wire 	      i_clr_lsb,
   input wire 	      i_shift_op,
   input wire 	      i_right_shift_op,
   input wire [2:0]   i_shamt,
   input wire 	      i_sh_signed,
   //Data
   input wire [B:0] i_rs1,
   input wire [B:0] i_imm,
   output wire [B:0] o_q,
   //External
   output wire [31:0] o_dbus_adr,
   //Extension
   output wire [31:0] o_ext_rs1,
   // New dual-function parallel-write ports for BNE early-exit  
   input wire         i_parallel_we,    // 1 = parallel 32-bit write this cycle,
   input wire [31:0] i_parallel_data);   // value to load in parallel

   wire		      c;
   wire [B:0]	      q;
   reg [B:0]	      c_r;
   reg [31:0]	      data;
   wire [B:0]	      clr_lsb;

   assign clr_lsb[0] = i_cnt0 & i_clr_lsb;

   generate
      if (W > 1) begin : gen_clr_lsb_w_gt_1
         assign  clr_lsb[B:1] = {B{1'b0}};
      end
   endgenerate

   assign {c,q} = {1'b0,(i_rs1 & {W{i_rs1_en}})} + {1'b0,(i_imm & {W{i_imm_en}} & ~clr_lsb)} + c_r;

always @(posedge i_clk) begin
      //Make sure carry is cleared before loading new data
      c_r    <= {W{1'b0}};
      c_r[0] <= c & i_en;
   end

   generate 
        if (W == 1) begin : gen_w_eq_1
            always @(posedge i_clk) begin
                // New: parallel write takes priority over serial shift-in 
                if (i_parallel_we) begin
                    data <= i_parallel_data;  // parallel write
                end else begin 
                // Original serial shift-in behaviour 
                    if (i_en)
                        data[31:2] <= {i_init ? q : {W{data[31] & i_sh_signed}}, data[31:3]};

	                if (i_init ? (i_cnt0 | i_cnt1) : i_en)
	                    data[1:0] <= {i_init ? q : data[2], data[1]};
	            end
            end

        assign o_lsb = (MDU & i_mdu_op) ? 2'b00 : data[1:0];
        assign o_q = data[0] & {W{i_en}};
    end else if (W == 4) begin : gen_lsb_w_4
        reg [1:0] lsb;
        reg [W-2:0] data_tail;
 
        wire [2:0] shift_amount
           = !i_shift_op ? 3'd3 :
            i_right_shift_op ? (3'd3+{1'b0,i_shamt[1:0]}) :
            ({1'b0,~i_shamt[1:0]});

        always @(posedge i_clk) begin 
            // New: parallel write takes priority over serial shift-in
            if (i_parallel_we) begin
                data <= i_parallel_data;
                if (i_cnt0) lsb <= i_parallel_data[1:0];
            end else begin
                // Original: serial shift-in 
                if (i_en)
                    if (i_cnt0) lsb <= q[1:0];
                if (i_en)
                    data <= {i_init ? q : {W{i_sh_signed & data[31]}}, data[31:W]};
                if (i_en)
                    data_tail <= data[B:1] & {B{~i_cnt_done}};
            end
        end    

        wire [2*W+B-2:0] muxdata = {data[W+B-1:0],data_tail};
	    wire [B:0]	  muxout = muxdata[{1'b0,shift_amount}+:W];

	    assign o_lsb = (MDU & i_mdu_op) ? 2'b00 : lsb;
	    assign o_q = i_en ? muxout : {W{1'b0}};
      end
   endgenerate


   assign o_dbus_adr = {data[31:2], 2'b00};
   assign o_ext_rs1  = data;

endmodule
