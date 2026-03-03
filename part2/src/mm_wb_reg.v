// MEM/WB registers

module mm_wb_reg (
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,

  input  wire [31:0] alu_in,
  input  wire [31:0] mem_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        MOA_in,

  output reg  [31:0] alu_out,
  output wire [31:0] mem_out,
  output reg         wreg_out,
  output reg  [4:0]  rd_out,
  output reg         MOA_out
);

always @(posedge clk) begin
  if (rst) begin
    alu_out  <= 32'd0;
    //mem_out  <= 32'd0;
    wreg_out <= 1'b0;
    rd_out   <= 5'd0;
    MOA_out  <= 1'b0;
  end else if (enable) begin
    alu_out  <= alu_in;
    //mem_out  <= mem_in;
    wreg_out <= wreg_in;
    rd_out   <= rd_in;
    MOA_out  <= MOA_in;
  end else begin
    alu_out  <= alu_out;
    //mem_out  <= mem_out;
    wreg_out <= wreg_out;
    rd_out   <= rd_out;
    MOA_out  <= MOA_out;
  end
end

assign mem_out = mem_in;

endmodule
