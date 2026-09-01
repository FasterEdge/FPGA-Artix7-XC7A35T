// ─────────────────────────────────────────────────────────────
// FasterEdge 开源项目
// Github: https://github.com/FasterEdge
// Gitee:  https://gitee.com/FasterEdge
// ─────────────────────────────────────────────────────────────
`timescale 1ns/1ps
// fe_sha256_block.v — SHA-256 单块压缩核（迭代，64 轮）
// init_state 为链接变量输入（8×32bit，state[255:224] = 字 A）；
// 标准散列请传 H0 常量（本文件下方注释）。
// 一块约 114 周期（装载 + 调度 48 + 轮函数 64 + 收尾）。
module fe_sha256_block(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [255:0] init_state,     // [255:224]=H[0] ... [31:0]=H[7]
    input  wire [511:0] block_in,       // 字节序：block_in[511:504] = 第 0 字节
    output reg          busy,
    output reg          done,
    output reg  [255:0] state_out       // 同 init_state 布局
);
    localparam S_IDLE = 3'd0, S_SCHED = 3'd1, S_ROUND = 3'd2, S_ADD = 3'd3;

    reg [2:0]  state;
    reg [5:0]  t;
    reg [31:0] w [0:63];
    reg [31:0] a, b, c, d, e, f, g, h;
    reg [255:0] init_q;                  // 收尾加回"传入的链接变量"（非 H0）

    // ---- 轮调度组合逻辑（t>=16） ----
    wire [31:0] w_s0 = {w[t-15][6:0],  w[t-15][31:7]}    // rotr 7
                     ^ {w[t-15][17:0],w[t-15][31:18]}    // rotr 18
                     ^ {3'b0,  w[t-15][31:3]};           // shr 3
    wire [31:0] w_s1 = {w[t-2][16:0], w[t-2][31:17]}     // rotr 17
                     ^ {w[t-2][18:0], w[t-2][31:19]}     // rotr 19
                     ^ {10'b0, w[t-2][31:10]};           // shr 10
    wire [31:0] w_next = w[t-16] + w_s0 + w[t-7] + w_s1;

    // ---- 轮函数组合逻辑 ----
    wire [31:0] big_s1 = {e[5:0],  e[31:6]} ^ {e[10:0], e[31:11]} ^ {e[24:0], e[31:25]};
    wire [31:0] ch     = (e & f) ^ (~e & g);
    wire [31:0] big_s0 = {a[1:0],  a[31:2]} ^ {a[12:0], a[31:13]} ^ {a[21:0], a[31:22]};
    wire [31:0] maj    = (a & b) ^ (a & c) ^ (b & c);

    function [31:0] kconst(input [5:0] r);
        begin
            case (r)
                6'd0:  kconst=32'h428a2f98; 6'd1:  kconst=32'h71374491; 6'd2:  kconst=32'hb5c0fbcf; 6'd3:  kconst=32'he9b5dba5;
                6'd4:  kconst=32'h3956c25b; 6'd5:  kconst=32'h59f111f1; 6'd6:  kconst=32'h923f82a4; 6'd7:  kconst=32'hab1c5ed5;
                6'd8:  kconst=32'hd807aa98; 6'd9:  kconst=32'h12835b01; 6'd10: kconst=32'h243185be; 6'd11: kconst=32'h550c7dc3;
                6'd12: kconst=32'h72be5d74; 6'd13: kconst=32'h80deb1fe; 6'd14: kconst=32'h9bdc06a7; 6'd15: kconst=32'hc19bf174;
                6'd16: kconst=32'he49b69c1; 6'd17: kconst=32'hefbe4786; 6'd18: kconst=32'h0fc19dc6; 6'd19: kconst=32'h240ca1cc;
                6'd20: kconst=32'h2de92c6f; 6'd21: kconst=32'h4a7484aa; 6'd22: kconst=32'h5cb0a9dc; 6'd23: kconst=32'h76f988da;
                6'd24: kconst=32'h983e5152; 6'd25: kconst=32'ha831c66d; 6'd26: kconst=32'hb00327c8; 6'd27: kconst=32'hbf597fc7;
                6'd28: kconst=32'hc6e00bf3; 6'd29: kconst=32'hd5a79147; 6'd30: kconst=32'h06ca6351; 6'd31: kconst=32'h14292967;
                6'd32: kconst=32'h27b70a85; 6'd33: kconst=32'h2e1b2138; 6'd34: kconst=32'h4d2c6dfc; 6'd35: kconst=32'h53380d13;
                6'd36: kconst=32'h650a7354; 6'd37: kconst=32'h766a0abb; 6'd38: kconst=32'h81c2c92e; 6'd39: kconst=32'h92722c85;
                6'd40: kconst=32'ha2bfe8a1; 6'd41: kconst=32'ha81a664b; 6'd42: kconst=32'hc24b8b70; 6'd43: kconst=32'hc76c51a3;
                6'd44: kconst=32'hd192e819; 6'd45: kconst=32'hd6990624; 6'd46: kconst=32'hf40e3585; 6'd47: kconst=32'h106aa070;
                6'd48: kconst=32'h19a4c116; 6'd49: kconst=32'h1e376c08; 6'd50: kconst=32'h2748774c; 6'd51: kconst=32'h34b0bcb5;
                6'd52: kconst=32'h391c0cb3; 6'd53: kconst=32'h4ed8aa4a; 6'd54: kconst=32'h5b9cca4f; 6'd55: kconst=32'h682e6ff3;
                6'd56: kconst=32'h748f82ee; 6'd57: kconst=32'h78a5636f; 6'd58: kconst=32'h84c87814; 6'd59: kconst=32'h8cc70208;
                6'd60: kconst=32'h90befffa; 6'd61: kconst=32'ha4506ceb; 6'd62: kconst=32'hbef9a3f7; default: kconst=32'hc67178f2;
            endcase
        end
    endfunction

    function [31:0] h0w(input [2:0] i);
        case (i)
            3'd0: h0w = 32'h6a09e667; 3'd1: h0w = 32'hbb67ae85;
            3'd2: h0w = 32'h3c6ef372; 3'd3: h0w = 32'ha54ff53a;
            3'd4: h0w = 32'h510e527f; 3'd5: h0w = 32'h9b05688c;
            3'd6: h0w = 32'h1f83d9ab; default: h0w = 32'h5be0cd19;
        endcase
    endfunction

    wire [31:0] tmp1 = h + big_s1 + ch + kconst(t) + w[t];
    wire [31:0] tmp2 = big_s0 + maj;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0; t <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        // 装载 16 个消息字 + 初始链接变量
                        w[0]  = block_in[511 -: 32];  w[1]  = block_in[479 -: 32];
                        w[2]  = block_in[447 -: 32];  w[3]  = block_in[415 -: 32];
                        w[4]  = block_in[383 -: 32];  w[5]  = block_in[351 -: 32];
                        w[6]  = block_in[319 -: 32];  w[7]  = block_in[287 -: 32];
                        w[8]  = block_in[255 -: 32];  w[9]  = block_in[223 -: 32];
                        w[10] = block_in[191 -: 32];  w[11] = block_in[159 -: 32];
                        w[12] = block_in[127 -: 32];  w[13] = block_in[95  -: 32];
                        w[14] = block_in[63  -: 32];  w[15] = block_in[31  -: 32];
                        a = init_state[255:224]; b = init_state[223:192];
                        c = init_state[191:160]; d = init_state[159:128];
                        e = init_state[127:96];  f = init_state[95:64];
                        g = init_state[63:32];   h = init_state[31:0];
                        init_q = init_state;
                        t <= 6'd16;
                        busy <= 1'b1;
                        state <= S_SCHED;
                    end
                end
                S_SCHED: begin
                    w[t] <= w_next;
                    if (t == 6'd63) begin
                        t <= 6'd0;
                        state <= S_ROUND;
                    end else t <= t + 1;
                end
                S_ROUND: begin
                    {h, g, f, e} <= {g, f, e, d + tmp1};
                    {d, c, b, a} <= {c, b, a, tmp1 + tmp2};
                    if (t == 6'd63) begin
                        t <= 6'd0;
                        state <= S_ADD;
                    end else t <= t + 1;
                end
                S_ADD: begin
                    state_out = {a + init_q[255:224], b + init_q[223:192],
                                 c + init_q[191:160], d + init_q[159:128],
                                 e + init_q[127:96],  f + init_q[95:64],
                                 g + init_q[63:32],   h + init_q[31:0]};
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
