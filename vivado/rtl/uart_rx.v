// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// uart_rx.v — UART 8N1 接收（100MHz 类时钟域，中点采样）
module uart_rx #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid          // 单周期脉冲
);
    localparam integer BIT_PERIOD = CLK_FREQ / BAUD;

    reg [1:0] sync;
    reg       rx_prev;
    always @(posedge clk) begin
        if (rst) begin
            // UART idles high.  Resetting the synchronizer to idle prevents
            // X propagation and a false start edge immediately after reset.
            sync    <= 2'b11;
            rx_prev <= 1'b1;
        end else begin
            sync    <= {sync[0], rx};
            rx_prev <= sync[1];
        end
    end
    wire rx_s = sync[1];
    wire fall = rx_prev & ~rx_s;

    reg [15:0] cnt;
    reg [3:0]  bits;
    reg [7:0]  sh;
    reg        running;

    always @(posedge clk) begin
        if (rst) begin
            running <= 1'b0; valid <= 1'b0; cnt <= 0; bits <= 0; sh <= 0;
        end else begin
            valid <= 1'b0;
            if (!running) begin
                if (fall) begin
                    running <= 1'b1;
                    cnt <= BIT_PERIOD[15:0] / 2;   // 等到起始位中点
                    bits <= 0;
                end
            end else begin
                if (cnt != 0) begin
                    cnt <= cnt - 1;
                end else begin
                    cnt <= BIT_PERIOD[15:0] - 1;
                    if (bits == 0) begin
                        // 起始位中点：确认仍为 0
                        if (rx_s) running <= 1'b0;
                        else bits <= 1;
                    end else if (bits < 9) begin
                        sh  <= {rx_s, sh[7:1]};
                        bits <= bits + 1;
                    end else begin
                        // 停止位
                        running <= 1'b0;
                        if (rx_s) begin
                            data  <= sh;
                            valid <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
