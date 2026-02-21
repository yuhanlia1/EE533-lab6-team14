module id_ex_reg (
	input  wire        clk,
	input  wire        rst,
	input  wire        enable,

    input  wire [31:0] IMM,
	input  wire        wreg,
	input  wire [31:0] rd2,
	input  wire [31:0] rd1,
	input  wire [4:0]  rd,
	input  wire [2:0]  func3,
	input  wire [6:0]  func7,
	input  wire        ALUsrc,
	input  wire        WMM,
	input  wire        RMM,
	input  wire        MOA,
	input  wire        jal_jalr,

    output reg  [31:0] IMM_out,
	output reg         wreg_out,
	output reg  [31:0] rd2_out,
	output reg  [31:0] rd1_out,
	output reg  [4:0]  rd_out,
	output reg  [2:0]  func3_out,
	output reg  [6:0]  func7_out,
	output reg         ALUsrc_out,
	output reg         WMM_out,
	output reg         RMM_out,
	output reg         MOA_out,
	output reg         jal_jalr_out
);

always @(posedge clk) begin
  if (rst) begin
    IMM_out       <= 32'd0;
    wreg_out      <= 1'b0;
    rd2_out       <= 32'd0;
    rd1_out       <= 32'd0;
    rd_out        <= 5'd0;
    func3_out     <= 3'd0;
    func7_out     <= 7'd0;
    ALUsrc_out    <= 1'b0;
    WMM_out       <= 1'b0;
    RMM_out       <= 1'b0;
    MOA_out       <= 1'b0;
    jal_jalr_out  <= 1'b0;
  end else if (enable) begin
    IMM_out       <= IMM;
    wreg_out      <= wreg;
    rd2_out       <= rd2;
    rd1_out       <= rd1;
    rd_out        <= rd;
    func3_out     <= func3;
    func7_out     <= func7;
    ALUsrc_out    <= ALUsrc;
    WMM_out       <= WMM;
    RMM_out       <= RMM;
    MOA_out       <= MOA;
    jal_jalr_out  <= jal_jalr;
  end else begin
    IMM_out       <= IMM_out;
    wreg_out      <= wreg_out;
    rd2_out       <= rd2_out;
    rd1_out       <= rd1_out;
    rd_out        <= rd_out;
    func3_out     <= func3_out;
    func7_out     <= func7_out;
    ALUsrc_out    <= ALUsrc_out;
    WMM_out       <= WMM_out;
    RMM_out       <= RMM_out;
    MOA_out       <= MOA_out;
    jal_jalr_out  <= jal_jalr_out;
  end
end

endmodule