module Icache (
  input  wire        clk,
  input  wire [8:0]  addr,
  input  wire [31:0] din,
  output wire [31:0] dout,
  input  wire        we
);

reg [31:0] mem [0:511];
integer i;

initial begin
  for (i = 0; i < 512; i = i + 1) mem[i] = 32'h00000000;
`ifdef ICACHE_INIT_FILE
  $readmemh(`ICACHE_INIT_FILE, mem);
`endif
end

assign dout = mem[addr];

always @(posedge clk) begin
  if (we) mem[addr] <= din;
end

endmodule