`timescale 1ns/1ps

// ============================================================================
//  tb_pipeline_datapath.v
//  通用冒泡排序验证 Testbench
//
//  ★ 只需修改两处即可测试任意输入：
//      1. parameter ARR_LEN   — 数组长度
//      2. task load_dcache    — 填入你的测试数据
//
//  验证逻辑（无需预先知道答案）：
//      • 检查输出是否升序排列
//      • 检查输出是否是输入的全排列（元素不丢失、不重复）
// ============================================================================

module tb_pipeline_datapath;

// -----------------------------------------------------------------------------
//  ★ 用户参数区 — 需要时在这里修改
// ─────────────────────────────────────────────────────────────────────────────
parameter CLK_PERIOD = 10;       // 时钟周期 ns（10 ns = 100 MHz）
parameter ARR_LEN    = 6;        // 数组长度，对应 dmem[0..ARR_LEN-1]
parameter HALT_PC    = 9'd55;    // 程序 halt 自跳指令的 PC 地址
parameter MAX_CYCLES = 5000;     // 超时保护周期数

// ─────────────────────────────────────────────────────────────────────────────
//  时钟 & 复位
// ─────────────────────────────────────────────────────────────────────────────
reg clk, rst;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ─────────────────────────────────────────────────────────────────────────────
//  DUT
// ─────────────────────────────────────────────────────────────────────────────
pipeline_datapath dut (
    .clk (clk),
    .rst (rst)
);

// ─────────────────────────────────────────────────────────────────────────────
//  周期计数
// ─────────────────────────────────────────────────────────────────────────────
integer cycle_cnt;
initial cycle_cnt = 0;
always @(posedge clk) cycle_cnt = cycle_cnt + 1;

integer i;

// 输入快照：load_dcache 时自动保存，用于全排列验证
reg [31:0] input_snapshot [0:511];

// ============================================================================
//  Task: load_icache — 冒泡排序程序（固定，不需要修改）
// ============================================================================
task load_icache;
begin
    for (i = 0; i < 512; i = i + 1)
        dut.Imm.mem[i] = 32'h00000013;  // NOP

    dut.Imm.mem[0] = 32'hFC010113;
  dut.Imm.mem[1] = 32'h00000013;
  dut.Imm.mem[2] = 32'h00000013;
  dut.Imm.mem[3] = 32'h02812E23;
  dut.Imm.mem[4] = 32'h00000013;
  dut.Imm.mem[5] = 32'h00000013;
  dut.Imm.mem[6] = 32'h04010413;
  dut.Imm.mem[7] = 32'h00000013;
  dut.Imm.mem[8] = 32'h00000013;
  dut.Imm.mem[9] = 32'h000007B7;
  dut.Imm.mem[10] = 32'h00000013;
  dut.Imm.mem[11] = 32'h00000013;
  dut.Imm.mem[12] = 32'h00078793;
  dut.Imm.mem[13] = 32'h00000013;
  dut.Imm.mem[14] = 32'h00000013;
  dut.Imm.mem[15] = 32'h0007A503;
  dut.Imm.mem[16] = 32'h00000013;
  dut.Imm.mem[17] = 32'h00000013;
  dut.Imm.mem[18] = 32'h0047A583;
  dut.Imm.mem[19] = 32'h00000013;
  dut.Imm.mem[20] = 32'h00000013;
  dut.Imm.mem[21] = 32'h0087A603;
  dut.Imm.mem[22] = 32'h00000013;
  dut.Imm.mem[23] = 32'h00000013;
  dut.Imm.mem[24] = 32'h00C7A683;
  dut.Imm.mem[25] = 32'h00000013;
  dut.Imm.mem[26] = 32'h00000013;
  dut.Imm.mem[27] = 32'h0107A703;
  dut.Imm.mem[28] = 32'h00000013;
  dut.Imm.mem[29] = 32'h00000013;
  dut.Imm.mem[30] = 32'h0147A783;
  dut.Imm.mem[31] = 32'h00000013;
  dut.Imm.mem[32] = 32'h00000013;
  dut.Imm.mem[33] = 32'hFCA42423;
  dut.Imm.mem[34] = 32'h00000013;
  dut.Imm.mem[35] = 32'h00000013;
  dut.Imm.mem[36] = 32'hFCB42623;
  dut.Imm.mem[37] = 32'h00000013;
  dut.Imm.mem[38] = 32'h00000013;
  dut.Imm.mem[39] = 32'hFCC42823;
  dut.Imm.mem[40] = 32'h00000013;
  dut.Imm.mem[41] = 32'h00000013;
  dut.Imm.mem[42] = 32'hFCD42A23;
  dut.Imm.mem[43] = 32'h00000013;
  dut.Imm.mem[44] = 32'h00000013;
  dut.Imm.mem[45] = 32'hFCE42C23;
  dut.Imm.mem[46] = 32'h00000013;
  dut.Imm.mem[47] = 32'h00000013;
  dut.Imm.mem[48] = 32'hFCF42E23;
  dut.Imm.mem[49] = 32'h00000013;
  dut.Imm.mem[50] = 32'h00000013;
  dut.Imm.mem[51] = 32'h00600793;
  dut.Imm.mem[52] = 32'h00000013;
  dut.Imm.mem[53] = 32'h00000013;
  dut.Imm.mem[54] = 32'hFEF42223;
  dut.Imm.mem[55] = 32'h00000013;
  dut.Imm.mem[56] = 32'h00000013;
  dut.Imm.mem[57] = 32'hFE042623;
  dut.Imm.mem[58] = 32'h00000013;
  dut.Imm.mem[59] = 32'h00000013;
  dut.Imm.mem[60] = 32'h1320006F;
  dut.Imm.mem[61] = 32'h00000013;
  dut.Imm.mem[62] = 32'h00000013;
  dut.Imm.mem[63] = 32'hFE042423;
  dut.Imm.mem[64] = 32'h00000013;
  dut.Imm.mem[65] = 32'h00000013;
  dut.Imm.mem[66] = 32'h0F00006F;
  dut.Imm.mem[67] = 32'h00000013;
  dut.Imm.mem[68] = 32'h00000013;
  dut.Imm.mem[69] = 32'hFE842783;
  dut.Imm.mem[70] = 32'h00000013;
  dut.Imm.mem[71] = 32'h00000013;
  dut.Imm.mem[72] = 32'h00279793;
  dut.Imm.mem[73] = 32'h00000013;
  dut.Imm.mem[74] = 32'h00000013;
  dut.Imm.mem[75] = 32'hFF040713;
  dut.Imm.mem[76] = 32'h00000013;
  dut.Imm.mem[77] = 32'h00000013;
  dut.Imm.mem[78] = 32'h00F707B3;
  dut.Imm.mem[79] = 32'h00000013;
  dut.Imm.mem[80] = 32'h00000013;
  dut.Imm.mem[81] = 32'hFD87A703;
  dut.Imm.mem[82] = 32'h00000013;
  dut.Imm.mem[83] = 32'h00000013;
  dut.Imm.mem[84] = 32'hFE842783;
  dut.Imm.mem[85] = 32'h00000013;
  dut.Imm.mem[86] = 32'h00000013;
  dut.Imm.mem[87] = 32'h00178793;
  dut.Imm.mem[88] = 32'h00000013;
  dut.Imm.mem[89] = 32'h00000013;
  dut.Imm.mem[90] = 32'h00279793;
  dut.Imm.mem[91] = 32'h00000013;
  dut.Imm.mem[92] = 32'h00000013;
  dut.Imm.mem[93] = 32'hFF040693;
  dut.Imm.mem[94] = 32'h00000013;
  dut.Imm.mem[95] = 32'h00000013;
  dut.Imm.mem[96] = 32'h00F687B3;
  dut.Imm.mem[97] = 32'h00000013;
  dut.Imm.mem[98] = 32'h00000013;
  dut.Imm.mem[99] = 32'hFD87A783;
  dut.Imm.mem[100] = 32'h00000013;
  dut.Imm.mem[101] = 32'h00000013;
  dut.Imm.mem[102] = 32'h08E7DB63;
  dut.Imm.mem[103] = 32'h00000013;
  dut.Imm.mem[104] = 32'h00000013;
  dut.Imm.mem[105] = 32'hFE842783;
  dut.Imm.mem[106] = 32'h00000013;
  dut.Imm.mem[107] = 32'h00000013;
  dut.Imm.mem[108] = 32'h00279793;
  dut.Imm.mem[109] = 32'h00000013;
  dut.Imm.mem[110] = 32'h00000013;
  dut.Imm.mem[111] = 32'hFF040713;
  dut.Imm.mem[112] = 32'h00000013;
  dut.Imm.mem[113] = 32'h00000013;
  dut.Imm.mem[114] = 32'h00F707B3;
  dut.Imm.mem[115] = 32'h00000013;
  dut.Imm.mem[116] = 32'h00000013;
  dut.Imm.mem[117] = 32'hFD87A783;
  dut.Imm.mem[118] = 32'h00000013;
  dut.Imm.mem[119] = 32'h00000013;
  dut.Imm.mem[120] = 32'hFEF42023;
  dut.Imm.mem[121] = 32'h00000013;
  dut.Imm.mem[122] = 32'h00000013;
  dut.Imm.mem[123] = 32'hFE842783;
  dut.Imm.mem[124] = 32'h00000013;
  dut.Imm.mem[125] = 32'h00000013;
  dut.Imm.mem[126] = 32'h00178793;
  dut.Imm.mem[127] = 32'h00000013;
  dut.Imm.mem[128] = 32'h00000013;
  dut.Imm.mem[129] = 32'h00279793;
  dut.Imm.mem[130] = 32'h00000013;
  dut.Imm.mem[131] = 32'h00000013;
  dut.Imm.mem[132] = 32'hFF040713;
  dut.Imm.mem[133] = 32'h00000013;
  dut.Imm.mem[134] = 32'h00000013;
  dut.Imm.mem[135] = 32'h00F707B3;
  dut.Imm.mem[136] = 32'h00000013;
  dut.Imm.mem[137] = 32'h00000013;
  dut.Imm.mem[138] = 32'hFD87A703;
  dut.Imm.mem[139] = 32'h00000013;
  dut.Imm.mem[140] = 32'h00000013;
  dut.Imm.mem[141] = 32'hFE842783;
  dut.Imm.mem[142] = 32'h00000013;
  dut.Imm.mem[143] = 32'h00000013;
  dut.Imm.mem[144] = 32'h00279793;
  dut.Imm.mem[145] = 32'h00000013;
  dut.Imm.mem[146] = 32'h00000013;
  dut.Imm.mem[147] = 32'hFF040693;
  dut.Imm.mem[148] = 32'h00000013;
  dut.Imm.mem[149] = 32'h00000013;
  dut.Imm.mem[150] = 32'h00F687B3;
  dut.Imm.mem[151] = 32'h00000013;
  dut.Imm.mem[152] = 32'h00000013;
  dut.Imm.mem[153] = 32'hFCE7AC23;
  dut.Imm.mem[154] = 32'h00000013;
  dut.Imm.mem[155] = 32'h00000013;
  dut.Imm.mem[156] = 32'hFE842783;
  dut.Imm.mem[157] = 32'h00000013;
  dut.Imm.mem[158] = 32'h00000013;
  dut.Imm.mem[159] = 32'h00178793;
  dut.Imm.mem[160] = 32'h00000013;
  dut.Imm.mem[161] = 32'h00000013;
  dut.Imm.mem[162] = 32'h00279793;
  dut.Imm.mem[163] = 32'h00000013;
  dut.Imm.mem[164] = 32'h00000013;
  dut.Imm.mem[165] = 32'hFF040713;
  dut.Imm.mem[166] = 32'h00000013;
  dut.Imm.mem[167] = 32'h00000013;
  dut.Imm.mem[168] = 32'h00F707B3;
  dut.Imm.mem[169] = 32'h00000013;
  dut.Imm.mem[170] = 32'h00000013;
  dut.Imm.mem[171] = 32'hFE042703;
  dut.Imm.mem[172] = 32'h00000013;
  dut.Imm.mem[173] = 32'h00000013;
  dut.Imm.mem[174] = 32'hFCE7AC23;
  dut.Imm.mem[175] = 32'h00000013;
  dut.Imm.mem[176] = 32'h00000013;
  dut.Imm.mem[177] = 32'hFE842783;
  dut.Imm.mem[178] = 32'h00000013;
  dut.Imm.mem[179] = 32'h00000013;
  dut.Imm.mem[180] = 32'h00178793;
  dut.Imm.mem[181] = 32'h00000013;
  dut.Imm.mem[182] = 32'h00000013;
  dut.Imm.mem[183] = 32'hFEF42423;
  dut.Imm.mem[184] = 32'h00000013;
  dut.Imm.mem[185] = 32'h00000013;
  dut.Imm.mem[186] = 32'hFE442783;
  dut.Imm.mem[187] = 32'h00000013;
  dut.Imm.mem[188] = 32'h00000013;
  dut.Imm.mem[189] = 32'hFFF78713;
  dut.Imm.mem[190] = 32'h00000013;
  dut.Imm.mem[191] = 32'h00000013;
  dut.Imm.mem[192] = 32'hFEC42783;
  dut.Imm.mem[193] = 32'h00000013;
  dut.Imm.mem[194] = 32'h00000013;
  dut.Imm.mem[195] = 32'h40F707B3;
  dut.Imm.mem[196] = 32'h00000013;
  dut.Imm.mem[197] = 32'h00000013;
  dut.Imm.mem[198] = 32'hFE842703;
  dut.Imm.mem[199] = 32'h00000013;
  dut.Imm.mem[200] = 32'h00000013;
  dut.Imm.mem[201] = 32'hEEF74CE3;
  dut.Imm.mem[202] = 32'h00000013;
  dut.Imm.mem[203] = 32'h00000013;
  dut.Imm.mem[204] = 32'hFEC42783;
  dut.Imm.mem[205] = 32'h00000013;
  dut.Imm.mem[206] = 32'h00000013;
  dut.Imm.mem[207] = 32'h00178793;
  dut.Imm.mem[208] = 32'h00000013;
  dut.Imm.mem[209] = 32'h00000013;
  dut.Imm.mem[210] = 32'hFEF42623;
  dut.Imm.mem[211] = 32'h00000013;
  dut.Imm.mem[212] = 32'h00000013;
  dut.Imm.mem[213] = 32'hFE442783;
  dut.Imm.mem[214] = 32'h00000013;
  dut.Imm.mem[215] = 32'h00000013;
  dut.Imm.mem[216] = 32'hFFF78793;
  dut.Imm.mem[217] = 32'h00000013;
  dut.Imm.mem[218] = 32'h00000013;
  dut.Imm.mem[219] = 32'hFEC42703;
  dut.Imm.mem[220] = 32'h00000013;
  dut.Imm.mem[221] = 32'h00000013;
  dut.Imm.mem[222] = 32'hECF741E3;
  dut.Imm.mem[223] = 32'h00000013;
  dut.Imm.mem[224] = 32'h00000013;
  dut.Imm.mem[225] = 32'h00000793;
  dut.Imm.mem[226] = 32'h00000013;
  dut.Imm.mem[227] = 32'h00000013;
  dut.Imm.mem[228] = 32'h00078513;
  dut.Imm.mem[229] = 32'h00000013;
  dut.Imm.mem[230] = 32'h00000013;
  dut.Imm.mem[231] = 32'h03C12403;
end
endtask

// ============================================================================
//  Task: load_dcache
//  ★★ 只需修改这里的输入数据 ★★
//  同时自动保存到 input_snapshot[]，不需要改其他任何地方
// ============================================================================
task load_dcache;
begin
    // 清零
    for (i = 0; i < 512; i = i + 1) begin
        dut.mm_stage_inst.Dmm.mem[i] = 32'h00000000;
        input_snapshot[i]            = 32'h00000000;
    end

    // ── ★ 在这里修改测试数据 ★ ─────────────────────────────────────
    dut.mm_stage_inst.Dmm.mem[0] = 32'h00000005;
  dut.mm_stage_inst.Dmm.mem[1] = 32'hFFFFFFFF;
  dut.mm_stage_inst.Dmm.mem[2] = 32'h00000002;
  dut.mm_stage_inst.Dmm.mem[3] = 32'h00000004;
  dut.mm_stage_inst.Dmm.mem[4] = 32'h0000000A;
  dut.mm_stage_inst.Dmm.mem[5] = 32'h00000008;
    // ────────────────────────────────────────────────────────────────

    // 自动保存输入快照（请勿修改此处）
    for (i = 0; i < ARR_LEN; i = i + 1)
        input_snapshot[i] = dut.mm_stage_inst.Dmm.mem[i];
end
endtask

// ============================================================================
//  Task: check_sorted
//  验证 1：输出结果是否为升序
//  方法：逐对相邻元素比较 dmem[k] <= dmem[k+1]
// ============================================================================
integer sorted_fail;
task check_sorted;
integer k;
reg signed [31:0] cur, nxt;
begin
    sorted_fail = 0;
    $display("  ── 验证1：升序检查 ───────────────────────────────────");
    $display("  idx │ 输出值");
    $display("  ────┼────────");
    for (k = 0; k < ARR_LEN; k = k + 1)
        $display("  [%0d] │  %0d", k, $signed(dut.mm_stage_inst.Dmm.mem[k]));
    $display("  ────┴────────");

    for (k = 0; k < ARR_LEN - 1; k = k + 1) begin
        cur = dut.mm_stage_inst.Dmm.mem[k];
        nxt = dut.mm_stage_inst.Dmm.mem[k+1];
        if (cur > nxt) begin
            $display("  [FAIL] dmem[%0d]=%0d  >  dmem[%0d]=%0d  ← 顺序错误!",
                     k, cur, k+1, nxt);
            sorted_fail = sorted_fail + 1;
        end
    end

    if (sorted_fail == 0)
        $display("  结论：升序检查 PASS ✓\n");
    else
        $display("  结论：升序检查 FAIL ✗（%0d 处乱序）\n", sorted_fail);
end
endtask

// ============================================================================
//  Task: check_permutation
//  验证 2：输出是否是输入的全排列（元素无丢失/无重复）
//  方法：对每个输入值统计它在输入与输出中的出现次数，两者必须相等
// ============================================================================
integer perm_fail;
task check_permutation;
integer j, k;
reg [31:0] val;
integer cnt_in, cnt_out;
begin
    perm_fail = 0;
    $display("  ── 验证2：元素完整性检查（无丢失/无重复）─────────────");

    for (j = 0; j < ARR_LEN; j = j + 1) begin
        val     = input_snapshot[j];
        cnt_in  = 0;
        cnt_out = 0;
        for (k = 0; k < ARR_LEN; k = k + 1) begin
            if (input_snapshot[k]            === val) cnt_in  = cnt_in  + 1;
            if (dut.mm_stage_inst.Dmm.mem[k] === val) cnt_out = cnt_out + 1;
        end
        if (cnt_in !== cnt_out) begin
            $display("  [FAIL] 元素 %0d：输入出现 %0d 次，输出出现 %0d 次",
                     val, cnt_in, cnt_out);
            perm_fail = perm_fail + 1;
        end
    end

    if (perm_fail == 0)
        $display("  结论：元素完整性检查 PASS ✓\n");
    else
        $display("  结论：元素完整性检查 FAIL ✗（%0d 个元素计数不符）\n", perm_fail);
end
endtask

// ============================================================================
//  Task: dump_regs  （调试辅助，默认不调用）
// ============================================================================
task dump_regs;
begin
    $display("\n--- 寄存器快照 (cycle %0d) ---", cycle_cnt);
    $display("  x5  (i)      = %0d", dut.id_stage_inst.u_reg_files.regs[5]);
    $display("  x6  (j)      = %0d", dut.id_stage_inst.u_reg_files.regs[6]);
    $display("  x7  (limit)  = %0d", dut.id_stage_inst.u_reg_files.regs[7]);
    $display("  x8  (arr[j]) = %0d", dut.id_stage_inst.u_reg_files.regs[8]);
    $display("  x9  (arr[j1])= %0d", dut.id_stage_inst.u_reg_files.regs[9]);
    $display("  x11 (j+1)    = %0d", dut.id_stage_inst.u_reg_files.regs[11]);
    $display("  x12 (n)      = %0d", dut.id_stage_inst.u_reg_files.regs[12]);
    $display("  x13 (n-1)    = %0d", dut.id_stage_inst.u_reg_files.regs[13]);
end
endtask

// ============================================================================
//  主仿真流程
// ============================================================================
reg halt_detected;
integer k_print;

initial begin
    $display("============================================================");
    $display("  RV32I Pipeline Testbench — 冒泡排序（通用验证）");
    $display("  数组长度 ARR_LEN = %0d", ARR_LEN);
    $display("============================================================");

    // ── 复位 ──────────────────────────────────────────────────────────
    rst           = 1;
    halt_detected = 0;
    @(posedge clk); #1;
    @(posedge clk); #1;

    // ── 加载存储器 ────────────────────────────────────────────────────
    load_icache;
    load_dcache;

    // 打印原始输入
    $display("\n  原始输入数据：");
    for (k_print = 0; k_print < ARR_LEN; k_print = k_print + 1)
        $display("    dmem[%0d] = %0d", k_print, input_snapshot[k_print]);

    // ── 释放复位 ──────────────────────────────────────────────────────
    @(posedge clk); #1;
    rst = 0;
    $display("\n[cycle %0d] 复位释放，开始运行...", cycle_cnt);

    // ── 运行直到 halt 或超时 ──────────────────────────────────────────
    begin : run_loop
        integer cyc;
        for (cyc = 0; cyc < MAX_CYCLES; cyc = cyc + 1) begin
            @(posedge clk); #1;
            if (dut.pc_if === HALT_PC && !halt_detected) begin
                halt_detected = 1;
                $display("[cycle %0d] Halt 检测到（PC = %0d）", cycle_cnt, HALT_PC);
                repeat(8) @(posedge clk);  // 等流水线排空
                disable run_loop;
            end
        end
        if (!halt_detected)
            $display("[WARN] 超时！%0d 周期内未检测到 Halt（PC=%0d）",
                     MAX_CYCLES, HALT_PC);
    end

    // ── 结果验证 ──────────────────────────────────────────────────────
    $display("\n========== 排序结果验证 (cycle %0d) ==========\n", cycle_cnt);
    check_sorted;
    check_permutation;

    // ── 总结 ──────────────────────────────────────────────────────────
    $display("═════════════════════════════════════════════");
    if (sorted_fail == 0 && perm_fail == 0) begin
        $display("  ★  总体结果：ALL PASSED  ★");
    end else begin
        $display("  ✗  总体结果：FAILED");
        if (sorted_fail > 0) $display("     · 升序错误：%0d 处", sorted_fail);
        if (perm_fail   > 0) $display("     · 元素错误：%0d 个", perm_fail);
    end
    $display("  总仿真周期：%0d", cycle_cnt);
    $display("═════════════════════════════════════════════\n");

    // dump_regs;  // ← 调试时取消注释

    $finish;
end

// ============================================================================
//  逐周期 VERBOSE 跟踪（取消注释 `define VERBOSE 启用）
// ============================================================================
// `define VERBOSE
`ifdef VERBOSE
always @(posedge clk) begin
    if (!rst)
        $display("CYC=%4d | PC_IF=%2d | flush=%b | WB rd=x%2d data=%6d we=%b",
            cycle_cnt, dut.pc_if, dut.flush_in,
            dut.wb_rd_out, $signed(dut.wb_data_out), dut.wb_wreg_out);
end
`endif

// X 态监视
always @(posedge clk)
    if (!rst && dut.wb_wreg_out === 1'bx)
        $display("[WARN] X 态：wb_wreg_out 在 cycle %0d 异常", cycle_cnt);

endmodule