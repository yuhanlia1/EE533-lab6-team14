`timescale 1ns/1ps

module tb_4thread_bubble;

  parameter CLK_PERIOD = 10;

  reg clk;
  reg rst;

  pipeline_datapath dut(
    .clk(clk),
    .rst(rst)
  );

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  integer cycle_cnt;
  initial cycle_cnt = 0;
  always @(posedge clk) cycle_cnt = cycle_cnt + 1;

  localparam [31:0] NOP      = 32'h00000013;
  localparam [6:0]  OP_R     = 7'b0110011;
  localparam [6:0]  OP_I     = 7'b0010011;
  localparam [6:0]  OP_LW    = 7'b0000011;
  localparam [6:0]  OP_SW    = 7'b0100011;
  localparam [6:0]  OP_BR    = 7'b1100011;

  localparam [2:0]  F3_ADD   = 3'b000;
  localparam [2:0]  F3_SLL   = 3'b001;
  localparam [2:0]  F3_LW_SW = 3'b010;
  localparam [2:0]  F3_BEQ   = 3'b000;
  localparam [2:0]  F3_BLT   = 3'b100;
  localparam [2:0]  F3_BGE   = 3'b101;

  localparam [6:0]  F7_ADD   = 7'h00;
  localparam [6:0]  F7_SUB   = 7'h20;

  localparam integer N = 12;
  localparam integer MAX_CYCLES = 80000;

  function [31:0] enc_r;
    input [6:0] funct7;
    input [4:0] rs2;
    input [4:0] rs1;
    input [2:0] funct3;
    input [4:0] rd;
    input [6:0] opcode;
    begin
      enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    end
  endfunction

  function [31:0] enc_i;
    input [11:0] imm;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
      enc_i = {imm, rs1, funct3, rd, opcode};
    end
  endfunction

  function [31:0] enc_i_sh;
    input [6:0]  funct7;
    input [4:0]  shamt;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [4:0]  rd;
    input [6:0]  opcode;
    begin
      enc_i_sh = {funct7, shamt, rs1, funct3, rd, opcode};
    end
  endfunction

  function [31:0] enc_s;
    input [11:0] imm;
    input [4:0]  rs2;
    input [4:0]  rs1;
    input [2:0]  funct3;
    input [6:0]  opcode;
    begin
      enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    end
  endfunction

  function [31:0] enc_b;
    input integer off_bytes;
    input [4:0]  rs2;
    input [4:0]  rs1;
    input [2:0]  funct3;
    reg signed [12:0] imm13;
    begin
      imm13 = off_bytes;
      enc_b = {imm13[12], imm13[10:5], rs2, rs1, funct3, imm13[4:1], imm13[11], OP_BR};
    end
  endfunction

  integer pcw;
  integer L_outer;
  integer L_inner;
  integer L_body;
  integer L_swap;
  integer L_halt;
  integer L_common;

  integer P_beq_common0;
  integer P_beq_common1;
  integer P_beq_common2;
  integer P_beq_common3;

  integer P_bge_halt;
  integer P_blt_body;
  integer P_beq_outer;
  integer P_blt_swap;
  integer P_beq_inner_noswap;
  integer P_beq_inner_swap;

  reg [31:0] halt_inst;
  integer off;

  task emit;
    input [31:0] inst;
    begin
      dut.Imm.mem[pcw] = inst;
      pcw = pcw + 1;
    end
  endtask

  task build_icache;
    integer k;
    begin
      for (k = 0; k < 512; k = k + 1) dut.Imm.mem[k] = NOP;

      pcw = 0;

      emit(enc_i(12'd0,   5'd0, F3_ADD, 5'd10, OP_I));
      P_beq_common0 = pcw;
      emit(32'd0);

      emit(enc_i(12'd256, 5'd0, F3_ADD, 5'd10, OP_I));
      P_beq_common1 = pcw;
      emit(32'd0);

      emit(enc_i(12'd512, 5'd0, F3_ADD, 5'd10, OP_I));
      P_beq_common2 = pcw;
      emit(32'd0);

      emit(enc_i(12'd768, 5'd0, F3_ADD, 5'd10, OP_I));
      P_beq_common3 = pcw;
      emit(32'd0);

      L_common = pcw;

      emit(enc_i(N[11:0],  5'd0,  F3_ADD, 5'd12, OP_I));
      emit(enc_i(12'hFFF,  5'd12, F3_ADD, 5'd13, OP_I));

      emit(enc_i(12'd0,    5'd0,  F3_ADD, 5'd5,  OP_I));

      L_outer = pcw;

      P_bge_halt = pcw;
      emit(32'd0);

      emit(enc_r(F7_SUB, 5'd5, 5'd13, F3_ADD, 5'd7, OP_R));
      emit(enc_i_sh(F7_ADD, 5'd2, 5'd7, F3_SLL, 5'd14, OP_I));
      emit(enc_i(12'd0, 5'd0, F3_ADD, 5'd6, OP_I));

      L_inner = pcw;

      P_blt_body = pcw;
      emit(32'd0);

      emit(enc_i(12'd1, 5'd5, F3_ADD, 5'd5, OP_I));
      P_beq_outer = pcw;
      emit(32'd0);

      L_body = pcw;

      emit(enc_r(F7_ADD, 5'd6, 5'd10, F3_ADD, 5'd11, OP_R));
      emit(enc_i(12'd0, 5'd11, F3_LW_SW, 5'd8, OP_LW));
      emit(enc_i(12'd4, 5'd11, F3_ADD, 5'd15, OP_I));
      emit(enc_i(12'd0, 5'd15, F3_LW_SW, 5'd9, OP_LW));

      P_blt_swap = pcw;
      emit(32'd0);

      emit(enc_i(12'd4, 5'd6, F3_ADD, 5'd6, OP_I));
      P_beq_inner_noswap = pcw;
      emit(32'd0);

      L_swap = pcw;

      emit(enc_s(12'd0, 5'd9, 5'd11, F3_LW_SW, OP_SW));
      emit(enc_s(12'd0, 5'd8, 5'd15, F3_LW_SW, OP_SW));
      emit(enc_i(12'd4, 5'd6, F3_ADD, 5'd6, OP_I));
      P_beq_inner_swap = pcw;
      emit(32'd0);

      L_halt = pcw;
      halt_inst = enc_b(0, 5'd0, 5'd0, F3_BEQ);
      emit(halt_inst);

      off = (L_common - P_beq_common0) * 4;
      dut.Imm.mem[P_beq_common0] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_common - P_beq_common1) * 4;
      dut.Imm.mem[P_beq_common1] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_common - P_beq_common2) * 4;
      dut.Imm.mem[P_beq_common2] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_common - P_beq_common3) * 4;
      dut.Imm.mem[P_beq_common3] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_halt - P_bge_halt) * 4;
      dut.Imm.mem[P_bge_halt] = enc_b(off, 5'd13, 5'd5, F3_BGE);

      off = (L_body - P_blt_body) * 4;
      dut.Imm.mem[P_blt_body] = enc_b(off, 5'd14, 5'd6, F3_BLT);

      off = (L_outer - P_beq_outer) * 4;
      dut.Imm.mem[P_beq_outer] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_swap - P_blt_swap) * 4;
      dut.Imm.mem[P_blt_swap] = enc_b(off, 5'd8, 5'd9, F3_BLT);

      off = (L_inner - P_beq_inner_noswap) * 4;
      dut.Imm.mem[P_beq_inner_noswap] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      off = (L_inner - P_beq_inner_swap) * 4;
      dut.Imm.mem[P_beq_inner_swap] = enc_b(off, 5'd0, 5'd0, F3_BEQ);

      $display("ICACHE built: L_common=%0d L_outer=%0d L_inner=%0d L_body=%0d L_swap=%0d L_halt=%0d", L_common, L_outer, L_inner, L_body, L_swap, L_halt);
    end
  endtask

  reg signed [31:0] init0 [0:N-1];
  reg signed [31:0] init1 [0:N-1];
  reg signed [31:0] init2 [0:N-1];
  reg signed [31:0] init3 [0:N-1];
  reg signed [31:0] exp0  [0:N-1];
  reg signed [31:0] exp1  [0:N-1];
  reg signed [31:0] exp2  [0:N-1];
  reg signed [31:0] exp3  [0:N-1];

  task init_data;
    begin
      init0[0]=5;  init0[1]=-1; init0[2]=2;  init0[3]=4;
      init0[4]=10; init0[5]=8;  init0[6]=3;  init0[7]=-7;
      init0[8]=6;  init0[9]=0;  init0[10]=9; init0[11]=-2;

      init1[0]=9;  init1[1]=1;  init1[2]=7;  init1[3]=2;
      init1[4]=-3; init1[5]=4;  init1[6]=8;  init1[7]=5;
      init1[8]=-6; init1[9]=3;  init1[10]=6; init1[11]=-1;

      init2[0]=12; init2[1]=11; init2[2]=10; init2[3]=9;
      init2[4]=8;  init2[5]=7;  init2[6]=6;  init2[7]=5;
      init2[8]=4;  init2[9]=3;  init2[10]=2; init2[11]=1;

      init3[0]=0;  init3[1]=-5; init3[2]=5;  init3[3]=-4;
      init3[4]=4;  init3[5]=-3; init3[6]=3;  init3[7]=-2;
      init3[8]=2;  init3[9]=-1; init3[10]=1; init3[11]=0;
    end
  endtask

  task bubble_expected;
    input integer which;
    integer a,b;
    reg signed [31:0] tmp;
    begin
      for (a=0; a<N; a=a+1) begin
        case(which)
          0: exp0[a]=init0[a];
          1: exp1[a]=init1[a];
          2: exp2[a]=init2[a];
          3: exp3[a]=init3[a];
        endcase
      end
      for (a=0; a<N-1; a=a+1) begin
        for (b=0; b<N-1-a; b=b+1) begin
          case(which)
            0: if (exp0[b] > exp0[b+1]) begin tmp=exp0[b]; exp0[b]=exp0[b+1]; exp0[b+1]=tmp; end
            1: if (exp1[b] > exp1[b+1]) begin tmp=exp1[b]; exp1[b]=exp1[b+1]; exp1[b+1]=tmp; end
            2: if (exp2[b] > exp2[b+1]) begin tmp=exp2[b]; exp2[b]=exp2[b+1]; exp2[b+1]=tmp; end
            3: if (exp3[b] > exp3[b+1]) begin tmp=exp3[b]; exp3[b]=exp3[b+1]; exp3[b+1]=tmp; end
          endcase
        end
      end
    end
  endtask

  task load_all_dmem;
    integer k;
    begin
      for (k=0; k<512; k=k+1) dut.mm_stage_inst.Dmm.mem[k]=32'd0;
      for (k=0; k<N; k=k+1) begin
        dut.mm_stage_inst.Dmm.mem[(0<<6)+k] = init0[k];
        dut.mm_stage_inst.Dmm.mem[(1<<6)+k] = init1[k];
        dut.mm_stage_inst.Dmm.mem[(2<<6)+k] = init2[k];
        dut.mm_stage_inst.Dmm.mem[(3<<6)+k] = init3[k];
      end
    end
  endtask

  task dump_segment;
    input integer tid;
    integer k;
    integer base;
    begin
      base = tid << 6;
      $display("\nDMEM segment T%0d (base=%0d):", tid, base);
      for (k=0; k<N; k=k+1) begin
        $display("  dmem[%0d]=%0d", k, $signed(dut.mm_stage_inst.Dmm.mem[base+k]));
      end
    end
  endtask

  task check_segment;
    input integer tid;
    integer k;
    integer base;
    integer fails;
    reg signed [31:0] got;
    reg signed [31:0] exp;
    begin
      base = tid << 6;
      fails = 0;
      for (k=0; k<N; k=k+1) begin
        got = $signed(dut.mm_stage_inst.Dmm.mem[base+k]);
        case(tid)
          0: exp = exp0[k];
          1: exp = exp1[k];
          2: exp = exp2[k];
          default: exp = exp3[k];
        endcase
        if (got !== exp) begin
          $display("T%0d FAIL [%0d] got=%0d exp=%0d", tid, k, got, exp);
          fails = fails + 1;
        end
      end
      if (fails==0) $display("T%0d PASS", tid);
      else $display("T%0d TOTAL FAILS=%0d (segment base=%0d)", tid, fails, base);
    end
  endtask

  reg halted0, halted1, halted2, halted3;

  wire [1:0] tid_id;
  assign tid_id = dut.tid_id;

  integer cyc;

  task dbg_print;
    begin
      $display("C%0d t=%0t | IF:tid=%0d pc=%h instr=%h | ID:tid=%0d pc=%h instr=%h jump=%b tgt=%h | WB:we=%b tid=%0d rd=%0d data=%h",
        cycle_cnt, $time,
        dut.tid_sel, dut.pc_if, dut.instr_in,
        dut.tid_id, dut.pc_id, dut.instr_id,
        dut.jump_valid_id, dut.addr_id,
        dut.wb_wreg_out, dut.wb_tid_out, dut.wb_rd_out, dut.wb_data_out
      );
    end
  endtask

  initial begin
    $timeformat(-9,0," ns",0);

    rst = 1'b1;
    halted0 = 1'b0;
    halted1 = 1'b0;
    halted2 = 1'b0;
    halted3 = 1'b0;

    init_data;
    bubble_expected(0);
    bubble_expected(1);
    bubble_expected(2);
    bubble_expected(3);

    @(posedge clk);
    @(posedge clk);

    build_icache;
    load_all_dmem;

    @(negedge clk);
    rst = 1'b0;

    dut.pc_inst.pc_thr[0] = 11'd0;
    dut.pc_inst.pc_thr[1] = 11'd8;
    dut.pc_inst.pc_thr[2] = 11'd16;
    dut.pc_inst.pc_thr[3] = 11'd24;

    $display("[%0t] start", $time);

    begin : run_loop
      for (cyc = 0; cyc < MAX_CYCLES; cyc = cyc + 1) begin
        @(posedge clk);

        if (cycle_cnt < 80) dbg_print;
        else if (dut.jump_valid_id) dbg_print;
        else if (dut.wb_wreg_out) dbg_print;

        if ((dut.instr_id == halt_inst) && (dut.pc_id[10:2] == L_halt[8:0])) begin
          case (tid_id)
            2'd0: halted0 = 1'b1;
            2'd1: halted1 = 1'b1;
            2'd2: halted2 = 1'b1;
            2'd3: halted3 = 1'b1;
          endcase
        end

        if (halted0 && halted1 && halted2 && halted3) begin
          $display("[%0t] ALL THREADS HALTED (cyc=%0d)", $time, cycle_cnt);
          disable run_loop;
        end
      end
    end

    if (!(halted0 && halted1 && halted2 && halted3)) begin
      $display("TIMEOUT: not all threads halted in %0d cycles", MAX_CYCLES);
    end

    $display("\nCHECK RESULTS:");
    check_segment(0);
    check_segment(1);
    check_segment(2);
    check_segment(3);

    dump_segment(0);
    dump_segment(1);
    dump_segment(2);
    dump_segment(3);

    $finish;
  end

endmodule