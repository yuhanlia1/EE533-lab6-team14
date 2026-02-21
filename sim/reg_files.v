// XLEN = 32 regsfile

module reg_files (
  input  wire        clk,
  input  wire        rst,

  input  wire [4:0]  rs1_addr,
  input  wire [4:0]  rs2_addr,

  input  wire [4:0]  rd_addr,     // from WB stage
  input  wire [31:0] wb_data,     // from WB stage
  input  wire        wea,         // write enable (from WB stage)

  output wire [31:0] rd1,
  output wire [31:0] rd2
);

reg [31:0] regs [0:31];
integer i;

/* synchronous write, x0 stays zero */
always @(posedge clk) begin
  if (rst) begin
    for (i = 0; i < 32; i = i + 1) begin
      regs[i] <= 32'd0;
    end
  end else begin
    if (wea && (rd_addr != 5'd0)) begin
      regs[rd_addr] <= wb_data;
    end
    regs[0] <= 32'd0;
  end
end

/* combinational read with simple write-forwarding , IRFR */
assign rd1 = (rs1_addr == 5'd0) ? 32'd0 :
             (wea && (rd_addr != 5'd0) && (rd_addr == rs1_addr)) ? wb_data : 
			 regs[rs1_addr];

assign rd2 = (rs2_addr == 5'd0) ? 32'd0 :
             (wea && (rd_addr != 5'd0) && (rd_addr == rs2_addr)) ? wb_data : 
			 regs[rs2_addr];

endmodule