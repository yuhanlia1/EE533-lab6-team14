`timescale 1ns/1ps

// ID/EX pipeline register for mid-pipe branch + 2-cycle kill (wist)
// - wist_out is muxed: (flush_in) ? 1 : flush_out
// - Branch compare moved to EX, so this stage only carries is_b/is_jal/is_jalr.
module id_ex_reg (
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,

  input  wire [10:0] pc_in,
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

  input  wire        flush_in,
  input  wire        flush_out,

  input  wire        is_b_in,
  input  wire        is_jal_in,
  input  wire        is_jalr_in,

  output reg  [10:0] pc_out,
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
  output reg         jal_jalr_out,

  output reg         wist_out,
  output reg         is_b_out,
  output reg         is_jal_out,
  output reg         is_jalr_out
);

wire wist_in_mux;
assign wist_in_mux = (flush_in) ? 1'b1 : flush_out;

always @(posedge clk) begin
  if (rst) begin
    pc_out       <= 11'd0;
    IMM_out      <= 32'd0;
    wreg_out     <= 1'b0;
    rd2_out      <= 32'd0;
    rd1_out      <= 32'd0;
    rd_out       <= 5'd0;
    func3_out    <= 3'd0;
    func7_out    <= 7'd0;
    ALUsrc_out   <= 1'b0;
    WMM_out      <= 1'b0;
    RMM_out      <= 1'b0;
    MOA_out      <= 1'b0;
    jal_jalr_out <= 1'b0;

    wist_out     <= 1'b0;
    is_b_out     <= 1'b0;
    is_jal_out   <= 1'b0;
    is_jalr_out  <= 1'b0;
  end else if (enable) begin
    pc_out       <= pc_in;
    IMM_out      <= IMM;
    wreg_out     <= wreg;
    rd2_out      <= rd2;
    rd1_out      <= rd1;
    rd_out       <= rd;
    func3_out    <= func3;
    func7_out    <= func7;
    ALUsrc_out   <= ALUsrc;
    WMM_out      <= WMM;
    RMM_out      <= RMM;
    MOA_out      <= MOA;
    jal_jalr_out <= jal_jalr;

    wist_out     <= wist_in_mux;
    is_b_out     <= is_b_in;
    is_jal_out   <= is_jal_in;
    is_jalr_out  <= is_jalr_in;
  end
end

endmodule
