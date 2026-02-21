// IF/ID 

module if_id_reg (
	input  wire        clk		,
	input  wire        rst		,
	input  wire        enable	,
	input  wire        wist		,
	input  wire [8:0]  pc_in	,
	input  wire [31:0] inst_in	,	// instruction
	output reg  [8:0]  pc_out	,
	output reg  [31:0] inst_out	,
	output reg         wist_out
);

always @(posedge clk) begin
  if (rst) begin
    pc_out   <= 9'd0	;
    inst_out <= 32'd0	;
    wist_out <= 1'b0	;
  end else if (enable) begin
    pc_out   <= pc_in	;
    inst_out <= inst_in	;
    wist_out <= wist	;     // 只负责把flush标记往后传
  end else begin
    pc_out   <= pc_out	;
    inst_out <= inst_out;
    wist_out <= wist_out;
  end
end

endmodule