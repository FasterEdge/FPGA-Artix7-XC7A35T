// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// uart_tx.v — UART 8N1 发送（起始位 + 8 数据位 LSB 先行 + 停止位）
module uart_tx #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,         // busy 为低时接受
    input  wire [7:0] data,
    output wire       tx,
    output reg        busy
);
    localparam integer BIT_PERIOD = CLK_FREQ / BAUD;

    reg  [15:0] cnt;
    reg  [3:0]  bits;
    reg  [9:0]  frame;                 // frame[0]=起始位0, [8:1]=数据LSB先行, [9]=停止位1

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; cnt <= 0; bits <= 0; frame <= 10'h3FF;
        end else if (!busy) begin
            if (start) begin
                frame <= {1'b1, data, 1'b0};
                busy  <= 1'b1;
                cnt   <= BIT_PERIOD[15:0];
                bits  <= 4'd0;
            end
        end else begin
            if (cnt != 0) begin
                cnt <= cnt - 1;
            end else begin
                cnt <= BIT_PERIOD[15:0];
                if (bits == 4'd9)
                    busy <= 1'b0;      // 停止位结束
                else
                    bits <= bits + 1;
            end
        end
    end

    assign tx = busy ? frame[bits] : 1'b1;

endmodule
