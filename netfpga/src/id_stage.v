module id_stage (
	input  	wire        clk,
	input  	wire        rst,
	
	input  	wire [10:0] pc_in,      // CHANGED
	input  	wire [31:0] inst_in,
	
	input  	wire [4:0]  wb_rd_addr,
	input  	wire [31:0] wb_data,
	input  	wire        wb_wea,
	
	input  	wire        wist,
	
	input	wire [4:0]	dbg_addr,
	output	reg  [31:0] dbg_rdata,
	
	output 	reg  [31:0] imm,
	output 	wire [10:0] addr_out,   // CHANGED
	output 	wire        jump_valid,
	
	output 	wire        wreg,
	output 	wire [31:0] rd1_out,
	output 	wire [31:0] rd2_out,
	output 	wire [4:0]  rd_out,
	output 	wire [2:0]  funct3_out,
	output 	wire [6:0]  funct7_out,
	output 	wire        ALUsrc,
	output 	wire        WMM,
	output 	wire        RMM,
	output 	wire        MOA,
	output 	wire        jal_jalr
);

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;

wire [10:0] pc_plus4;        // CHANGED
wire [31:0] pc_u32;          // CHANGED sizing below
wire [31:0] pc_plus4_u32;    // CHANGED

wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [4:0] rd_addr;

wire [31:0] rd1;
wire [31:0] rd2;
wire is_lui;
wire is_auipc;

assign opcode   = inst_in[6:0];
assign funct3   = inst_in[14:12];
assign funct7   = inst_in[31:25];
assign rs1_addr = inst_in[19:15];
assign rs2_addr = inst_in[24:20];
assign rd_addr  = inst_in[11:7];

assign rd_out      = rd_addr;
assign funct3_out   = funct3;
assign funct7_out   = funct7;

reg_files u_reg_files (
  .clk      (clk),
  .rst      (rst),

  .rs1_addr (rs1_addr),
  .rs2_addr (rs2_addr),

  .rd_addr  (wb_rd_addr),
  .wb_data  (wb_data),
  .wea      (wb_wea),

  .dbg_addr (dbg_addr),
  .dbg_data (dbg_data_rf),

  .rd1      (rd1),
  .rd2      (rd2)
);

assign rd1_out = rd1;

wire is_b;
wire is_jal;
wire is_jalr;
wire [31:0] auipc_val;

assign is_lui   = (opcode == 7'b0110111);
assign is_auipc = (opcode == 7'b0010111);

assign is_b    = (opcode == 7'b1100011);
assign is_jal  = (opcode == 7'b1101111);
assign is_jalr = (opcode == 7'b1100111) && (funct3 == 3'b000);

assign jal_jalr = is_jal | is_jalr | is_lui | is_auipc;

// CHANGED: pc+4 (byte)
assign pc_plus4     = pc_in + 11'd4;
assign pc_u32       = {21'd0, pc_in};
assign pc_plus4_u32 = {21'd0, pc_plus4};

assign auipc_val = pc_u32 + imm;

assign rd2_out = (is_jal | is_jalr) ? pc_plus4_u32 :
                 is_auipc ? auipc_val :
                 is_lui   ? imm :
                 rd2;

wire eq, lt_s, ge_s, lt_u, ge_u;
assign eq   = (rd1 == rd2);
assign lt_s = ($signed(rd1) <  $signed(rd2));
assign ge_s = ($signed(rd1) >= $signed(rd2));
assign lt_u = (rd1 <  rd2);
assign ge_u = (rd1 >= rd2);

reg b_take;
always @(*) begin
  if (is_b) begin
    case (funct3)
      3'b000: b_take = eq;
      3'b001: b_take = ~eq;
      3'b100: b_take = lt_s;
      3'b101: b_take = ge_s;
      3'b110: b_take = lt_u;
      3'b111: b_take = ge_u;
      default: b_take = 1'b0;
    endcase
  end else begin
    b_take = 1'b0;
  end
end

wire jump_valid_int;
assign jump_valid_int = b_take | is_jal | is_jalr;

// -------------------- Immediate decode --------------------
// CHANGED: B/J immediates append 1'b0 (RISC-V spec bit0=0)
always @(*) begin
  case (opcode)
    7'b0010011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // I
    7'b0000011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // LW
    7'b1100111: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // JALR
    7'b1110011: imm = {{20{inst_in[31]}}, inst_in[31:20]}; // CSR
    7'b0100011: imm = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]}; // S
    7'b1100011: imm = {{19{inst_in[31]}}, inst_in[31], inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0}; // CHANGED (B)
    7'b1101111: imm = {{11{inst_in[31]}}, inst_in[31], inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0}; // CHANGED (J)
    7'b0110111: imm = {inst_in[31:12], 12'b0}; // U
    7'b0010111: imm = {inst_in[31:12], 12'b0}; // U
    default:    imm = 32'd0;
  endcase
end

// -------------------- Branch/J target --------------------
// CHANGED: use byte PC, full 32-bit add, and force 4-byte alignment for this 32-bit-only core
wire [31:0] base32;
wire [31:0] target_raw;
wire [31:0] target_aligned;

assign base32     = is_jalr ? rd1 : pc_u32;
assign target_raw = base32 + imm;

// CHANGED: clear low 2 bits so Icache (pc>>2) works for 32-bit-only instructions
assign target_aligned = target_raw & ~32'd3;

assign addr_out = target_aligned[10:0];

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

assign jump_valid = wist ? 1'b0 : jump_valid_int;
assign WMM        = wist ? 1'b0 : WMM_int;
assign RMM        = wist ? 1'b0 : RMM_int;
assign wreg       = wist ? 1'b0 : wreg_int;

assign MOA        = MOA_int;

endmodule