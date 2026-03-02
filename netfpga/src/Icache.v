module Icache (
  input  wire        clk,
  input  wire [8:0]  addr,
  input  wire [31:0] din,
  output reg  [31:0] dout,
  input  wire        we
);

reg [31:0] mem [0:511];

always @(posedge clk) begin
  if (we) mem[addr] <= din;
  dout <= mem[addr];
end

endmodule