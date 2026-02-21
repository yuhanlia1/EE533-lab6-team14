// mem stage

module mm_stage (
  input  wire        clk,

  input  wire [31:0] alu_in,
  input  wire [31:0] rd2_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,

  output wire [31:0] alu_out,
  output wire [31:0] mem_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        MOA_out
);

wire [8:0] addr_bus;
assign addr_bus = alu_in[10:2];		// was [8:0]

assign alu_out  = jal_jalr_in ? rd2_in : alu_in;

assign wreg_out = wreg_in;
assign rd_out   = rd_in;
assign MOA_out  = MOA_in;

Dcache Dmm(
  .addra (addr_bus),
  .addrb (addr_bus),
  .clka  (clk),
  .clkb  (clk),
  .dinb  (rd2_in),
  .douta (mem_out),
  .ena   (RMM_in),
  .enb   (WMM_in),
  .web   (WMM_in)
);

endmodule