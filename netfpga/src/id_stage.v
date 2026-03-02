`timescale 1ns/1ps

// ID stage for mid-pipe branch:
// - No wist gating here anymore.
// - Branch compare moved to EX, so ID only outputs is_b/is_jal/is_jalr flags.
// - Keeps debug read port (dbg_addr/dbg_rdata) via reg_files.
module id_stage (
  input  wire        clk,
  input  wire        rst,

  input  wire [10:0] pc_in,      // byte PC
  input  wire [31:0] inst_in,

  input  wire [4:0]  wb_rd_addr,
  input  wire [31:0] wb_data,
  input  wire        wb_wea,

  input  wire [4:0]  dbg_addr,
  output wire [31:0] dbg_rdata,

  output reg  [31:0] imm,

  // mid-pipe branch: only opcode-type bits are generated in ID
  output wire        is_b_out,
  output wire        is_jal_out,
  output wire        is_jalr_out,

  output wire        wreg,
  output wire [31:0] rd1_out,
  output wire [31:0] rd2_out,
  output wire [4:0]  rd_out,
  output wire [2:0]  funct3_out,
  output wire [6:0]  funct7_out,
  output wire        ALUsrc,
  output wire        WMM,
  output wire        RMM,
  output wire        MOA,
  output wire        jal_jalr
);

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;

wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [4:0] rd_addr;

wire [31:0] rd1;
wire [31:0] rd2;

assign opcode   = inst_in[6:0];
assign funct3   = inst_in[14:12];
assign funct7   = inst_in[31:25];
assign rs1_addr = inst_in[19:15];
assign rs2_addr = inst_in[24:20];
assign rd_addr  = inst_in[11:7];

assign rd_out     = rd_addr;
assign funct3_out = funct3;
assign funct7_out = funct7;

reg_files u_reg_files (
  .clk      (clk),
  .rst      (rst),

  .rs1_addr (rs1_addr),
  .rs2_addr (rs2_addr),

  .rd_addr  (wb_rd_addr),
  .wb_data  (wb_data),
  .wea      (wb_wea),

  .dbg_addr (dbg_addr),
  .dbg_data (dbg_rdata),

  .rd1      (rd1),
  .rd2      (rd2)
);

assign rd1_out = rd1;

// decode helpers
wire is_b;
wire is_jal;
wire is_jalr;
wire is_lui;
wire is_auipc;

assign is_b    = (opcode == 7'b1100011);
assign is_jal  = (opcode == 7'b1101111);
assign is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);

assign is_lui   = (opcode == 7'b0110111);
assign is_auipc = (opcode == 7'b0010111);

assign is_b_out    = is_b;
assign is_jal_out  = is_jal;
assign is_jalr_out = is_jalr;

// keep existing jal_jalr meaning (used by MEM stage for writeback select)
assign jal_jalr = is_jal | is_jalr | is_lui | is_auipc;

// pc+4 and AUIPC/LUI writeback helper (NOT jump target)
wire [10:0] pc_plus4;
wire [31:0] pc_u32;
wire [31:0] pc_plus4_u32;
wire [31:0] auipc_val;

assign pc_plus4     = pc_in + 11'd4;
assign pc_u32       = {21'd0, pc_in};
assign pc_plus4_u32 = {21'd0, pc_plus4};

assign auipc_val = pc_u32 + imm;

// rd2_out mux (do not change)
assign rd2_out = (is_jal | is_jalr) ? pc_plus4_u32 :
                 is_auipc ? auipc_val :
                 is_lui   ? imm :
                 rd2;

// Immediate decode (B/J immediates append 1'b0)
always @(*) begin
  case (opcode)
    7'b0010011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // I
    7'b0000011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // LW
    7'b1100111: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // JALR
    7'b1110011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // CSR
    7'b0100011: imm = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]}; // S
    7'b1100011: imm = {{19{inst_in[31]}}, inst_in[31], inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0}; // B
    7'b1101111: imm = {{11{inst_in[31]}}, inst_in[31], inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0}; // J
    7'b0110111: imm = {inst_in[31:12], 12'b0}; // U
    7'b0010111: imm = {inst_in[31:12], 12'b0}; // U
    default:    imm = 32'd0;
  endcase
end

assign ALUsrc = (opcode == 7'b0010011) | (opcode == 7'b0000011) | (opcode == 7'b0100011);

wire WMM_int;
wire RMM_int;
wire MOA_int;
wire wreg_int;

assign WMM_int = (opcode == 7'b0100011);
assign RMM_int = (opcode == 7'b0000011);
assign MOA_int = (opcode == 7'b0000011);

assign wreg_int = (opcode == 7'b0110011) |
                  (opcode == 7'b0010011) |
                  (opcode == 7'b0000011) |
                  (opcode == 7'b1101111) |
                  (opcode == 7'b1100111) |
                  (opcode == 7'b0110111) |
                  (opcode == 7'b0010111);

// No wist gating here anymore.
assign WMM  = WMM_int;
assign RMM  = RMM_int;
assign wreg = wreg_int;
assign MOA  = MOA_int;

endmodule
