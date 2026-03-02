module Dcache(
  input  wire [8:0] addra,
  input  wire [8:0] addrb,
  input  wire        clka,
  input  wire        clkb,
  input  wire [31:0] dinb,
  output reg  [31:0] douta,
  input  wire        ena,
  input  wire        enb,
  input  wire        web
);

reg [31:0] mem [0:511];

wire [8:0] ia;
wire [8:0] ib;

assign ia = addra[8:0];
assign ib = addrb[8:0];

// assign douta = mem[ia];		// 组合读

always @(posedge clkb) begin
  if (enb && web) mem[ib] <= dinb;
  
  douta <= mem[ia];
end

endmodule