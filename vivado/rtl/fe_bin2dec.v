`timescale 1ns/1ps
// fe_bin2dec.v — 32 位二进制转十进制 ASCII（10 次除 10 + 反转，两拍流水）
// digits[7:0] 为最高位数字（便于从高位流式输出），ndigits 为有效位数。
module fe_bin2dec(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] value,
    output reg         done,          // 单周期脉冲
    output reg  [79:0] digits,        // ASCII，digits[7:0] = 最高位
    output reg  [3:0]  ndigits
);
    localparam S_IDLE = 0, S_DIV = 1, S_REV = 2;

    reg [1:0]  state;
    reg [31:0] v;
    reg [3:0]  idx;
    reg [3:0]  digs [0:9];

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0; ndigits <= 0; digits <= 0; v <= 0; idx <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    if (value == 0) begin
                        digits  <= 80'h30;
                        ndigits <= 4'd1;
                        done    <= 1'b1;
                    end else begin
                        v <= value; idx <= 0; state <= S_DIV;
                    end
                end
                S_DIV: begin
                    digs[idx] <= v % 10;
                    v   <= v / 10;
                    idx <= idx + 1;
                    if (v / 10 == 0) begin
                        idx <= idx + 1;
                        state <= S_REV;
                    end
                end
                S_REV: begin
                    ndigits <= idx;
                    for (integer j = 0; j < 10; j = j + 1) begin
                        if (j < idx)
                            digits[j*8 +: 8] = 8'h30 + digs[idx - 1 - j];
                    end
                    state <= S_IDLE;
                    done  <= 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
