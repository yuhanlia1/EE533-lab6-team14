// pc模块, pc_addr = 9bit

module pc (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire       jump_valid,
    input  wire [8:0] jump_addr,
    output reg  [8:0] pc,
    output wire [8:0] pc_next
);

assign pc_next = jump_valid ? jump_addr : (pc + 9'd1);

always @(posedge clk) begin
    if (rst) begin
        pc <= 9'd0;
    end else if (enable) begin
        pc <= pc_next;
    end else begin
        pc <= pc;   // 可省略：不写 else 也会保持
    end
end

endmodule