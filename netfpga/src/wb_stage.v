// WB stage

module wb_stage (
  input  wire [31:0] alu_in,
  input  wire [31:0] mem_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        MOA_in,

  output wire [31:0] wb_data_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out
);

assign wb_data_out = MOA_in ? mem_in : alu_in;
assign wreg_out = wreg_in;
assign rd_out   = rd_in;

endmodule