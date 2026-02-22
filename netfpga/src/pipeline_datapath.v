`timescale 1ns/1ps
`include "../include/registers.v"

module pipeline_datapath
#(
    parameter UDP_REG_SRC_WIDTH = 2
)
(
    input                                clk,
    input                                reset,

    input                               reg_req_in,
    input                               reg_ack_in,
    input                               reg_rd_wr_L_in,
    input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
    input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
    input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

    output                              reg_req_out,
    output                              reg_ack_out,
    output                              reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0]      reg_src_out
);

wire [31:0] sw_imem_ctrl;
wire [31:0] sw_imem_write;
wire [31:0] sw_imem_addr;
wire [31:0] sw_imem_wdata;

wire [31:0] sw_dmem_ctrl;
wire [31:0] sw_dmem_write;
wire [31:0] sw_dmem_addr;
wire [31:0] sw_dmem_wdata;

wire [31:0] sw_dbg_regsel;

reg  [31:0] hw_imem_rdata;
reg  [31:0] hw_dmem_rdata;

reg  [31:0] hw_dbg_rdata;

wire imem_interact_en;
wire imem_sw_we;
wire dmem_interact_en;
wire dmem_sw_we;

assign imem_interact_en = sw_imem_ctrl[0];
assign imem_sw_we       = sw_imem_write[0];

assign dmem_interact_en = sw_dmem_ctrl[0];
assign dmem_sw_we       = sw_dmem_write[0];

wire core_enable;
assign core_enable = ~(imem_interact_en | dmem_interact_en);

wire en_reg;
assign en_reg = core_enable;

wire [10:0] pc_if;
wire [10:0] pc_new;
wire        flush_in_raw;
wire        flush_in;

wire [31:0] instr_in;

wire [10:0] pc_id;
wire [31:0] instr_id;
wire        flush_out;

wire [31:0] imm_id;
wire [10:0] addr_id;
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

wire [31:0] alu_ex;
wire [31:0] rd2_ex_o;
wire        wreg_ex_o;
wire [4:0]  rd_ex_o;
wire        WMM_ex_o;
wire        RMM_ex_o;
wire        MOA_ex_o;
wire        jal_jalr_ex_o;

wire [31:0] alu_mem_in;
wire [31:0] rd2_mem_in;
wire        wreg_mem_in;
wire [4:0]  rd_mem_in;
wire        WMM_mem_in;
wire        RMM_mem_in;
wire        MOA_mem_in;
wire        jal_jalr_mem_in;

wire [31:0] alu_mm;
wire [31:0] mem_mm;
wire        wreg_mm;
wire [4:0]  rd_mm;
wire        MOA_mm;

wire [31:0] wb_data_out;
wire        wb_wreg_out;
wire [4:0]  wb_rd_out;

wire [31:0] alu_mm_wb;
wire [31:0] mem_mm_wb;
wire        wreg_mm_wb;
wire [4:0]  rd_mm_wb;
wire        MOA_mm_wb;

assign flush_in_raw = jump_valid_id;
assign flush_in     = flush_in_raw & en_reg;
assign pc_new       = addr_id;

wire wb_wreg_core;
assign wb_wreg_core = wb_wreg_out & en_reg;

wire [8:0]  imem_addr_final;
wire [31:0] imem_din_final;
wire        imem_we_final;

assign imem_addr_final = imem_interact_en ? sw_imem_addr[8:0] : pc_if[10:2];
assign imem_din_final  = sw_imem_wdata;
assign imem_we_final   = imem_interact_en & imem_sw_we;

wire [4:0]  dbg_raddr;
wire [31:0] dbg_rdata;

assign dbg_raddr = sw_dbg_regsel[4:0];

always @(posedge clk) begin
    if (reset) begin
        hw_imem_rdata <= 32'hDEADBEEF;
    end else begin
        if (imem_interact_en && !imem_we_final) begin
            hw_imem_rdata <= instr_in;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        hw_dmem_rdata <= 32'hDEADBEEF;
    end else begin
        if (dmem_interact_en && !dmem_sw_we) begin
            hw_dmem_rdata <= mem_mm;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        hw_dbg_rdata <= 32'hDEADBEEF;
    end else begin
        hw_dbg_rdata <= dbg_rdata;
    end
end

pc pc_inst(
  .clk        (clk),
  .rst        (reset),
  .enable     (en_reg),
  .jump_valid (flush_in),
  .jump_addr  (pc_new),
  .pc         (pc_if)
);

Icache Imm(
  .clk  (clk),
  .addr (imem_addr_final),
  .din  (imem_din_final),
  .dout (instr_in),
  .we   (imem_we_final)
);

if_id_reg if_id_reg_inst (
  .clk      (clk),
  .rst      (reset),
  .enable   (en_reg),
  .wist     (flush_in),
  .pc_in    (pc_if),
  .inst_in  (instr_in),
  .pc_out   (pc_id),
  .inst_out (instr_id),
  .wist_out (flush_out)
);

id_stage id_stage_inst (
  .clk        (clk),
  .rst        (reset),
  .pc_in      (pc_id),
  .inst_in    (instr_id),

  .wb_rd_addr (wb_rd_out),
  .wb_data    (wb_data_out),
  .wb_wea     (wb_wreg_core),

  .wist       (flush_out),

  .dbg_addr   (dbg_raddr),
  .dbg_rdata   (dbg_rdata),

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

id_ex_reg id_ex_inst (
  .clk         (clk),
  .rst         (reset),
  .enable      (en_reg),

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

ex_stage ex_stage_inst (
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

  .alu_out      (alu_ex),
  .rd2_out      (rd2_ex_o),
  .wreg_out     (wreg_ex_o),
  .rd_out       (rd_ex_o),
  .WMM_out      (WMM_ex_o),
  .RMM_out      (RMM_ex_o),
  .MOA_out      (MOA_ex_o),
  .jal_jalr_out (jal_jalr_ex_o)
);

ex_mm_reg ex_mm_reg_inst (
  .clk         (clk),
  .rst         (reset),
  .enable      (en_reg),

  .alu_in      (alu_ex),
  .rd2_in      (rd2_ex_o),
  .wreg_in     (wreg_ex_o),
  .rd_in       (rd_ex_o),
  .WMM_in      (WMM_ex_o),
  .RMM_in      (RMM_ex_o),
  .MOA_in      (MOA_ex_o),
  .jal_jalr_in (jal_jalr_ex_o),

  .alu_out     (alu_mem_in),
  .rd2_out     (rd2_mem_in),
  .wreg_out    (wreg_mem_in),
  .rd_out      (rd_mem_in),
  .WMM_out     (WMM_mem_in),
  .RMM_out     (RMM_mem_in),
  .MOA_out     (MOA_mem_in),
  .jal_jalr_out(jal_jalr_mem_in)
);

mm_stage mm_stage_inst (
  .clk              (clk),

  .alu_in_bypass    (alu_ex),			// don't delete: bypass from ex stage
  .alu_in			(alu_mem_in),
  .rd2_in_bypass    (rd2_ex_o),			// don't delete: bypass from ex stage
  .rd2_in		    (rd2_mem_in),
  .wreg_in          (wreg_mem_in),
  .rd_in            (rd_mem_in),
  .WMM_in           (WMM_ex_o),			// don't delete: bypass from ex stage
  .RMM_in           (RMM_ex_o),			// don't delete: bypass from ex stage
  .MOA_in           (MOA_mem_in),
  .jal_jalr_in      (jal_jalr_mem_in),

  .dmem_interact_en (dmem_interact_en),
  .dmem_sw_addr     (sw_dmem_addr[8:0]),
  .dmem_sw_wdata    (sw_dmem_wdata),
  .dmem_sw_we       (dmem_sw_we),

  .alu_out          (alu_mm),			
  .mem_out          (mem_mm),
  .wreg_out         (wreg_mm),
  .rd_out           (rd_mm),
  .MOA_out          (MOA_mm)
);

mm_wb_reg mm_wb_reg_inst (
  .clk      (clk),
  .rst      (reset),
  .enable   (en_reg),

  .alu_in   (alu_mm),				
  .mem_in   (mem_mm),
  .wreg_in  (wreg_mm),
  .rd_in    (rd_mm),
  .MOA_in   (MOA_mm),

  .alu_out  (alu_mm_wb),
  .mem_out  (mem_mm_wb),
  .wreg_out (wreg_mm_wb),
  .rd_out   (rd_mm_wb),
  .MOA_out  (MOA_mm_wb)
);

wb_stage wb_stage_inst (
  .alu_in      (alu_mm_wb),
  .mem_in      (mem_mm_wb),
  .wreg_in     (wreg_mm_wb),
  .rd_in       (rd_mm_wb),
  .MOA_in      (MOA_mm_wb),

  .wb_data_out (wb_data_out),
  .wreg_out    (wb_wreg_out),
  .rd_out      (wb_rd_out)
);

generic_regs
#(
    .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
`ifdef PIPE_BLOCK_ADDR
    .TAG                 (`PIPE_BLOCK_ADDR),
    .REG_ADDR_WIDTH      (`PIPE_REG_ADDR_WIDTH),
`else
    .TAG                 (`PIPELINE_DATAPATH_BLOCK_ADDR),
    .REG_ADDR_WIDTH      (`PIPELINE_DATAPATH_REG_ADDR_WIDTH),
`endif
    .NUM_COUNTERS        (0),
    .NUM_SOFTWARE_REGS   (9),
    .NUM_HARDWARE_REGS   (3)
) module_regs (
    .reg_req_in       (reg_req_in),
    .reg_ack_in       (reg_ack_in),
    .reg_rd_wr_L_in   (reg_rd_wr_L_in),
    .reg_addr_in      (reg_addr_in),
    .reg_data_in      (reg_data_in),
    .reg_src_in       (reg_src_in),

    .reg_req_out      (reg_req_out),
    .reg_ack_out      (reg_ack_out),
    .reg_rd_wr_L_out  (reg_rd_wr_L_out),
    .reg_addr_out     (reg_addr_out),
    .reg_data_out     (reg_data_out),
    .reg_src_out      (reg_src_out),

    .counter_updates  (),
    .counter_decrement(),

    .software_regs    ({
        sw_dbg_regsel,

        sw_dmem_wdata,
        sw_dmem_addr,
        sw_dmem_write,
        sw_dmem_ctrl,
        sw_imem_wdata,
        sw_imem_addr,
        sw_imem_write,
        sw_imem_ctrl
    }),

    .hardware_regs    ({
        hw_dbg_rdata,

        hw_dmem_rdata,
        hw_imem_rdata
    }),

    .clk              (clk),
    .reset            (reset)
);

endmodule