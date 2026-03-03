// Part2: 4-thread pipeline datapath (plain Verilog)
//
// Changes vs the buggy Part2 attempt:
//   [FIX-1] Branch/jump must update the PC of the *thread in ID stage* (tid_id),
//           not the *thread currently in IF* (tid_sel).
//           -> pc4_thread now takes jump_tid, and updates that thread's PC.
//   [FIX-2] The old single-thread "flush/wist" was incorrectly stalling/killing
//           OTHER threads (because tid_id != tid_sel in barrel scheduling).
//           -> wist is tied to 0 in Part2.

`timescale 1ns/1ps

module pipeline_datapath(
    input  wire clk,
    input  wire rst
);

  // simple always-on enable
  wire en_reg;
  assign en_reg = 1'b1;

  // 4-thread barrel scheduling: one thread per cycle
  reg [31:0] cycle_cnt;
  always @(posedge clk) begin
    if (rst) cycle_cnt <= 32'd0;
    else     cycle_cnt <= cycle_cnt + 32'd1;
  end

  wire [1:0] tid_sel;
  assign tid_sel = cycle_cnt[1:0];

  // ---------------- IF ----------------
  wire [31:0] pc_if;       // byte PC
  wire [8:0]  pc_word_if;  // word index for I$ (pc_if[10:2])
  wire [31:0] instr_in;

  // ---------------- IF/ID ----------------
  wire [31:0] pc_id;
  wire [31:0] instr_id;
  wire [1:0]  tid_id;

  // ---------------- ID outputs ----------------
  wire [31:0] imm_id;
  wire [31:0] addr_id;         // jump target in bytes
  wire        jump_valid_id;

  wire        wreg_id;
  wire [31:0] rd1_id;
  wire [31:0] rd2_id;
  wire [4:0]  rd_id;
  wire [2:0]  funct3_id;
  wire [6:0]  funct7_id;
  wire        ALUsrc_id;
  wire        WMM_id;
  wire        RMM_id;
  wire        MOA_id;
  wire        jal_jalr_id;

  // ---------------- ID/EX ----------------
  wire [31:0] IMM_ex;
  wire        wreg_ex;
  wire [31:0] rd2_ex;
  wire [31:0] rd1_ex;
  wire [4:0]  rd_ex;
  wire [2:0]  func3_ex;
  wire [6:0]  func7_ex;
  wire        ALUsrc_ex;
  wire        WMM_ex;
  wire        RMM_ex;
  wire        MOA_ex;
  wire        jal_jalr_ex;
  wire [1:0]  tid_ex;

  // ---------------- EX outputs ----------------
  wire [31:0] alu_ex;
  wire [31:0] rd2_ex_o;
  wire        wreg_ex_o;
  wire [4:0]  rd_ex_o;
  wire        WMM_ex_o;
  wire        RMM_ex_o;
  wire        MOA_ex_o;
  wire        jal_jalr_ex_o;
  wire [1:0]  tid_ex_o;

  // ---------------- EX/MEM ----------------
  wire [31:0] alu_mem_in;
  wire [31:0] rd2_mem_in;
  wire        wreg_mem_in;
  wire [4:0]  rd_mem_in;
  wire        WMM_mem_in;
  wire        RMM_mem_in;
  wire        MOA_mem_in;
  wire        jal_jalr_mem_in;
  wire [1:0]  tid_mem_in;

  // ---------------- MEM outputs ----------------
  wire [31:0] alu_mm;
  wire [31:0] mem_mm;
  wire        wreg_mm;
  wire [4:0]  rd_mm;
  wire        MOA_mm;
  wire [1:0]  tid_mm;

  // ---------------- MEM/WB ----------------
  wire [31:0] alu_mm_wb;
  wire [31:0] mem_mm_wb;
  wire        wreg_mm_wb;
  wire [4:0]  rd_mm_wb;
  wire        MOA_mm_wb;
  wire [1:0]  tid_mm_wb;

  // ---------------- WB outputs ----------------
  wire [31:0] wb_data_out;
  wire        wb_wreg_out;
  wire [4:0]  wb_rd_out;
  wire [1:0]  wb_tid_out;

  // [FIX-2] Part2 barrel: DO NOT use the old single-thread flush.
  wire flush_out;
  wire wist_if;
  assign wist_if = jump_valid_id & (tid_sel == tid_id);

// ---------------- PC + I$ ----------------
  pc4_thread pc_inst(
    .clk        (clk),
    .rst        (rst),
    .enable     (en_reg),
    .tid_sel    (tid_sel),
    // [FIX-1] jump_valid/addr apply to tid_id (thread in ID)
    .jump_valid (jump_valid_id),
    .jump_tid   (tid_id),
    .jump_addr  (addr_id),
    .pc_u32     (pc_if),
    .pc_word    (pc_word_if)
  );

  Icache Imm(
    .clk  (clk),
    .addr (pc_word_if),
    .din  (32'b0),
    .dout (instr_in),
    .we   (1'b0)
  );

  if_id_reg if_id_reg_inst(
    .clk      (clk),
    .rst      (rst),
    .enable   (en_reg),
    .wist     (wist_if),
    .pc_in    (pc_if),
    .inst_in  (instr_in),
    .tid_in   (tid_sel),
    .pc_out   (pc_id),
    .inst_out (instr_id),
    .tid_out  (tid_id),
    .wist_out (flush_out)
  );

  // ---------------- ID ----------------
  id_stage id_stage_inst(
    .clk        (clk),
    .rst        (rst),
    .pc_in      (pc_id),
    .inst_in    (instr_id),
    .tid_in     (tid_id),
    .wb_tid     (wb_tid_out),
    .wb_rd_addr (wb_rd_out),
    .wb_data    (wb_data_out),
    .wb_wea     (wb_wreg_out),
    .wist       (flush_out),
    .imm        (imm_id),
    .addr_out   (addr_id),
    .jump_valid (jump_valid_id),
    .wreg       (wreg_id),
    .rd1_out    (rd1_id),
    .rd2_out    (rd2_id),
    .rd_out     (rd_id),
    .funct3_out (funct3_id),
    .funct7_out (funct7_id),
    .ALUsrc     (ALUsrc_id),
    .WMM        (WMM_id),
    .RMM        (RMM_id),
    .MOA        (MOA_id),
    .jal_jalr   (jal_jalr_id)
  );

  id_ex_reg id_ex_inst(
    .clk         (clk),
    .rst         (rst),
    .enable      (en_reg),
    .tid_in      (tid_id),
    .IMM         (imm_id),
    .wreg        (wreg_id),
    .rd2         (rd2_id),
    .rd1         (rd1_id),
    .rd          (rd_id),
    .func3       (funct3_id),
    .func7       (funct7_id),
    .ALUsrc      (ALUsrc_id),
    .WMM         (WMM_id),
    .RMM         (RMM_id),
    .MOA         (MOA_id),
    .jal_jalr    (jal_jalr_id),
    .tid_out     (tid_ex),
    .IMM_out     (IMM_ex),
    .wreg_out    (wreg_ex),
    .rd2_out     (rd2_ex),
    .rd1_out     (rd1_ex),
    .rd_out      (rd_ex),
    .func3_out   (func3_ex),
    .func7_out   (func7_ex),
    .ALUsrc_out  (ALUsrc_ex),
    .WMM_out     (WMM_ex),
    .RMM_out     (RMM_ex),
    .MOA_out     (MOA_ex),
    .jal_jalr_out(jal_jalr_ex)
  );

  // ---------------- EX ----------------
  ex_stage ex_stage_inst(
    .tid_in       (tid_ex),
    .IMM_in       (IMM_ex),
    .wreg_in      (wreg_ex),
    .rd2_in       (rd2_ex),
    .rd1_in       (rd1_ex),
    .rd_in        (rd_ex),
    .func3_in     (func3_ex),
    .func7_in     (func7_ex),
    .ALUsrc_in    (ALUsrc_ex),
    .WMM_in       (WMM_ex),
    .RMM_in       (RMM_ex),
    .MOA_in       (MOA_ex),
    .jal_jalr_in  (jal_jalr_ex),
    .tid_out      (tid_ex_o),
    .alu_out      (alu_ex),
    .rd2_out      (rd2_ex_o),
    .wreg_out     (wreg_ex_o),
    .rd_out       (rd_ex_o),
    .WMM_out      (WMM_ex_o),
    .RMM_out      (RMM_ex_o),
    .MOA_out      (MOA_ex_o),
    .jal_jalr_out (jal_jalr_ex_o)
  );

  ex_mm_reg ex_mm_reg_inst(
    .clk         (clk),
    .rst         (rst),
    .enable      (en_reg),
    .tid_in      (tid_ex_o),
    .alu_in      (alu_ex),
    .rd2_in      (rd2_ex_o),
    .wreg_in     (wreg_ex_o),
    .rd_in       (rd_ex_o),
    .WMM_in      (WMM_ex_o),
    .RMM_in      (RMM_ex_o),
    .MOA_in      (MOA_ex_o),
    .jal_jalr_in (jal_jalr_ex_o),
    .tid_out     (tid_mem_in),
    .alu_out     (alu_mem_in),
    .rd2_out     (rd2_mem_in),
    .wreg_out    (wreg_mem_in),
    .rd_out      (rd_mem_in),
    .WMM_out     (WMM_mem_in),
    .RMM_out     (RMM_mem_in),
    .MOA_out     (MOA_mem_in),
    .jal_jalr_out(jal_jalr_mem_in)
  );

  // ---------------- MEM ----------------
  mm_stage mm_stage_inst(
    .clk        (clk),
    .tid_in     (tid_mem_in),
    .alu_in     (alu_mem_in),
    .rd2_in     (rd2_mem_in),
    .wreg_in    (wreg_mem_in),
    .rd_in      (rd_mem_in),
    .WMM_in     (WMM_mem_in),
    .RMM_in     (RMM_mem_in),
    .MOA_in     (MOA_mem_in),
    .jal_jalr_in(jal_jalr_mem_in),
    .tid_out    (tid_mm),
    .alu_out    (alu_mm),
    .mem_out    (mem_mm),
    .wreg_out   (wreg_mm),
    .rd_out     (rd_mm),
    .MOA_out    (MOA_mm)
  );

  mm_wb_reg mm_wb_reg_inst(
    .clk      (clk),
    .rst      (rst),
    .enable   (en_reg),
    .tid_in   (tid_mm),
    .alu_in   (alu_mm),
    .mem_in   (mem_mm),
    .wreg_in  (wreg_mm),
    .rd_in    (rd_mm),
    .MOA_in   (MOA_mm),
    .tid_out  (tid_mm_wb),
    .alu_out  (alu_mm_wb),
    .mem_out  (mem_mm_wb),
    .wreg_out (wreg_mm_wb),
    .rd_out   (rd_mm_wb),
    .MOA_out  (MOA_mm_wb)
  );

  // ---------------- WB ----------------
  wb_stage wb_stage_inst(
    .alu_in      (alu_mm_wb),
    .mem_in      (mem_mm_wb),
    .wreg_in     (wreg_mm_wb),
    .rd_in       (rd_mm_wb),
    .MOA_in      (MOA_mm_wb),
    .wb_data_out (wb_data_out),
    .wreg_out    (wb_wreg_out),
    .rd_out      (wb_rd_out)
  );

  // pass tid alongside WB write
  assign wb_tid_out = tid_mm_wb;

endmodule


// ============================================================
// 4-thread PC (byte address) + word index output
// ============================================================
module pc4_thread(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [1:0]  tid_sel,
    input  wire        jump_valid,
    input  wire [1:0]  jump_tid,
    input  wire [31:0] jump_addr,
    output wire [31:0] pc_u32,
    output wire [8:0]  pc_word
);

  reg [31:0] pc_thr [0:3];
  integer k;

  // output current IF thread PC
  assign pc_u32  = pc_thr[tid_sel];
  assign pc_word = pc_thr[tid_sel][10:2];

  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < 4; k = k + 1) pc_thr[k] <= 32'd0;
    end else if (enable) begin
      // default: advance the currently selected IF thread
      // [FIX-1] if the jump is for this same thread, override with jump target
      if (jump_valid && (jump_tid == tid_sel))
        pc_thr[tid_sel] <= jump_addr;
      else
        pc_thr[tid_sel] <= pc_thr[tid_sel] + 32'd4;

      // [FIX-1] if the jump is for a *different* thread (ID stage thread),
      // update that thread PC too.
      if (jump_valid && (jump_tid != tid_sel))
        pc_thr[jump_tid] <= jump_addr;
    end
  end

endmodule


// ============================================================
// IF/ID pipeline register (with thread id)
// ============================================================
module if_id_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,
  input  wire        wist,
  input  wire [31:0] pc_in,
  input  wire [31:0] inst_in,
  input  wire [1:0]  tid_in,
  output reg  [31:0] pc_out,
  output reg  [31:0] inst_out,
  output reg  [1:0]  tid_out,
  output reg         wist_out
);

  always @(posedge clk) begin
    if (rst) begin
      pc_out   <= 32'd0;
      inst_out <= 32'd0;
      tid_out  <= 2'd0;
      wist_out <= 1'b0;
    end else if (enable) begin
      pc_out   <= pc_in;
      inst_out <= inst_in;
      tid_out  <= tid_in;
      wist_out <= wist;
    end
  end

endmodule


// ============================================================
// 4-thread register file (32 regs per thread)
// ============================================================
module reg_files_4thread(
  input  wire        clk,
  input  wire        rst,
  input  wire [1:0]  tid_r,
  input  wire [4:0]  rs1_addr,
  input  wire [4:0]  rs2_addr,
  input  wire [1:0]  tid_w,
  input  wire [4:0]  rd_addr,
  input  wire [31:0] wb_data,
  input  wire        wea,
  output wire [31:0] rd1,
  output wire [31:0] rd2
);

  reg [31:0] regs [0:127];
  integer i;

  wire [6:0] rbase;
  wire [6:0] wbase;
  assign rbase = {tid_r, 5'd0};
  assign wbase = {tid_w, 5'd0};

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < 128; i = i + 1) regs[i] <= 32'd0;
    end else begin
      if (wea && (rd_addr != 5'd0)) regs[wbase + rd_addr] <= wb_data;
      regs[wbase + 5'd0] <= 32'd0;
    end
  end

  // combinational reads with simple WB forwarding
  assign rd1 = (rs1_addr == 5'd0) ? 32'd0 :
               (wea && (tid_w == tid_r) && (rd_addr != 5'd0) && (rd_addr == rs1_addr)) ? wb_data :
               regs[rbase + rs1_addr];

  assign rd2 = (rs2_addr == 5'd0) ? 32'd0 :
               (wea && (tid_w == tid_r) && (rd_addr != 5'd0) && (rd_addr == rs2_addr)) ? wb_data :
               regs[rbase + rs2_addr];

endmodule


// ============================================================
// ID stage
// ============================================================
module id_stage(
  input  wire        clk,
  input  wire        rst,
  input  wire [31:0] pc_in,
  input  wire [31:0] inst_in,
  input  wire [1:0]  tid_in,
  input  wire [1:0]  wb_tid,
  input  wire [4:0]  wb_rd_addr,
  input  wire [31:0] wb_data,
  input  wire        wb_wea,
  input  wire        wist,
  output reg  [31:0] imm,
  output wire [31:0] addr_out,
  output wire        jump_valid,
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

  assign opcode   = inst_in[6:0];
  assign funct3   = inst_in[14:12];
  assign funct7   = inst_in[31:25];
  assign rs1_addr = inst_in[19:15];
  assign rs2_addr = inst_in[24:20];
  assign rd_addr  = inst_in[11:7];

  assign rd_out     = rd_addr;
  assign funct3_out = funct3;
  assign funct7_out = funct7;

  wire [31:0] rd1;
  wire [31:0] rd2;

  reg_files_4thread u_reg_files(
    .clk      (clk),
    .rst      (rst),
    .tid_r    (tid_in),
    .rs1_addr (rs1_addr),
    .rs2_addr (rs2_addr),
    .tid_w    (wb_tid),
    .rd_addr  (wb_rd_addr),
    .wb_data  (wb_data),
    .wea      (wb_wea),
    .rd1      (rd1),
    .rd2      (rd2)
  );

  assign rd1_out = rd1;

  wire is_lui;
  wire is_auipc;
  wire is_b;
  wire is_jal;
  wire is_jalr;

  assign is_lui   = (opcode == 7'b0110111);
  assign is_auipc = (opcode == 7'b0010111);
  assign is_b     = (opcode == 7'b1100011);
  assign is_jal   = (opcode == 7'b1101111);
  assign is_jalr  = (opcode == 7'b1100111) && (funct3 == 3'b000);

  assign jal_jalr = is_jal | is_jalr | is_lui | is_auipc;

  wire [31:0] pc_plus4;
  assign pc_plus4 = pc_in + 32'd4;

  wire [31:0] auipc_val;
  assign auipc_val = pc_in + imm;

  assign rd2_out = (is_jal | is_jalr) ? pc_plus4 :
                   is_auipc ? auipc_val :
                   is_lui   ? imm :
                   rd2;

  // branches
  wire eq, lt_s, ge_s, lt_u, ge_u;
  assign eq   = (rd1 == rd2);
  assign lt_s = ($signed(rd1) <  $signed(rd2));
  assign ge_s = ($signed(rd1) >= $signed(rd2));
  assign lt_u = (rd1 <  rd2);
  assign ge_u = (rd1 >= rd2);

  reg b_take;
  always @(*) begin
    b_take = 1'b0;
    if (is_b) begin
      case (funct3)
        3'b000: b_take = eq;    // beq
        3'b001: b_take = ~eq;   // bne
        3'b100: b_take = lt_s;  // blt
        3'b101: b_take = ge_s;  // bge
        3'b110: b_take = lt_u;  // bltu
        3'b111: b_take = ge_u;  // bgeu
        default: b_take = 1'b0;
      endcase
    end
  end

  wire jump_valid_int;
  assign jump_valid_int = b_take | is_jal | is_jalr;

  // immediates (RISC-V style, with LSB 0 for B/J)
  always @(*) begin
    case (opcode)
      7'b0010011: imm = {{20{inst_in[31]}}, inst_in[31:20]};
      7'b0000011: imm = {{20{inst_in[31]}}, inst_in[31:20]};
      7'b1100111: imm = {{20{inst_in[31]}}, inst_in[31:20]};
      7'b0100011: imm = {{20{inst_in[31]}}, inst_in[31:25], inst_in[11:7]};
      7'b1100011: imm = {{19{inst_in[31]}}, inst_in[31], inst_in[7], inst_in[30:25], inst_in[11:8], 1'b0};
      7'b1101111: imm = {{11{inst_in[31]}}, inst_in[31], inst_in[19:12], inst_in[20], inst_in[30:21], 1'b0};
      7'b0110111: imm = {inst_in[31:12], 12'b0};
      7'b0010111: imm = {inst_in[31:12], 12'b0};
      default:    imm = 32'd0;
    endcase
  end

  wire [31:0] base32;
  assign base32   = is_jalr ? rd1 : pc_in;
  assign addr_out = base32 + imm;

  assign ALUsrc = (opcode == 7'b0010011) | (opcode == 7'b0000011) | (opcode == 7'b0100011);

  wire WMM_int, RMM_int, MOA_int, wreg_int;
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


// ============================================================
// ID/EX pipeline register (with tid)
// ============================================================
module id_ex_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,
  input  wire [1:0]  tid_in,
  input  wire [31:0] IMM,
  input  wire        wreg,
  input  wire [31:0] rd2,
  input  wire [31:0] rd1,
  input  wire [4:0]  rd,
  input  wire [2:0]  func3,
  input  wire [6:0]  func7,
  input  wire        ALUsrc,
  input  wire        WMM,
  input  wire        RMM,
  input  wire        MOA,
  input  wire        jal_jalr,
  output reg  [1:0]  tid_out,
  output reg  [31:0] IMM_out,
  output reg         wreg_out,
  output reg  [31:0] rd2_out,
  output reg  [31:0] rd1_out,
  output reg  [4:0]  rd_out,
  output reg  [2:0]  func3_out,
  output reg  [6:0]  func7_out,
  output reg         ALUsrc_out,
  output reg         WMM_out,
  output reg         RMM_out,
  output reg         MOA_out,
  output reg         jal_jalr_out
);

  always @(posedge clk) begin
    if (rst) begin
      tid_out      <= 2'd0;
      IMM_out      <= 32'd0;
      wreg_out     <= 1'b0;
      rd2_out      <= 32'd0;
      rd1_out      <= 32'd0;
      rd_out       <= 5'd0;
      func3_out    <= 3'd0;
      func7_out    <= 7'd0;
      ALUsrc_out   <= 1'b0;
      WMM_out      <= 1'b0;
      RMM_out      <= 1'b0;
      MOA_out      <= 1'b0;
      jal_jalr_out <= 1'b0;
    end else if (enable) begin
      tid_out      <= tid_in;
      IMM_out      <= IMM;
      wreg_out     <= wreg;
      rd2_out      <= rd2;
      rd1_out      <= rd1;
      rd_out       <= rd;
      func3_out    <= func3;
      func7_out    <= func7;
      ALUsrc_out   <= ALUsrc;
      WMM_out      <= WMM;
      RMM_out      <= RMM;
      MOA_out      <= MOA;
      jal_jalr_out <= jal_jalr;
    end
  end

endmodule


// ============================================================
// EX stage (with tid passthrough)
// ============================================================
module ex_stage(
  input  wire [1:0]  tid_in,
  input  wire [31:0] IMM_in,
  input  wire        wreg_in,
  input  wire [31:0] rd2_in,
  input  wire [31:0] rd1_in,
  input  wire [4:0]  rd_in,
  input  wire [2:0]  func3_in,
  input  wire [6:0]  func7_in,
  input  wire        ALUsrc_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,
  output wire [1:0]  tid_out,
  output wire [31:0] alu_out,
  output wire [31:0] rd2_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        WMM_out,
  output wire        RMM_out,
  output wire        MOA_out,
  output wire        jal_jalr_out
);

  assign tid_out = tid_in;

  wire [31:0] b_sel;
  assign b_sel = ALUsrc_in ? IMM_in : rd2_in;

  wire add_force;
  assign add_force = WMM_in | RMM_in;

  wire zero_unused, lt_unused, ltu_unused;
  alu u_alu(
    .a         (rd1_in),
    .b         (b_sel),
    .func3     (func3_in),
    .func7     (func7_in),
    .add_force (add_force),
    .is_imm    (ALUsrc_in),
    .y         (alu_out),
    .zero      (zero_unused),
    .lt        (lt_unused),
    .ltu       (ltu_unused)
  );

  assign rd2_out      = rd2_in;
  assign wreg_out     = wreg_in;
  assign rd_out       = rd_in;
  assign WMM_out      = WMM_in;
  assign RMM_out      = RMM_in;
  assign MOA_out      = MOA_in;
  assign jal_jalr_out = jal_jalr_in;

endmodule


// ============================================================
// EX/MEM pipeline register (with tid)
// ============================================================
module ex_mm_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,
  input  wire [1:0]  tid_in,
  input  wire [31:0] alu_in,
  input  wire [31:0] rd2_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,
  output reg  [1:0]  tid_out,
  output reg  [31:0] alu_out,
  output reg  [31:0] rd2_out,
  output reg         wreg_out,
  output reg  [4:0]  rd_out,
  output reg         WMM_out,
  output reg         RMM_out,
  output reg         MOA_out,
  output reg         jal_jalr_out
);

  always @(posedge clk) begin
    if (rst) begin
      tid_out      <= 2'd0;
      alu_out      <= 32'd0;
      rd2_out      <= 32'd0;
      wreg_out     <= 1'b0;
      rd_out       <= 5'd0;
      WMM_out      <= 1'b0;
      RMM_out      <= 1'b0;
      MOA_out      <= 1'b0;
      jal_jalr_out <= 1'b0;
    end else if (enable) begin
      tid_out      <= tid_in;
      alu_out      <= alu_in;
      rd2_out      <= rd2_in;
      wreg_out     <= wreg_in;
      rd_out       <= rd_in;
      WMM_out      <= WMM_in;
      RMM_out      <= RMM_in;
      MOA_out      <= MOA_in;
      jal_jalr_out <= jal_jalr_in;
    end
  end

endmodule


// ============================================================
// MEM stage (with tid -> per-thread D$ banked by address high bits)
// ============================================================
module mm_stage(
  input  wire        clk,
  input  wire [1:0]  tid_in,
  input  wire [31:0] alu_in,   // byte address for D$
  input  wire [31:0] rd2_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        WMM_in,
  input  wire        RMM_in,
  input  wire        MOA_in,
  input  wire        jal_jalr_in,
  output wire [1:0]  tid_out,
  output wire [31:0] alu_out,
  output wire [31:0] mem_out,
  output wire        wreg_out,
  output wire [4:0]  rd_out,
  output wire        MOA_out
);

  assign tid_out = tid_in;

  assign alu_out  = jal_jalr_in ? rd2_in : alu_in;
  assign wreg_out = wreg_in;
  assign rd_out   = rd_in;
  assign MOA_out  = MOA_in;

  Dcache_4thread Dmm(
    .tid_r (tid_in),
    .tid_w (tid_in),
    .addra (alu_in),
    .addrb (alu_in),
    .clka  (clk),
    .clkb  (clk),
    .dinb  (rd2_in),
    .douta (mem_out),
    .ena   (RMM_in),
    .enb   (WMM_in),
    .web   (WMM_in)
  );

endmodule


// ============================================================
// MEM/WB pipeline register (with tid)
// ============================================================
module mm_wb_reg(
  input  wire        clk,
  input  wire        rst,
  input  wire        enable,
  input  wire [1:0]  tid_in,
  input  wire [31:0] alu_in,
  input  wire [31:0] mem_in,
  input  wire        wreg_in,
  input  wire [4:0]  rd_in,
  input  wire        MOA_in,
  output reg  [1:0]  tid_out,
  output reg  [31:0] alu_out,
  output reg  [31:0] mem_out,
  output reg         wreg_out,
  output reg  [4:0]  rd_out,
  output reg         MOA_out
);

  always @(posedge clk) begin
    if (rst) begin
      tid_out  <= 2'd0;
      alu_out  <= 32'd0;
      mem_out  <= 32'd0;
      wreg_out <= 1'b0;
      rd_out   <= 5'd0;
      MOA_out  <= 1'b0;
    end else if (enable) begin
      tid_out  <= tid_in;
      alu_out  <= alu_in;
      mem_out  <= mem_in;
      wreg_out <= wreg_in;
      rd_out   <= rd_in;
      MOA_out  <= MOA_in;
    end
  end

endmodule


// ============================================================
// WB stage
// ============================================================
module wb_stage(
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
  assign wreg_out    = wreg_in;
  assign rd_out      = rd_in;

endmodule


// ============================================================
// ALU
// ============================================================
module alu(
  input  wire [31:0] a,
  input  wire [31:0] b,
  input  wire [2:0]  func3,
  input  wire [6:0]  func7,
  input  wire        add_force,
  input  wire        is_imm,
  output reg  [31:0] y,
  output wire        zero,
  output wire        lt,
  output wire        ltu
);

  wire sub_sra;
  assign sub_sra = func7[5];

  wire [4:0] shamt;
  assign shamt = b[4:0];

  assign zero = (a == b);
  assign lt   = ($signed(a) < $signed(b));
  assign ltu  = (a < b);

  wire [31:0] srl_val;
  assign srl_val = a >> shamt;

  wire [31:0] sra_val;
  assign sra_val = (shamt == 5'd0) ? a :
                   (srl_val | ({32{a[31]}} << (32 - shamt)));

  always @(*) begin
    y = 32'd0;
    if (add_force) begin
      y = a + b;
    end else if (is_imm) begin
      case (func3)
        3'b000: y = a + b;
        3'b010: y = lt  ? 32'd1 : 32'd0;
        3'b011: y = ltu ? 32'd1 : 32'd0;
        3'b100: y = a ^ b;
        3'b110: y = a | b;
        3'b111: y = a & b;
        3'b001: y = (func7[5] == 1'b0) ? (a << shamt) : 32'd0;
        3'b101: y = sub_sra ? sra_val : srl_val;
        default: y = 32'd0;
      endcase
    end else begin
      case (func3)
        3'b000: y = sub_sra ? (a - b) : (a + b);
        3'b001: y = a << shamt;
        3'b010: y = lt  ? 32'd1 : 32'd0;
        3'b011: y = ltu ? 32'd1 : 32'd0;
        3'b100: y = a ^ b;
        3'b101: y = sub_sra ? sra_val : srl_val;
        3'b110: y = a | b;
        3'b111: y = a & b;
        default: y = 32'd0;
      endcase
    end
  end

endmodule


// ============================================================
// 4-thread Dcache: 512 words total, each thread gets 64 words.
// Address input is byte address; internally uses addr[10:2] as word index.
// ============================================================
module Dcache_4thread(
  input  wire [1:0]  tid_r,
  input  wire [1:0]  tid_w,
  input  wire [31:0] addra,
  input  wire [31:0] addrb,
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

  wire [8:0] wa;
  wire [8:0] wb;
  assign wa = addra[10:2];
  assign wb = addrb[10:2];

  wire [8:0] seg_r;
  wire [8:0] seg_w;
  assign seg_r = {tid_r, 6'd0};
  assign seg_w = {tid_w, 6'd0};

  wire [8:0] idx_r;
  wire [8:0] idx_w;
  assign idx_r = seg_r + wa[5:0];
  assign idx_w = seg_w + wb[5:0];

  initial begin
    for (j = 0; j < 512; j = j + 1) mem[j] = 32'h00000000;
`ifdef DCACHE_INIT_FILE
    $readmemh(`DCACHE_INIT_FILE, mem);
`endif
  end

  assign douta = ena ? mem[idx_r] : 32'd0;

  always @(posedge clkb) begin
    if (enb && web) mem[idx_w] <= dinb;
  end

endmodule


// ============================================================
// Icache: 512 words, word addressed.
// ============================================================
module Icache(
  input  wire        clk,
  input  wire [8:0]  addr,
  input  wire [31:0] din,
  output wire [31:0] dout,
  input  wire        we
);

  reg [31:0] mem [0:511];
  integer i;

  initial begin
    for (i = 0; i < 512; i = i + 1) mem[i] = 32'h00000013; // NOP
`ifdef ICACHE_INIT_FILE
    $readmemh(`ICACHE_INIT_FILE, mem);
`endif
  end

  assign dout = mem[addr];

  always @(posedge clk) begin
    if (we) mem[addr] <= din;
  end

endmodule
