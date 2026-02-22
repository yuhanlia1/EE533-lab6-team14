// mem stage

module mm_stage (
  input  wire        clk,

  input  wire [31:0] alu_in_bypass,
  input  wire [31:0] alu_in,
  input  wire [31:0] rd2_in_bypass,
  input  wire [31:0] rd2_in,
  
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,

  input  wire        dmem_interact_en,
  input  wire [8:0]  dmem_sw_addr,
  input  wire [31:0] dmem_sw_wdata,
  input  wire        dmem_sw_we,

  output wire  [31:0] alu_out,	
  output wire [31:0] mem_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        MOA_out
);

wire [8:0] addr_cpu;
wire [8:0] addr_final;
wire [31:0] dinb_final;
wire ena_final;
wire enb_final;
wire web_final;

assign addr_cpu   = alu_in_bypass[10:2];
assign addr_final = dmem_interact_en ? dmem_sw_addr : addr_cpu;

assign dinb_final = dmem_interact_en ? dmem_sw_wdata : rd2_in_bypass;

assign ena_final  = dmem_interact_en ? (~dmem_sw_we) : RMM_in;
assign enb_final  = dmem_interact_en ? dmem_sw_we    : WMM_in;
assign web_final  = enb_final;

assign alu_out  = jal_jalr_in ? rd2_in : alu_in;

assign wreg_out = wreg_in;
assign rd_out   = rd_in;
assign MOA_out  = MOA_in;

Dcache Dmm(
  .addra (addr_final),
  .addrb (addr_final),
  .clka  (clk),
  .clkb  (clk),
  .dinb  (dinb_final),
  .douta (mem_out),
  .ena   (ena_final),
  .enb   (enb_final),
  .web   (web_final)
);

endmodule