`timescale 1ns/1ps

module tb_pipeline_datapath;

parameter CLK_PERIOD    = 10;
parameter MAX_CYCLES    = 50000;
parameter TRACE_FIRST_N = 200;

// ============================================================
// 修正点1: ARR_LEN 改为 6（汇编中 li a3,6 即 n=6）
// 修正点2: RESULT_WORD 改为 179（s0-48 = 764-48 = 716 byte = word179）
// ============================================================
parameter ARR_LEN      = 6;
parameter RODATA_WORD  = 256;
parameter RESULT_WORD  = 179;   // ← 原来是 180，偏移了 1 个元素

localparam [10:0] HALT_BYTE_PC = 11'd1044;

localparam integer TOHOST_CODE_WORD = 510;
localparam integer TOHOST_DONE_WORD = 511;

reg clk, rst;

pipeline_datapath dut (
  .clk(clk),
  .rst(rst)
);

initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

integer cycle_cnt;
initial cycle_cnt = 0;
always @(posedge clk) cycle_cnt = cycle_cnt + 1;

integer i, k, cyc;

reg [31:0] input_snapshot [0:ARR_LEN-1];
reg [31:0] last_res [0:ARR_LEN-1];

reg [31:0] last_tohost_code, last_tohost_done;

reg halt_detected;
reg [31:0] stop_reason;

integer sorted_fail;
integer perm_fail;
integer exact_fail;

reg [31:0] if_instr;
integer if_idx;

task init_last_res;
begin
  for (i = 0; i < ARR_LEN; i = i + 1)
    last_res[i] = 32'hxxxxxxxx;
end
endtask

task dump_regs;
begin
  $display("--- REGS (cycle=%0d) ---", cycle_cnt);
  $display("x1  ra = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[1],  $signed(dut.id_stage_inst.u_reg_files.regs[1]));
  $display("x2  sp = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[2],  $signed(dut.id_stage_inst.u_reg_files.regs[2]));
  $display("x8  s0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[8],  $signed(dut.id_stage_inst.u_reg_files.regs[8]));
  $display("x10 a0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[10], $signed(dut.id_stage_inst.u_reg_files.regs[10]));
end
endtask

task show_tohost;
reg [31:0] code, done;
begin
  code = dut.mm_stage_inst.Dmm.mem[TOHOST_CODE_WORD];
  done = dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD];
  $display("tohost: code=0x%08h done=0x%08h", code, done);
end
endtask

task snapshot_input;
begin
  // 修正点3: 快照范围覆盖全部 ARR_LEN=6 个元素（word256..261）
  for (i = 0; i < ARR_LEN; i = i + 1)
    input_snapshot[i] = dut.mm_stage_inst.Dmm.mem[RODATA_WORD + i];
  $display("[SNAPSHOT] input @ rodata word%0d..%0d captured",
           RODATA_WORD, RODATA_WORD+ARR_LEN-1);
end
endtask

task dump_result;
begin
  $display("idx | word | value");
  for (i = 0; i < ARR_LEN; i = i + 1)
    $display("%0d   | %0d  | %0d",
             i, RESULT_WORD+i,
             $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+i]));
end
endtask

task check_sorted;
reg signed [31:0] cur, nxt;
begin
  sorted_fail = 0;
  for (k = 0; k < ARR_LEN-1; k = k + 1) begin
    cur = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+k]);
    nxt = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+k+1]);
    if (cur > nxt) begin
      $display("[SORTED FAIL] result[%0d]=%0d > result[%0d]=%0d",
               k, cur, k+1, nxt);
      sorted_fail = sorted_fail + 1;
    end
  end
end
endtask

task check_permutation;
integer j;
reg signed [31:0] val;
integer cnt_in, cnt_out;
begin
  perm_fail = 0;
  for (j = 0; j < ARR_LEN; j = j + 1) begin
    val = $signed(input_snapshot[j]);
    cnt_in = 0;
    cnt_out = 0;
    for (k = 0; k < ARR_LEN; k = k + 1) begin
      if ($signed(input_snapshot[k]) === val) cnt_in = cnt_in + 1;
      if ($signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+k]) === val) cnt_out = cnt_out + 1;
    end
    if (cnt_in !== cnt_out) begin
      $display("[PERM FAIL] val=%0d appears %0d times in input, %0d times in output",
               val, cnt_in, cnt_out);
      perm_fail = perm_fail + 1;
    end
  end
end
endtask

// ============================================================
// 修正点4: 期望值改为 {-1,2,4,5,8,10}（对应输入{5,-1,2,4,10,8}排序结果）
// ============================================================
task check_expected_exact;
reg signed [31:0] v0, v1, v2, v3, v4, v5;
begin
  exact_fail = 0;
  v0 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+0]);
  v1 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+1]);
  v2 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+2]);
  v3 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+3]);
  v4 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+4]);
  v5 = $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+5]);

  if (v0 !== -1) begin $display("[EXACT FAIL] result[0] expect -1, got %0d", v0); exact_fail = exact_fail + 1; end
  if (v1 !==  2) begin $display("[EXACT FAIL] result[1] expect  2, got %0d", v1); exact_fail = exact_fail + 1; end
  if (v2 !==  4) begin $display("[EXACT FAIL] result[2] expect  4, got %0d", v2); exact_fail = exact_fail + 1; end
  if (v3 !==  5) begin $display("[EXACT FAIL] result[3] expect  5, got %0d", v3); exact_fail = exact_fail + 1; end
  if (v4 !==  8) begin $display("[EXACT FAIL] result[4] expect  8, got %0d", v4); exact_fail = exact_fail + 1; end
  if (v5 !== 10) begin $display("[EXACT FAIL] result[5] expect 10, got %0d", v5); exact_fail = exact_fail + 1; end
end
endtask

// ==========================================================
// Auto-generated by rv32i_asm.py
// Source : Selectsort_rv32i_gen.s
// Insts  : 88   Slots: 264
// HALT byte PC = 1044
// STACK_TOP    = 0x0300 = 768
// RODATA_BASE  = 0x0400 → Dcache word 256
// Array byte addr: s0-48 = 764-48 = 716 → Dcache word 179
// Result: word179 .. 184  (6 elements)
// ==========================================================

// ==========================================================
// Auto-generated by rv32i_asm.py
// Source : selsort_rv32i_gen.s
// Insts  : 93   Slots: 279
// HALT byte PC = 1104  (slot 276)
// STACK_TOP    = 0x0300 = 768
// RODATA_BASE  = 0x0400 → Dcache word 256
// Array result (bubble sort): arr_base≈0x02D0 → Dcache word 180..185
// ==========================================================

task load_icache;
integer _ki;
begin
    for (_ki = 0; _ki < 512; _ki = _ki + 1)
        dut.Imm.mem[_ki] = 32'h00000013; // NOP

    dut.Imm.mem[  0] = 32'h30000113; // addi sp,x0,768
    dut.Imm.mem[  1] = 32'h00000013; // NOP
    dut.Imm.mem[  2] = 32'h00000013; // NOP
    // ── <main> (byte 12) ──
    dut.Imm.mem[  3] = 32'hFF810113; // addi sp,sp,-8
    dut.Imm.mem[  4] = 32'h00000013; // NOP
    dut.Imm.mem[  5] = 32'h00000013; // NOP
    dut.Imm.mem[  6] = 32'h00812023; // sw s0,0(sp)
    dut.Imm.mem[  7] = 32'h00000013; // NOP
    dut.Imm.mem[  8] = 32'h00000013; // NOP
    dut.Imm.mem[  9] = 32'h00112223; // sw ra,4(sp)
    dut.Imm.mem[ 10] = 32'h00000013; // NOP
    dut.Imm.mem[ 11] = 32'h00000013; // NOP
    dut.Imm.mem[ 12] = 32'h00410413; // addi s0,sp,4
    dut.Imm.mem[ 13] = 32'h00000013; // NOP
    dut.Imm.mem[ 14] = 32'h00000013; // NOP
    dut.Imm.mem[ 15] = 32'hFD010113; // addi sp,sp,-48
    dut.Imm.mem[ 16] = 32'h00000013; // NOP
    dut.Imm.mem[ 17] = 32'h00000013; // NOP
    dut.Imm.mem[ 18] = 32'h000006B7; // lui a3,%hi(.LC0)
    dut.Imm.mem[ 19] = 32'h00000013; // NOP
    dut.Imm.mem[ 20] = 32'h00000013; // NOP
    dut.Imm.mem[ 21] = 32'h40068693; // addi a3,a3,%lo(.LC0)
    dut.Imm.mem[ 22] = 32'h00000013; // NOP
    dut.Imm.mem[ 23] = 32'h00000013; // NOP
    dut.Imm.mem[ 24] = 32'hFD040293; // addi t0,s0,-48
    dut.Imm.mem[ 25] = 32'h00000013; // NOP
    dut.Imm.mem[ 26] = 32'h00000013; // NOP
    dut.Imm.mem[ 27] = 32'h00068093; // mv ra,a3
    dut.Imm.mem[ 28] = 32'h00000013; // NOP
    dut.Imm.mem[ 29] = 32'h00000013; // NOP
    dut.Imm.mem[ 30] = 32'h0000A503; // lw a0,0(ra)
    dut.Imm.mem[ 31] = 32'h00000013; // NOP
    dut.Imm.mem[ 32] = 32'h00000013; // NOP
    dut.Imm.mem[ 33] = 32'h0040A583; // lw a1,4(ra)
    dut.Imm.mem[ 34] = 32'h00000013; // NOP
    dut.Imm.mem[ 35] = 32'h00000013; // NOP
    dut.Imm.mem[ 36] = 32'h0080A603; // lw a2,8(ra)
    dut.Imm.mem[ 37] = 32'h00000013; // NOP
    dut.Imm.mem[ 38] = 32'h00000013; // NOP
    dut.Imm.mem[ 39] = 32'h00C0A683; // lw a3,12(ra)
    dut.Imm.mem[ 40] = 32'h00000013; // NOP
    dut.Imm.mem[ 41] = 32'h00000013; // NOP
    dut.Imm.mem[ 42] = 32'h01008093; // addi ra,ra,16
    dut.Imm.mem[ 43] = 32'h00000013; // NOP
    dut.Imm.mem[ 44] = 32'h00000013; // NOP
    dut.Imm.mem[ 45] = 32'h00A2A023; // sw a0,0(t0)
    dut.Imm.mem[ 46] = 32'h00000013; // NOP
    dut.Imm.mem[ 47] = 32'h00000013; // NOP
    dut.Imm.mem[ 48] = 32'h00B2A223; // sw a1,4(t0)
    dut.Imm.mem[ 49] = 32'h00000013; // NOP
    dut.Imm.mem[ 50] = 32'h00000013; // NOP
    dut.Imm.mem[ 51] = 32'h00C2A423; // sw a2,8(t0)
    dut.Imm.mem[ 52] = 32'h00000013; // NOP
    dut.Imm.mem[ 53] = 32'h00000013; // NOP
    dut.Imm.mem[ 54] = 32'h00D2A623; // sw a3,12(t0)
    dut.Imm.mem[ 55] = 32'h00000013; // NOP
    dut.Imm.mem[ 56] = 32'h00000013; // NOP
    dut.Imm.mem[ 57] = 32'h01028293; // addi t0,t0,16
    dut.Imm.mem[ 58] = 32'h00000013; // NOP
    dut.Imm.mem[ 59] = 32'h00000013; // NOP
    dut.Imm.mem[ 60] = 32'h0000A503; // lw a0,0(ra)
    dut.Imm.mem[ 61] = 32'h00000013; // NOP
    dut.Imm.mem[ 62] = 32'h00000013; // NOP
    dut.Imm.mem[ 63] = 32'h0040A583; // lw a1,4(ra)
    dut.Imm.mem[ 64] = 32'h00000013; // NOP
    dut.Imm.mem[ 65] = 32'h00000013; // NOP
    dut.Imm.mem[ 66] = 32'h00A2A023; // sw a0,0(t0)
    dut.Imm.mem[ 67] = 32'h00000013; // NOP
    dut.Imm.mem[ 68] = 32'h00000013; // NOP
    dut.Imm.mem[ 69] = 32'h00B2A223; // sw a1,4(t0)
    dut.Imm.mem[ 70] = 32'h00000013; // NOP
    dut.Imm.mem[ 71] = 32'h00000013; // NOP
    dut.Imm.mem[ 72] = 32'h00600693; // li a3,6
    dut.Imm.mem[ 73] = 32'h00000013; // NOP
    dut.Imm.mem[ 74] = 32'h00000013; // NOP
    dut.Imm.mem[ 75] = 32'hFED42623; // sw a3,-20(s0)
    dut.Imm.mem[ 76] = 32'h00000013; // NOP
    dut.Imm.mem[ 77] = 32'h00000013; // NOP
    dut.Imm.mem[ 78] = 32'h00000693; // li a3,0
    dut.Imm.mem[ 79] = 32'h00000013; // NOP
    dut.Imm.mem[ 80] = 32'h00000013; // NOP
    dut.Imm.mem[ 81] = 32'hFED42C23; // sw a3,-8(s0)
    dut.Imm.mem[ 82] = 32'h00000013; // NOP
    dut.Imm.mem[ 83] = 32'h00000013; // NOP
    dut.Imm.mem[ 84] = 32'h2880006F; // j .L2
    dut.Imm.mem[ 85] = 32'h00000013; // NOP
    dut.Imm.mem[ 86] = 32'h00000013; // NOP
    // ── <.L7> (byte 348) ──
    dut.Imm.mem[ 87] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[ 88] = 32'h00000013; // NOP
    dut.Imm.mem[ 89] = 32'h00000013; // NOP
    dut.Imm.mem[ 90] = 32'hFED42823; // sw a3,-16(s0)
    dut.Imm.mem[ 91] = 32'h00000013; // NOP
    dut.Imm.mem[ 92] = 32'h00000013; // NOP
    dut.Imm.mem[ 93] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[ 94] = 32'h00000013; // NOP
    dut.Imm.mem[ 95] = 32'h00000013; // NOP
    dut.Imm.mem[ 96] = 32'h00168693; // addi a3,a3,1
    dut.Imm.mem[ 97] = 32'h00000013; // NOP
    dut.Imm.mem[ 98] = 32'h00000013; // NOP
    dut.Imm.mem[ 99] = 32'hFED42A23; // sw a3,-12(s0)
    dut.Imm.mem[100] = 32'h00000013; // NOP
    dut.Imm.mem[101] = 32'h00000013; // NOP
    dut.Imm.mem[102] = 32'h0CC0006F; // j .L3
    dut.Imm.mem[103] = 32'h00000013; // NOP
    dut.Imm.mem[104] = 32'h00000013; // NOP
    // ── <.L5> (byte 420) ──
    dut.Imm.mem[105] = 32'hFF442683; // lw a3,-12(s0)
    dut.Imm.mem[106] = 32'h00000013; // NOP
    dut.Imm.mem[107] = 32'h00000013; // NOP
    dut.Imm.mem[108] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[109] = 32'h00000013; // NOP
    dut.Imm.mem[110] = 32'h00000013; // NOP
    dut.Imm.mem[111] = 32'hFFC40613; // addi a2,s0,-4
    dut.Imm.mem[112] = 32'h00000013; // NOP
    dut.Imm.mem[113] = 32'h00000013; // NOP
    dut.Imm.mem[114] = 32'h00D606B3; // add a3,a2,a3
    dut.Imm.mem[115] = 32'h00000013; // NOP
    dut.Imm.mem[116] = 32'h00000013; // NOP
    dut.Imm.mem[117] = 32'hFD46A603; // lw a2,-44(a3)
    dut.Imm.mem[118] = 32'h00000013; // NOP
    dut.Imm.mem[119] = 32'h00000013; // NOP
    dut.Imm.mem[120] = 32'hFF042683; // lw a3,-16(s0)
    dut.Imm.mem[121] = 32'h00000013; // NOP
    dut.Imm.mem[122] = 32'h00000013; // NOP
    dut.Imm.mem[123] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[124] = 32'h00000013; // NOP
    dut.Imm.mem[125] = 32'h00000013; // NOP
    dut.Imm.mem[126] = 32'hFFC40593; // addi a1,s0,-4
    dut.Imm.mem[127] = 32'h00000013; // NOP
    dut.Imm.mem[128] = 32'h00000013; // NOP
    dut.Imm.mem[129] = 32'h00D586B3; // add a3,a1,a3
    dut.Imm.mem[130] = 32'h00000013; // NOP
    dut.Imm.mem[131] = 32'h00000013; // NOP
    dut.Imm.mem[132] = 32'hFD46A683; // lw a3,-44(a3)
    dut.Imm.mem[133] = 32'h00000013; // NOP
    dut.Imm.mem[134] = 32'h00000013; // NOP
    dut.Imm.mem[135] = 32'h02D65263; // bge a2,a3,.L4
    dut.Imm.mem[136] = 32'h00000013; // NOP
    dut.Imm.mem[137] = 32'h00000013; // NOP
    dut.Imm.mem[138] = 32'hFF442683; // lw a3,-12(s0)
    dut.Imm.mem[139] = 32'h00000013; // NOP
    dut.Imm.mem[140] = 32'h00000013; // NOP
    dut.Imm.mem[141] = 32'hFED42823; // sw a3,-16(s0)
    dut.Imm.mem[142] = 32'h00000013; // NOP
    dut.Imm.mem[143] = 32'h00000013; // NOP
    // ── <.L4> (byte 576) ──
    dut.Imm.mem[144] = 32'hFF442683; // lw a3,-12(s0)
    dut.Imm.mem[145] = 32'h00000013; // NOP
    dut.Imm.mem[146] = 32'h00000013; // NOP
    dut.Imm.mem[147] = 32'h00168693; // addi a3,a3,1
    dut.Imm.mem[148] = 32'h00000013; // NOP
    dut.Imm.mem[149] = 32'h00000013; // NOP
    dut.Imm.mem[150] = 32'hFED42A23; // sw a3,-12(s0)
    dut.Imm.mem[151] = 32'h00000013; // NOP
    dut.Imm.mem[152] = 32'h00000013; // NOP
    // ── <.L3> (byte 612) ──
    dut.Imm.mem[153] = 32'hFF442603; // lw a2,-12(s0)
    dut.Imm.mem[154] = 32'h00000013; // NOP
    dut.Imm.mem[155] = 32'h00000013; // NOP
    dut.Imm.mem[156] = 32'hFEC42683; // lw a3,-20(s0)
    dut.Imm.mem[157] = 32'h00000013; // NOP
    dut.Imm.mem[158] = 32'h00000013; // NOP
    dut.Imm.mem[159] = 32'hF2D644E3; // blt a2,a3,.L5
    dut.Imm.mem[160] = 32'h00000013; // NOP
    dut.Imm.mem[161] = 32'h00000013; // NOP
    dut.Imm.mem[162] = 32'hFF042603; // lw a2,-16(s0)
    dut.Imm.mem[163] = 32'h00000013; // NOP
    dut.Imm.mem[164] = 32'h00000013; // NOP
    dut.Imm.mem[165] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[166] = 32'h00000013; // NOP
    dut.Imm.mem[167] = 32'h00000013; // NOP
    dut.Imm.mem[168] = 32'h10D60A63; // beq a2,a3,.L6
    dut.Imm.mem[169] = 32'h00000013; // NOP
    dut.Imm.mem[170] = 32'h00000013; // NOP
    dut.Imm.mem[171] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[172] = 32'h00000013; // NOP
    dut.Imm.mem[173] = 32'h00000013; // NOP
    dut.Imm.mem[174] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[175] = 32'h00000013; // NOP
    dut.Imm.mem[176] = 32'h00000013; // NOP
    dut.Imm.mem[177] = 32'hFFC40613; // addi a2,s0,-4
    dut.Imm.mem[178] = 32'h00000013; // NOP
    dut.Imm.mem[179] = 32'h00000013; // NOP
    dut.Imm.mem[180] = 32'h00D606B3; // add a3,a2,a3
    dut.Imm.mem[181] = 32'h00000013; // NOP
    dut.Imm.mem[182] = 32'h00000013; // NOP
    dut.Imm.mem[183] = 32'hFD46A683; // lw a3,-44(a3)
    dut.Imm.mem[184] = 32'h00000013; // NOP
    dut.Imm.mem[185] = 32'h00000013; // NOP
    dut.Imm.mem[186] = 32'hFED42423; // sw a3,-24(s0)
    dut.Imm.mem[187] = 32'h00000013; // NOP
    dut.Imm.mem[188] = 32'h00000013; // NOP
    dut.Imm.mem[189] = 32'hFF042683; // lw a3,-16(s0)
    dut.Imm.mem[190] = 32'h00000013; // NOP
    dut.Imm.mem[191] = 32'h00000013; // NOP
    dut.Imm.mem[192] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[193] = 32'h00000013; // NOP
    dut.Imm.mem[194] = 32'h00000013; // NOP
    dut.Imm.mem[195] = 32'hFFC40613; // addi a2,s0,-4
    dut.Imm.mem[196] = 32'h00000013; // NOP
    dut.Imm.mem[197] = 32'h00000013; // NOP
    dut.Imm.mem[198] = 32'h00D606B3; // add a3,a2,a3
    dut.Imm.mem[199] = 32'h00000013; // NOP
    dut.Imm.mem[200] = 32'h00000013; // NOP
    dut.Imm.mem[201] = 32'hFD46A603; // lw a2,-44(a3)
    dut.Imm.mem[202] = 32'h00000013; // NOP
    dut.Imm.mem[203] = 32'h00000013; // NOP
    dut.Imm.mem[204] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[205] = 32'h00000013; // NOP
    dut.Imm.mem[206] = 32'h00000013; // NOP
    dut.Imm.mem[207] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[208] = 32'h00000013; // NOP
    dut.Imm.mem[209] = 32'h00000013; // NOP
    dut.Imm.mem[210] = 32'hFFC40593; // addi a1,s0,-4
    dut.Imm.mem[211] = 32'h00000013; // NOP
    dut.Imm.mem[212] = 32'h00000013; // NOP
    dut.Imm.mem[213] = 32'h00D586B3; // add a3,a1,a3
    dut.Imm.mem[214] = 32'h00000013; // NOP
    dut.Imm.mem[215] = 32'h00000013; // NOP
    dut.Imm.mem[216] = 32'hFCC6AA23; // sw a2,-44(a3)
    dut.Imm.mem[217] = 32'h00000013; // NOP
    dut.Imm.mem[218] = 32'h00000013; // NOP
    dut.Imm.mem[219] = 32'hFF042683; // lw a3,-16(s0)
    dut.Imm.mem[220] = 32'h00000013; // NOP
    dut.Imm.mem[221] = 32'h00000013; // NOP
    dut.Imm.mem[222] = 32'h00269693; // slli a3,a3,2
    dut.Imm.mem[223] = 32'h00000013; // NOP
    dut.Imm.mem[224] = 32'h00000013; // NOP
    dut.Imm.mem[225] = 32'hFFC40613; // addi a2,s0,-4
    dut.Imm.mem[226] = 32'h00000013; // NOP
    dut.Imm.mem[227] = 32'h00000013; // NOP
    dut.Imm.mem[228] = 32'h00D606B3; // add a3,a2,a3
    dut.Imm.mem[229] = 32'h00000013; // NOP
    dut.Imm.mem[230] = 32'h00000013; // NOP
    dut.Imm.mem[231] = 32'hFE842603; // lw a2,-24(s0)
    dut.Imm.mem[232] = 32'h00000013; // NOP
    dut.Imm.mem[233] = 32'h00000013; // NOP
    dut.Imm.mem[234] = 32'hFCC6AA23; // sw a2,-44(a3)
    dut.Imm.mem[235] = 32'h00000013; // NOP
    dut.Imm.mem[236] = 32'h00000013; // NOP
    // ── <.L6> (byte 948) ──
    dut.Imm.mem[237] = 32'hFF842683; // lw a3,-8(s0)
    dut.Imm.mem[238] = 32'h00000013; // NOP
    dut.Imm.mem[239] = 32'h00000013; // NOP
    dut.Imm.mem[240] = 32'h00168693; // addi a3,a3,1
    dut.Imm.mem[241] = 32'h00000013; // NOP
    dut.Imm.mem[242] = 32'h00000013; // NOP
    dut.Imm.mem[243] = 32'hFED42C23; // sw a3,-8(s0)
    dut.Imm.mem[244] = 32'h00000013; // NOP
    dut.Imm.mem[245] = 32'h00000013; // NOP
    // ── <.L2> (byte 984) ──
    dut.Imm.mem[246] = 32'hFEC42683; // lw a3,-20(s0)
    dut.Imm.mem[247] = 32'h00000013; // NOP
    dut.Imm.mem[248] = 32'h00000013; // NOP
    dut.Imm.mem[249] = 32'hFFF68693; // addi a3,a3,-1
    dut.Imm.mem[250] = 32'h00000013; // NOP
    dut.Imm.mem[251] = 32'h00000013; // NOP
    dut.Imm.mem[252] = 32'hFF842603; // lw a2,-8(s0)
    dut.Imm.mem[253] = 32'h00000013; // NOP
    dut.Imm.mem[254] = 32'h00000013; // NOP
    dut.Imm.mem[255] = 32'hD6D640E3; // blt a2,a3,.L7
    dut.Imm.mem[256] = 32'h00000013; // NOP
    dut.Imm.mem[257] = 32'h00000013; // NOP
    dut.Imm.mem[258] = 32'h00000693; // li a3,0
    dut.Imm.mem[259] = 32'h00000013; // NOP
    dut.Imm.mem[260] = 32'h00000013; // NOP
    dut.Imm.mem[261] = 32'h00068513; // mv a0,a3
    dut.Imm.mem[262] = 32'h00000013; // NOP
    dut.Imm.mem[263] = 32'h00000013; // NOP
    dut.Imm.mem[264] = 32'hFFC40113; // addi sp,s0,-4
    dut.Imm.mem[265] = 32'h00000013; // NOP
    dut.Imm.mem[266] = 32'h00000013; // NOP
    dut.Imm.mem[267] = 32'h00012403; // lw s0,0(sp)
    dut.Imm.mem[268] = 32'h00000013; // NOP
    dut.Imm.mem[269] = 32'h00000013; // NOP
    dut.Imm.mem[270] = 32'h00412083; // lw ra,4(sp)
    dut.Imm.mem[271] = 32'h00000013; // NOP
    dut.Imm.mem[272] = 32'h00000013; // NOP
    dut.Imm.mem[273] = 32'h00810113; // addi sp,sp,8
    dut.Imm.mem[274] = 32'h00000013; // NOP
    dut.Imm.mem[275] = 32'h00000013; // NOP
    dut.Imm.mem[276] = 32'h00000063; // ret
    dut.Imm.mem[277] = 32'h00000013; // NOP
    dut.Imm.mem[278] = 32'h00000013; // NOP

    $display("[ICACHE] 93 insts, 279 slots, HALT byte PC=1104");
end
endtask

task load_dcache;
integer _kd;
begin
    for (_kd = 0; _kd < 512; _kd = _kd + 1)
        dut.mm_stage_inst.Dmm.mem[_kd] = 32'h00000000;

    // .rodata → Dcache word 256 起
    // ★ 修改测试输入请改这里 ★
    dut.mm_stage_inst.Dmm.mem[256] = 32'h00000005; // 5
    dut.mm_stage_inst.Dmm.mem[257] = 32'hFFFFFFFF; // -1
    dut.mm_stage_inst.Dmm.mem[258] = 32'h00000002; // 2
    dut.mm_stage_inst.Dmm.mem[259] = 32'h00000004; // 4
    dut.mm_stage_inst.Dmm.mem[260] = 32'h0000000A; // 10
    dut.mm_stage_inst.Dmm.mem[261] = 32'h00000008; // 8

    $display("[DCACHE] 数据预加载完成");
end
endtask

always @(posedge clk) begin
  if (!rst) begin
    if (cycle_cnt <= TRACE_FIRST_N) begin
      if_idx = dut.pc_if >> 2;
      if_instr = dut.Imm.mem[if_idx];
      $display("[cyc %0d] pc=%0d instr=0x%08h", cycle_cnt, dut.pc_if, if_instr);
    end

    for (i = 0; i < ARR_LEN; i = i + 1) begin
      if (dut.mm_stage_inst.Dmm.mem[RESULT_WORD+i] !== last_res[i]) begin
        $display("[cyc %0d] res[%0d] word%0d = %0d",
                 cycle_cnt, i, RESULT_WORD+i,
                 $signed(dut.mm_stage_inst.Dmm.mem[RESULT_WORD+i]));
        last_res[i] <= dut.mm_stage_inst.Dmm.mem[RESULT_WORD+i];
      end
    end

    if (dut.mm_stage_inst.Dmm.mem[TOHOST_CODE_WORD] !== last_tohost_code ||
        dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD] !== last_tohost_done) begin
      $display("[cyc %0d] tohost: code=0x%08h done=0x%08h",
               cycle_cnt,
               dut.mm_stage_inst.Dmm.mem[TOHOST_CODE_WORD],
               dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD]);
      last_tohost_code <= dut.mm_stage_inst.Dmm.mem[TOHOST_CODE_WORD];
      last_tohost_done <= dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD];
    end
  end
end

initial begin
  $timeformat(-9, 0, " ns", 0);

  last_tohost_code = 32'hxxxxxxxx;
  last_tohost_done = 32'hxxxxxxxx;

  init_last_res;

  rst = 1'b1;
  halt_detected = 1'b0;
  stop_reason = 32'h00000000;

  // ============================================================
  // 修正点6: 提示信息与实际输入/期望输出一致
  // ============================================================
  $display("==============================================");
  $display("RV32I Pipeline TB (selectsort, 6-element)");
  $display("HALT_BYTE_PC=%0d  tohost(done)=DMEM[%0d]", HALT_BYTE_PC, TOHOST_DONE_WORD);
  $display("input  rodata @ word256..261 = {5,-1,2,4,10,8}");
  $display("expect result @ word%0d..%0d = {-1,2,4,5,8,10}", RESULT_WORD, RESULT_WORD+ARR_LEN-1);
  $display("Array stack addr: s0-48=716 byte = Dcache word 179");
  $display("==============================================");

  @(posedge clk); #1;
  @(posedge clk); #1;

  load_icache;
  load_dcache;

  snapshot_input;

  @(posedge clk); #1;
  rst = 1'b0;
  $display("[cycle %0d] reset released", cycle_cnt);

  begin : run_loop
    for (cyc = 0; cyc < MAX_CYCLES; cyc = cyc + 1) begin
      @(posedge clk); #1;

      if (!halt_detected && (dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD] !== 32'h00000000)) begin
        halt_detected = 1'b1;
        stop_reason = 32'h00000001;
        $display("[cycle %0d] DONE detected", cycle_cnt);
        repeat(8) @(posedge clk);
        disable run_loop;
      end

      if (!halt_detected && (dut.pc_if === HALT_BYTE_PC)) begin
        halt_detected = 1'b1;
        stop_reason = 32'h00000002;
        $display("[cycle %0d] HALT PC reached pc_if=%0d", cycle_cnt, dut.pc_if);
        repeat(8) @(posedge clk);
        disable run_loop;
      end
    end
  end

  if (!halt_detected) begin
    $display("[WARN] timeout: no stop within %0d cycles", MAX_CYCLES);
    dump_regs;
  end

  $display("--------------- FINAL ---------------");
  show_tohost;
  dump_result;

  check_sorted;
  check_permutation;
  check_expected_exact;

  $display("sorted_fail=%0d perm_fail=%0d exact_fail=%0d",
           sorted_fail, perm_fail, exact_fail);

  if (sorted_fail == 0 && perm_fail == 0 && exact_fail == 0) begin
    $display("ALL PASSED");
  end else begin
    $display("FAILED");
    dump_regs;
  end

  $display("total cycles=%0d stop_reason=0x%08h", cycle_cnt, stop_reason);
  $display("-------------------------------------");

  $finish;
end

always @(posedge clk) begin
  if (!rst && dut.wb_wreg_out === 1'bx)
    $display("[WARN] X: wb_wreg_out at cycle=%0d", cycle_cnt);
end

endmodule