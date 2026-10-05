module cus_alu(
    input wire i_clk,
    input wire i_rst,
    input wire i_clr,
    input wire i_mode,
    input wire i_is_customized,
    input wire o_rs1,
    output wire rs1,
    output wire is_acc_done,
    output wire o_serial
);

reg [5:0] pr_partial;

wire serial_acc = pr_partial[0];

//Mux: when is_customzied = 1, output serial_acc, when 0, output o_rs1
assign rs1 = i_is_customized ? serial_acc : o_rs1;

//Raw serial popcount output (bypasses the mux): during stage two it shifts
//out the accumulated count LSB-first, and is 0 once pr_partial is drained.
assign o_serial = serial_acc;

assign is_acc_done = |pr_partial;

//Accumulate 1
wire [5:0] pr_acc = pr_partial + {5'b0,o_rs1};

always @(posedge i_clk, posedge i_rst) begin
    if (i_rst == 1) begin
        pr_partial <= 6'b0;
    end else if (i_clr == 1) begin
        pr_partial <= 6'b0;
    end else if (i_mode == 1) begin
        pr_partial <= pr_acc;
    end else if (i_mode == 0) begin
        pr_partial <= {1'b0 , pr_partial[5:1]};
    end
end

endmodule