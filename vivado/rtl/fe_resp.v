`timescale 1ns/1ps
// fe_resp.v — 通用分段响应发送器（valid/ready 字节流）
// 最多 3 段，每段为"右对齐字符串常量/缓冲 + 长度"（长度须 ≥1）。
// 动态内容（数字、令牌等）由上层预先拼入段缓冲再启动。
module fe_resp(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,        // 单周期脉冲，段寄存器须已就绪
    input  wire [1:0]   nsegs,        // 1..3
    input  wire [1023:0] s0dat, input wire [7:0] s0len,
    input  wire [1023:0] s1dat, input wire [7:0] s1len,
    input  wire [1023:0] s2dat, input wire [7:0] s2len,
    output reg          resp_valid,
    output reg  [7:0]   resp_data,
    input  wire         resp_ready,
    output reg          resp_done
);
    reg [1:0] seg;
    reg [7:0] idx;
    reg [7:0] cur_len;
    reg [1023:0] cur_dat;
    reg       running;

    wire [7:0] out_byte = cur_dat[(cur_len-1-idx)*8 +: 8];

    always @(posedge clk) begin
        if (rst) begin
            resp_valid <= 0; resp_data <= 0; resp_done <= 0;
            seg <= 0; idx <= 0; cur_len <= 0; cur_dat <= 0; running <= 0;
        end else begin
            resp_done <= 1'b0;
            if (!running) begin
                resp_valid <= 1'b0;
                if (start) begin
                    seg     <= 2'd0;
                    idx     <= 0;
                    cur_dat <= s0dat;
                    cur_len <= s0len;
                    running <= 1'b1;
                end
            end else begin
                resp_valid <= 1'b1;
                resp_data  <= out_byte;
                if (resp_ready) begin
                    if (idx + 1 >= cur_len) begin
                        if (seg + 1 >= nsegs) begin
                            // 最后一个字节保持 valid=1，等消费方取走；
                            // 下一拍 !running 分支会把 valid 拉低。
                            resp_done  <= 1'b1;
                            running    <= 1'b0;
                        end else begin
                            seg <= seg + 1;
                            idx <= 0;
                            if (seg == 2'd0) begin
                                cur_dat <= s1dat; cur_len <= s1len;
                            end else begin
                                cur_dat <= s2dat; cur_len <= s2len;
                            end
                        end
                    end else begin
                        idx <= idx + 1;
                    end
                end
            end
        end
    end
endmodule
