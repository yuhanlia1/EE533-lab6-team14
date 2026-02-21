module alu (
  input  wire [31:0] a,
  input  wire [31:0] b,
  input  wire [2:0]  func3,
  input  wire [6:0]  func7,
  input  wire        add_force,
  input  wire        is_imm,
  output reg  [31:0] y,
  output wire        zero,
  output wire        lt,
  output wire        ltu
);

wire sub_sra;
assign sub_sra = func7[5];

wire [4:0] shamt;
assign shamt = b[4:0];

assign zero = (a == b);
assign lt   = ($signed(a) < $signed(b));
assign ltu  = (a < b);

wire [31:0] srl_val;
assign srl_val = a >> shamt;

wire [31:0] sra_val;
assign sra_val = (shamt == 5'd0) ? a :
                 (srl_val | ({32{a[31]}} << (32 - shamt)));

always @(*) begin
  y = 32'd0;

  if (add_force) begin
    y = a + b;
  end else if (is_imm) begin
    case (func3)
      3'b000: y = a + b;
      3'b010: y = lt  ? 32'd1 : 32'd0;
      3'b011: y = ltu ? 32'd1 : 32'd0;
      3'b100: y = a ^ b;
      3'b110: y = a | b;
      3'b111: y = a & b;
      3'b001: y = (func7[5] == 1'b0) ? (a << shamt) : 32'd0;
      3'b101: y = sub_sra ? sra_val : srl_val;
      default: y = 32'd0;
    endcase
  end else begin
    case (func3)
      3'b000: y = sub_sra ? (a - b) : (a + b);
      3'b001: y = a << shamt;
      3'b010: y = lt  ? 32'd1 : 32'd0;
      3'b011: y = ltu ? 32'd1 : 32'd0;
      3'b100: y = a ^ b;
      3'b101: y = sub_sra ? sra_val : srl_val;
      3'b110: y = a | b;
      3'b111: y = a & b;
      default: y = 32'd0;
    endcase
  end
end

endmodule