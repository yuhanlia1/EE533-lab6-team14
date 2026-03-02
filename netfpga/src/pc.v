// -------------------- PC (byte PC) --------------------
module pc (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        jump_valid,
    input  wire [10:0] jump_addr,
    output reg  [10:0] pc,
    output wire [10:0] pc_next
);

assign pc_next = jump_valid ? jump_addr : (pc + 11'd4);

always @(posedge clk) begin
    if (rst) begin
        pc <= 11'd0;
    end else if (enable) begin
        pc <= pc_next;
    end else begin
        pc <= pc;
    end
end

endmodule