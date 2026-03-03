// EX/MEM registers

module ex_mm_reg (
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,

  input  wire [31:0] alu_in,
  input  wire [31:0] rd2_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,

  output reg  [31:0] alu_out,		// debug
  output reg  [31:0] rd2_out,		// debug
  output reg         wreg_out,
  output reg  [4:0]  rd_out,
  output reg         WMM_out,		// debug
  output reg         RMM_out,		// debug
  output reg         MOA_out,
  output reg         jal_jalr_out
);

always @(posedge clk) begin
  if (rst) begin
    alu_out      <= 32'd0;
    rd2_out      <= 32'd0;
    wreg_out     <= 1'b0;
    rd_out       <= 5'd0;
    WMM_out      <= 1'b0;
    RMM_out      <= 1'b0;
    MOA_out      <= 1'b0;
    jal_jalr_out <= 1'b0;
  end else if (enable) begin
    alu_out      <= alu_in;
    rd2_out      <= rd2_in;
    wreg_out     <= wreg_in;
    rd_out       <= rd_in;
    WMM_out      <= WMM_in;
    RMM_out      <= RMM_in;
    MOA_out      <= MOA_in;
    jal_jalr_out <= jal_jalr_in;
  end
end

endmodule