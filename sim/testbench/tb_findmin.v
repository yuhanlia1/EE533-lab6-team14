`timescale 1ns/1ps

module tb_pipeline_datapath;

parameter CLK_PERIOD = 10;
parameter MAX_CYCLES = 50000;
parameter TRACE_FIRST_N = 250;

localparam [10:0] HALT_BYTE_PC = 11'd648;

localparam integer TOHOST_CODE_WORD = 510;
localparam integer TOHOST_DONE_WORD = 511;

localparam integer W_MIN = 189;  // -8(s0) = 756 bytes -> word 189
localparam integer W_I   = 188;  // -12(s0) = 752 bytes -> word 188 (loop index)

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

integer cyc;
reg halt_detected;
reg [31:0] stop_reason;

reg [31:0] last_min, last_i;
reg [31:0] last_tohost_code, last_tohost_done;

reg [31:0] if_instr;
integer if_idx;

reg signed [31:0] min_val, i_val;
integer fail_cnt;

task clear_imem;
  integer k;
  begin
    for (k = 0; k < 512; k = k + 1)
      dut.Imm.mem[k] = 32'h00000013;
  end
endtask

task clear_dmem;
  integer k;
  begin
    for (k = 0; k < 512; k = k + 1)
      dut.mm_stage_inst.Dmm.mem[k] = 32'h00000000;
  end
endtask

task dump_regs;
  begin
    $display("--- REGS (cycle=%0d) ---", cycle_cnt);
    $display("x1  ra = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[1],  $signed(dut.id_stage_inst.u_reg_files.regs[1]));
    $display("x2  sp = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[2],  $signed(dut.id_stage_inst.u_reg_files.regs[2]));
    $display("x8  s0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[8],  $signed(dut.id_stage_inst.u_reg_files.regs[8]));
    $display("x10 a0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[10], $signed(dut.id_stage_inst.u_reg_files.regs[10]));
    $display("x12 a2 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[12], $signed(dut.id_stage_inst.u_reg_files.regs[12]));
    $display("x13 a3 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[13], $signed(dut.id_stage_inst.u_reg_files.regs[13]));
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

task read_locals;
  begin
    min_val = $signed(dut.mm_stage_inst.Dmm.mem[W_MIN]);
    i_val   = $signed(dut.mm_stage_inst.Dmm.mem[W_I]);
  end
endtask

task check_findmin;
  begin
    fail_cnt = 0;
    read_locals;
    $display("locals: i(word%0d)=%0d min(word%0d)=%0d", W_I, i_val, W_MIN, min_val);

    if (min_val !== 1) begin
      $display("FINDMIN FAIL: expected 1 got %0d", min_val);
      fail_cnt = fail_cnt + 1;
    end else begin
      $display("FINDMIN PASS");
    end
  end
endtask

// ────────────────────────────────────────────────────
// load_icache: from your vh (findmin_rv32i_gen.s)
// ────────────────────────────────────────────────────
task load_icache;
integer _ki;
begin
    for (_ki = 0; _ki < 512; _ki = _ki + 1)
        dut.Imm.mem[_ki] = 32'h00000013;

    dut.Imm.mem[  0] = 32'h30000113;
    dut.Imm.mem[  1] = 32'h00000013;
    dut.Imm.mem[  2] = 32'h00000013;
    dut.Imm.mem[  3] = 32'hFF810113;
    dut.Imm.mem[  4] = 32'h00000013;
    dut.Imm.mem[  5] = 32'h00000013;
    dut.Imm.mem[  6] = 32'h00812023;
    dut.Imm.mem[  7] = 32'h00000013;
    dut.Imm.mem[  8] = 32'h00000013;
    dut.Imm.mem[  9] = 32'h00112223;
    dut.Imm.mem[ 10] = 32'h00000013;
    dut.Imm.mem[ 11] = 32'h00000013;
    dut.Imm.mem[ 12] = 32'h00410413;
    dut.Imm.mem[ 13] = 32'h00000013;
    dut.Imm.mem[ 14] = 32'h00000013;
    dut.Imm.mem[ 15] = 32'hFE010113;
    dut.Imm.mem[ 16] = 32'h00000013;
    dut.Imm.mem[ 17] = 32'h00000013;
    dut.Imm.mem[ 18] = 32'h000006B7;
    dut.Imm.mem[ 19] = 32'h00000013;
    dut.Imm.mem[ 20] = 32'h00000013;
    dut.Imm.mem[ 21] = 32'h40068693;
    dut.Imm.mem[ 22] = 32'h00000013;
    dut.Imm.mem[ 23] = 32'h00000013;
    dut.Imm.mem[ 24] = 32'hFDC40293;
    dut.Imm.mem[ 25] = 32'h00000013;
    dut.Imm.mem[ 26] = 32'h00000013;
    dut.Imm.mem[ 27] = 32'h00068093;
    dut.Imm.mem[ 28] = 32'h00000013;
    dut.Imm.mem[ 29] = 32'h00000013;
    dut.Imm.mem[ 30] = 32'h0000A503;
    dut.Imm.mem[ 31] = 32'h00000013;
    dut.Imm.mem[ 32] = 32'h00000013;
    dut.Imm.mem[ 33] = 32'h0040A583;
    dut.Imm.mem[ 34] = 32'h00000013;
    dut.Imm.mem[ 35] = 32'h00000013;
    dut.Imm.mem[ 36] = 32'h0080A603;
    dut.Imm.mem[ 37] = 32'h00000013;
    dut.Imm.mem[ 38] = 32'h00000013;
    dut.Imm.mem[ 39] = 32'h00C0A683;
    dut.Imm.mem[ 40] = 32'h00000013;
    dut.Imm.mem[ 41] = 32'h00000013;
    dut.Imm.mem[ 42] = 32'h01008093;
    dut.Imm.mem[ 43] = 32'h00000013;
    dut.Imm.mem[ 44] = 32'h00000013;
    dut.Imm.mem[ 45] = 32'h00A2A023;
    dut.Imm.mem[ 46] = 32'h00000013;
    dut.Imm.mem[ 47] = 32'h00000013;
    dut.Imm.mem[ 48] = 32'h00B2A223;
    dut.Imm.mem[ 49] = 32'h00000013;
    dut.Imm.mem[ 50] = 32'h00000013;
    dut.Imm.mem[ 51] = 32'h00C2A423;
    dut.Imm.mem[ 52] = 32'h00000013;
    dut.Imm.mem[ 53] = 32'h00000013;
    dut.Imm.mem[ 54] = 32'h00D2A623;
    dut.Imm.mem[ 55] = 32'h00000013;
    dut.Imm.mem[ 56] = 32'h00000013;
    dut.Imm.mem[ 57] = 32'h01028293;
    dut.Imm.mem[ 58] = 32'h00000013;
    dut.Imm.mem[ 59] = 32'h00000013;
    dut.Imm.mem[ 60] = 32'h0000A683;
    dut.Imm.mem[ 61] = 32'h00000013;
    dut.Imm.mem[ 62] = 32'h00000013;
    dut.Imm.mem[ 63] = 32'h00D2A023;
    dut.Imm.mem[ 64] = 32'h00000013;
    dut.Imm.mem[ 65] = 32'h00000013;
    dut.Imm.mem[ 66] = 32'h00500693;
    dut.Imm.mem[ 67] = 32'h00000013;
    dut.Imm.mem[ 68] = 32'h00000013;
    dut.Imm.mem[ 69] = 32'hFED42823;
    dut.Imm.mem[ 70] = 32'h00000013;
    dut.Imm.mem[ 71] = 32'h00000013;
    dut.Imm.mem[ 72] = 32'hFDC42683;
    dut.Imm.mem[ 73] = 32'h00000013;
    dut.Imm.mem[ 74] = 32'h00000013;
    dut.Imm.mem[ 75] = 32'hFED42C23;
    dut.Imm.mem[ 76] = 32'h00000013;
    dut.Imm.mem[ 77] = 32'h00000013;
    dut.Imm.mem[ 78] = 32'h00100693;
    dut.Imm.mem[ 79] = 32'h00000013;
    dut.Imm.mem[ 80] = 32'h00000013;
    dut.Imm.mem[ 81] = 32'hFED42A23;
    dut.Imm.mem[ 82] = 32'h00000013;
    dut.Imm.mem[ 83] = 32'h00000013;
    dut.Imm.mem[ 84] = 32'h0CC0006F;
    dut.Imm.mem[ 85] = 32'h00000013;
    dut.Imm.mem[ 86] = 32'h00000013;
    dut.Imm.mem[ 87] = 32'hFF442683;
    dut.Imm.mem[ 88] = 32'h00000013;
    dut.Imm.mem[ 89] = 32'h00000013;
    dut.Imm.mem[ 90] = 32'h00269693;
    dut.Imm.mem[ 91] = 32'h00000013;
    dut.Imm.mem[ 92] = 32'h00000013;
    dut.Imm.mem[ 93] = 32'hFFC40613;
    dut.Imm.mem[ 94] = 32'h00000013;
    dut.Imm.mem[ 95] = 32'h00000013;
    dut.Imm.mem[ 96] = 32'h00D606B3;
    dut.Imm.mem[ 97] = 32'h00000013;
    dut.Imm.mem[ 98] = 32'h00000013;
    dut.Imm.mem[ 99] = 32'hFE06A683;
    dut.Imm.mem[100] = 32'h00000013;
    dut.Imm.mem[101] = 32'h00000013;
    dut.Imm.mem[102] = 32'hFF842603;
    dut.Imm.mem[103] = 32'h00000013;
    dut.Imm.mem[104] = 32'h00000013;
    dut.Imm.mem[105] = 32'h04C6DA63;
    dut.Imm.mem[106] = 32'h00000013;
    dut.Imm.mem[107] = 32'h00000013;
    dut.Imm.mem[108] = 32'hFF442683;
    dut.Imm.mem[109] = 32'h00000013;
    dut.Imm.mem[110] = 32'h00000013;
    dut.Imm.mem[111] = 32'h00269693;
    dut.Imm.mem[112] = 32'h00000013;
    dut.Imm.mem[113] = 32'h00000013;
    dut.Imm.mem[114] = 32'hFFC40613;
    dut.Imm.mem[115] = 32'h00000013;
    dut.Imm.mem[116] = 32'h00000013;
    dut.Imm.mem[117] = 32'h00D606B3;
    dut.Imm.mem[118] = 32'h00000013;
    dut.Imm.mem[119] = 32'h00000013;
    dut.Imm.mem[120] = 32'hFE06A683;
    dut.Imm.mem[121] = 32'h00000013;
    dut.Imm.mem[122] = 32'h00000013;
    dut.Imm.mem[123] = 32'hFED42C23;
    dut.Imm.mem[124] = 32'h00000013;
    dut.Imm.mem[125] = 32'h00000013;
    dut.Imm.mem[126] = 32'hFF442683;
    dut.Imm.mem[127] = 32'h00000013;
    dut.Imm.mem[128] = 32'h00000013;
    dut.Imm.mem[129] = 32'h00168693;
    dut.Imm.mem[130] = 32'h00000013;
    dut.Imm.mem[131] = 32'h00000013;
    dut.Imm.mem[132] = 32'hFED42A23;
    dut.Imm.mem[133] = 32'h00000013;
    dut.Imm.mem[134] = 32'h00000013;
    dut.Imm.mem[135] = 32'hFF442603;
    dut.Imm.mem[136] = 32'h00000013;
    dut.Imm.mem[137] = 32'h00000013;
    dut.Imm.mem[138] = 32'hFF042683;
    dut.Imm.mem[139] = 32'h00000013;
    dut.Imm.mem[140] = 32'h00000013;
    dut.Imm.mem[141] = 32'hF2D644E3;
    dut.Imm.mem[142] = 32'h00000013;
    dut.Imm.mem[143] = 32'h00000013;
    dut.Imm.mem[144] = 32'h00000693;
    dut.Imm.mem[145] = 32'h00000013;
    dut.Imm.mem[146] = 32'h00000013;
    dut.Imm.mem[147] = 32'h00068513;
    dut.Imm.mem[148] = 32'h00000013;
    dut.Imm.mem[149] = 32'h00000013;
    dut.Imm.mem[150] = 32'hFFC40113;
    dut.Imm.mem[151] = 32'h00000013;
    dut.Imm.mem[152] = 32'h00000013;
    dut.Imm.mem[153] = 32'h00012403;
    dut.Imm.mem[154] = 32'h00000013;
    dut.Imm.mem[155] = 32'h00000013;
    dut.Imm.mem[156] = 32'h00412083;
    dut.Imm.mem[157] = 32'h00000013;
    dut.Imm.mem[158] = 32'h00000013;
    dut.Imm.mem[159] = 32'h00810113;
    dut.Imm.mem[160] = 32'h00000013;
    dut.Imm.mem[161] = 32'h00000013;
    dut.Imm.mem[162] = 32'h00000063;
    dut.Imm.mem[163] = 32'h00000013;
    dut.Imm.mem[164] = 32'h00000013;

    $display("[ICACHE] loaded, HALT byte PC=%0d", HALT_BYTE_PC);
end
endtask

// ────────────────────────────────────────────────────
// load_dcache: from your vh
// ────────────────────────────────────────────────────
task load_dcache;
integer _kd;
begin
    for (_kd = 0; _kd < 512; _kd = _kd + 1)
        dut.mm_stage_inst.Dmm.mem[_kd] = 32'h00000000;

    dut.mm_stage_inst.Dmm.mem[256] = 32'h00000005;
    dut.mm_stage_inst.Dmm.mem[257] = 32'h00000002;
    dut.mm_stage_inst.Dmm.mem[258] = 32'h00000009;
    dut.mm_stage_inst.Dmm.mem[259] = 32'h00000001;
    dut.mm_stage_inst.Dmm.mem[260] = 32'h00000003;

    $display("[DCACHE] preloaded .rodata at 256..260");
end
endtask

// ────────────────────────────────────────────────────
// runtime monitors
// ────────────────────────────────────────────────────
always @(posedge clk) begin
  if (!rst) begin
    if (cycle_cnt <= TRACE_FIRST_N) begin
      if_idx = dut.pc_if >> 2;
      if_instr = dut.Imm.mem[if_idx];
      $display("[cyc %0d] pc=%0d instr=0x%08h", cycle_cnt, dut.pc_if, if_instr);
    end

    if (dut.mm_stage_inst.Dmm.mem[W_MIN] !== last_min ||
        dut.mm_stage_inst.Dmm.mem[W_I]   !== last_i) begin
      $display("[cyc %0d] locals: i(word%0d)=%0d  min(word%0d)=%0d",
               cycle_cnt,
               W_I,   $signed(dut.mm_stage_inst.Dmm.mem[W_I]),
               W_MIN, $signed(dut.mm_stage_inst.Dmm.mem[W_MIN]));
      last_min <= dut.mm_stage_inst.Dmm.mem[W_MIN];
      last_i   <= dut.mm_stage_inst.Dmm.mem[W_I];
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

  last_min = 32'hxxxxxxxx;
  last_i   = 32'hxxxxxxxx;
  last_tohost_code = 32'hxxxxxxxx;
  last_tohost_done = 32'hxxxxxxxx;

  rst = 1'b1;
  halt_detected = 1'b0;
  stop_reason = 32'h00000000;

  $display("==============================================");
  $display("RV32I Pipeline TB (findmin)");
  $display("HALT_BYTE_PC=%0d  tohost(done)=DMEM[%0d]", HALT_BYTE_PC, TOHOST_DONE_WORD);
  $display("input array @ rodata word256..260 = {5,2,9,1,3}");
  $display("expect min = 1 stored at word%0d (-8(s0))", W_MIN);
  $display("==============================================");

  @(posedge clk); #1;
  @(posedge clk); #1;

  clear_imem;
  clear_dmem;

  load_icache;
  load_dcache;

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
  check_findmin;

  if (fail_cnt == 0) begin
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