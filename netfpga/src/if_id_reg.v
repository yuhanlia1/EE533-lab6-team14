// -------------------- IF/ID reg (keeps wist_out) --------------------
module if_id_reg (
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,
  input  wire        wist,
  input  wire [10:0] pc_in,
  input  wire [31:0] inst_in,
  output reg  [10:0] pc_out,
  output wire [31:0] inst_out,
  output reg         wist_out
);

always @(posedge clk) begin
  if (rst) begin
    pc_out   <= 11'd0;
    wist_out <= 1'b0;
  end else if (enable) begin
    pc_out   <= pc_in;
    wist_out <= wist;
  end else begin
    pc_out   <= pc_out;
    wist_out <= wist_out;
  end
end

// keep as-is for sync BRAM style in your current setup
assign inst_out = inst_in;

endmodule