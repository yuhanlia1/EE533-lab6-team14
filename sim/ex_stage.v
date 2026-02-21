// ex_stage

module ex_stage (
	input  wire [31:0] IMM_in,
	input  wire        wreg_in,
	input  wire [31:0] rd2_in,
	input  wire [31:0] rd1_in,
	input  wire [4:0]  rd_in,
	input  wire [2:0]  func3_in,
	input  wire [6:0]  func7_in,
	input  wire        ALUsrc_in,
	input  wire        WMM_in,
	input  wire        RMM_in,
	input  wire        MOA_in,
	input  wire        jal_jalr_in,

	output wire [31:0] alu_out,
	output wire [31:0] rd2_out,
	output wire        wreg_out,
	output wire [4:0]  rd_out,
	output wire        WMM_out,
	output wire        RMM_out,
	output wire        MOA_out,
	output wire        jal_jalr_out
);

wire [31:0] b_sel;
assign b_sel = ALUsrc_in ? IMM_in : rd2_in;

wire add_force;
assign add_force = WMM_in | RMM_in;

wire zero_unused;
wire lt_unused;
wire ltu_unused;

alu u_alu (
  .a         (rd1_in),
  .b         (b_sel),
  .func3     (func3_in),
  .func7     (func7_in),
  .add_force (add_force),
  .is_imm    (ALUsrc_in),
  .y         (alu_out),
  .zero      (zero_unused),
  .lt        (lt_unused),
  .ltu       (ltu_unused)
);

assign rd2_out      = rd2_in;
assign wreg_out     = wreg_in;
assign rd_out       = rd_in;
assign WMM_out      = WMM_in;
assign RMM_out      = RMM_in;
assign MOA_out      = MOA_in;
assign jal_jalr_out = jal_jalr_in;

endmodule