module Dcache(
  input  wire [8:0] addra,
  input  wire [8:0] addrb,
  input  wire        clka,
  input  wire        clkb,
  input  wire [31:0] dinb,
  output wire [31:0] douta,
  input  wire        ena,
  input  wire        enb,
  input  wire        web
);

reg [31:0] mem [0:511];
integer j;

wire [8:0] ia;
wire [8:0] ib;

assign ia = addra[8:0];
assign ib = addrb[8:0];

initial begin
  for (j = 0; j < 512; j = j + 1) mem[j] = 32'h00000000;
`ifdef DCACHE_INIT_FILE
  $readmemh(`DCACHE_INIT_FILE, mem);
`endif
end

assign douta = mem[ia];		// 组合读

always @(posedge clkb) begin
  if (enb && web) mem[ib] <= dinb;
end

endmodule