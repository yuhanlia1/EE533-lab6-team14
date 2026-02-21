`timescale 1ns/1ps

module tb_pipeline_datapath;

parameter CLK_PERIOD = 10;
parameter MAX_CYCLES = 50000;
parameter TRACE_FIRST_N = 200;

localparam [10:0] HALT_BYTE_PC = 11'd372;

localparam integer TOHOST_CODE_WORD = 510;
localparam integer TOHOST_DONE_WORD = 511;

localparam integer W_TEMP = 186;
localparam integer W_I    = 187;
localparam integer W_B    = 188;
localparam integer W_A    = 189;

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

reg [31:0] last186, last187, last188, last189;
reg [31:0] last_tohost_code, last_tohost_done;

reg halt_detected;
reg [31:0] stop_reason;

integer cyc;

reg signed [31:0] fib_a, fib_b, fib_i, fib_t;
integer fib_fail;

reg [31:0] if_instr;
integer if_idx;

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
    $display("x2  sp = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[2],  $signed(dut.id_stage_inst.u_reg_files.regs[2]));
    $display("x8  s0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[8],  $signed(dut.id_stage_inst.u_reg_files.regs[8]));
    $display("x10 a0 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[10], $signed(dut.id_stage_inst.u_reg_files.regs[10]));
    $display("x12 a2 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[12], $signed(dut.id_stage_inst.u_reg_files.regs[12]));
    $display("x13 a3 = 0x%08h (%0d)", dut.id_stage_inst.u_reg_files.regs[13], $signed(dut.id_stage_inst.u_reg_files.regs[13]));
  end
endtask

task read_stack_words;
  begin
    fib_t = $signed(dut.mm_stage_inst.Dmm.mem[W_TEMP]);
    fib_i = $signed(dut.mm_stage_inst.Dmm.mem[W_I]);
    fib_b = $signed(dut.mm_stage_inst.Dmm.mem[W_B]);
    fib_a = $signed(dut.mm_stage_inst.Dmm.mem[W_A]);
  end
endtask

task check_fib20;
  begin
    fib_fail = 0;
    read_stack_words;
    $display("stack: temp(w186)=%0d i(w187)=%0d b(w188)=%0d a(w189)=%0d", fib_t, fib_i, fib_b, fib_a);
    if (fib_b !== 6765) begin
      fib_fail = 1;
      $display("F(20) FAIL exp=6765 got=%0d", fib_b);
    end else begin
      $display("F(20) PASS");
    end
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

task load_icache;
  integer _ki;
  begin
    for (_ki = 0; _ki < 512; _ki = _ki + 1)
      dut.Imm.mem[_ki] = 32'h00000013;

    dut.Imm.mem[  0] = 32'h30000113;
    dut.Imm.mem[  1] = 32'h00000013;
    dut.Imm.mem[  2] = 32'h00000013;
    dut.Imm.mem[  3] = 32'hFFC10113;
    dut.Imm.mem[  4] = 32'h00000013;
    dut.Imm.mem[  5] = 32'h00000013;
    dut.Imm.mem[  6] = 32'h00812023;
    dut.Imm.mem[  7] = 32'h00000013;
    dut.Imm.mem[  8] = 32'h00000013;
    dut.Imm.mem[  9] = 32'h00010413;
    dut.Imm.mem[ 10] = 32'h00000013;
    dut.Imm.mem[ 11] = 32'h00000013;
    dut.Imm.mem[ 12] = 32'hFEC10113;
    dut.Imm.mem[ 13] = 32'h00000013;
    dut.Imm.mem[ 14] = 32'h00000013;
    dut.Imm.mem[ 15] = 32'h00100693;
    dut.Imm.mem[ 16] = 32'h00000013;
    dut.Imm.mem[ 17] = 32'h00000013;
    dut.Imm.mem[ 18] = 32'hFED42C23;
    dut.Imm.mem[ 19] = 32'h00000013;
    dut.Imm.mem[ 20] = 32'h00000013;
    dut.Imm.mem[ 21] = 32'h00100693;
    dut.Imm.mem[ 22] = 32'h00000013;
    dut.Imm.mem[ 23] = 32'h00000013;
    dut.Imm.mem[ 24] = 32'hFED42A23;
    dut.Imm.mem[ 25] = 32'h00000013;
    dut.Imm.mem[ 26] = 32'h00000013;
    dut.Imm.mem[ 27] = 32'h00300693;
    dut.Imm.mem[ 28] = 32'h00000013;
    dut.Imm.mem[ 29] = 32'h00000013;
    dut.Imm.mem[ 30] = 32'hFED42823;
    dut.Imm.mem[ 31] = 32'h00000013;
    dut.Imm.mem[ 32] = 32'h00000013;
    dut.Imm.mem[ 33] = 32'h0900006F;
    dut.Imm.mem[ 34] = 32'h00000013;
    dut.Imm.mem[ 35] = 32'h00000013;
    dut.Imm.mem[ 36] = 32'hFF842603;
    dut.Imm.mem[ 37] = 32'h00000013;
    dut.Imm.mem[ 38] = 32'h00000013;
    dut.Imm.mem[ 39] = 32'hFF442683;
    dut.Imm.mem[ 40] = 32'h00000013;
    dut.Imm.mem[ 41] = 32'h00000013;
    dut.Imm.mem[ 42] = 32'h00D606B3;
    dut.Imm.mem[ 43] = 32'h00000013;
    dut.Imm.mem[ 44] = 32'h00000013;
    dut.Imm.mem[ 45] = 32'hFED42623;
    dut.Imm.mem[ 46] = 32'h00000013;
    dut.Imm.mem[ 47] = 32'h00000013;
    dut.Imm.mem[ 48] = 32'hFF442683;
    dut.Imm.mem[ 49] = 32'h00000013;
    dut.Imm.mem[ 50] = 32'h00000013;
    dut.Imm.mem[ 51] = 32'hFED42C23;
    dut.Imm.mem[ 52] = 32'h00000013;
    dut.Imm.mem[ 53] = 32'h00000013;
    dut.Imm.mem[ 54] = 32'hFEC42683;
    dut.Imm.mem[ 55] = 32'h00000013;
    dut.Imm.mem[ 56] = 32'h00000013;
    dut.Imm.mem[ 57] = 32'hFED42A23;
    dut.Imm.mem[ 58] = 32'h00000013;
    dut.Imm.mem[ 59] = 32'h00000013;
    dut.Imm.mem[ 60] = 32'hFF042683;
    dut.Imm.mem[ 61] = 32'h00000013;
    dut.Imm.mem[ 62] = 32'h00000013;
    dut.Imm.mem[ 63] = 32'h00168693;
    dut.Imm.mem[ 64] = 32'h00000013;
    dut.Imm.mem[ 65] = 32'h00000013;
    dut.Imm.mem[ 66] = 32'hFED42823;
    dut.Imm.mem[ 67] = 32'h00000013;
    dut.Imm.mem[ 68] = 32'h00000013;
    dut.Imm.mem[ 69] = 32'hFF042683;
    dut.Imm.mem[ 70] = 32'h00000013;
    dut.Imm.mem[ 71] = 32'h00000013;
    dut.Imm.mem[ 72] = 32'h01400E93;
    dut.Imm.mem[ 73] = 32'h00000013;
    dut.Imm.mem[ 74] = 32'h00000013;
    dut.Imm.mem[ 75] = 32'hF6DED2E3;
    dut.Imm.mem[ 76] = 32'h00000013;
    dut.Imm.mem[ 77] = 32'h00000013;
    dut.Imm.mem[ 78] = 32'h00000693;
    dut.Imm.mem[ 79] = 32'h00000013;
    dut.Imm.mem[ 80] = 32'h00000013;
    dut.Imm.mem[ 81] = 32'h00068513;
    dut.Imm.mem[ 82] = 32'h00000013;
    dut.Imm.mem[ 83] = 32'h00000013;
    dut.Imm.mem[ 84] = 32'h00040113;
    dut.Imm.mem[ 85] = 32'h00000013;
    dut.Imm.mem[ 86] = 32'h00000013;
    dut.Imm.mem[ 87] = 32'h00012403;
    dut.Imm.mem[ 88] = 32'h00000013;
    dut.Imm.mem[ 89] = 32'h00000013;
    dut.Imm.mem[ 90] = 32'h00410113;
    dut.Imm.mem[ 91] = 32'h00000013;
    dut.Imm.mem[ 92] = 32'h00000013;
    dut.Imm.mem[ 93] = 32'h00000063;
    dut.Imm.mem[ 94] = 32'h00000013;
    dut.Imm.mem[ 95] = 32'h00000013;

    $display("[ICACHE] loaded, HALT byte PC=%0d", HALT_BYTE_PC);
  end
endtask

task load_dcache;
  integer _kd;
  begin
    for (_kd = 0; _kd < 512; _kd = _kd + 1)
      dut.mm_stage_inst.Dmm.mem[_kd] = 32'h00000000;
    $display("[DCACHE] cleared");
  end
endtask

always @(posedge clk) begin
  if (!rst) begin
    if (cycle_cnt <= TRACE_FIRST_N) begin
      if_idx = dut.pc_if >> 2;
      if_instr = dut.Imm.mem[if_idx];
      $display("[cyc %0d] pc=%0d instr=0x%08h", cycle_cnt, dut.pc_if, if_instr);
    end

    if (dut.mm_stage_inst.Dmm.mem[W_TEMP] !== last186 ||
        dut.mm_stage_inst.Dmm.mem[W_I]    !== last187 ||
        dut.mm_stage_inst.Dmm.mem[W_B]    !== last188 ||
        dut.mm_stage_inst.Dmm.mem[W_A]    !== last189) begin

      $display("[cyc %0d] stack w186=%0d w187=%0d w188=%0d w189=%0d",
               cycle_cnt,
               $signed(dut.mm_stage_inst.Dmm.mem[W_TEMP]),
               $signed(dut.mm_stage_inst.Dmm.mem[W_I]),
               $signed(dut.mm_stage_inst.Dmm.mem[W_B]),
               $signed(dut.mm_stage_inst.Dmm.mem[W_A]));

      last186 <= dut.mm_stage_inst.Dmm.mem[W_TEMP];
      last187 <= dut.mm_stage_inst.Dmm.mem[W_I];
      last188 <= dut.mm_stage_inst.Dmm.mem[W_B];
      last189 <= dut.mm_stage_inst.Dmm.mem[W_A];
    end

    if (dut.mm_stage_inst.Dmm.mem[TOHOST_CODE_WORD] !== last_tohost_code ||
        dut.mm_stage_inst.Dmm.mem[TOHOST_DONE_WORD] !== last_tohost_done) begin
      $display("[cyc %0d] tohost code=0x%08h done=0x%08h",
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

  last186 = 32'hxxxxxxxx;
  last187 = 32'hxxxxxxxx;
  last188 = 32'hxxxxxxxx;
  last189 = 32'hxxxxxxxx;

  last_tohost_code = 32'hxxxxxxxx;
  last_tohost_done = 32'hxxxxxxxx;

  rst = 1'b1;
  halt_detected = 1'b0;
  stop_reason = 32'h00000000;

  $display("==============================================");
  $display("RV32I Pipeline TB (fibonacci)");
  $display("HALT_BYTE_PC=%0d  tohost(done)=DMEM[%0d]", HALT_BYTE_PC, TOHOST_DONE_WORD);
  $display("watch stack words: 186..189  expect b(word188)=6765");
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
  check_fib20;

  if (fib_fail == 0) begin
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