// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// fe_ability_time.v — TimeAbility：sync_manual / sync_system / get_time /
//                      sync_ntp / configure_run
// 纯 FPGA 无网络：sync_ntp 返回错误（与 MCU 版移植层返回 -1 一致）。
module fe_ability_time #(
    parameter integer CLK_FREQ = 100000000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [255:0] act,
    input  wire [511:0] args,
    output reg         resp_start,
    output reg         resp_ok,
    output reg         resp_valid,
    output reg  [7:0]  resp_data,
    input  wire        resp_ready,
    output reg         resp_done
);
    // 秒计数器（epoch，32 位到 2106 年）
    reg [31:0]  epoch;
    reg [31:0]  tick;
    wire        sec_tick = (tick == CLK_FREQ[31:0] - 1);

    always @(posedge clk) begin
        if (rst) begin
            epoch <= 32'd0; tick <= 0;
        end else if (sec_tick) begin
            tick  <= 0;
            epoch <= epoch + 1;
        end else begin
            tick <= tick + 1;
        end
    end

    // bin2dec 实例（epoch 打印）
    reg         b2d_start;
    reg [31:0]  b2d_val;
    wire        b2d_done;
    wire [79:0] b2d_digits;
    wire [3:0]  b2d_nd;
    fe_bin2dec b2d(.clk(clk), .rst(rst), .start(b2d_start), .value(b2d_val),
                    .done(b2d_done), .digits(b2d_digits), .ndigits(b2d_nd));

    // 段寄存器 / 状态
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;
    reg [3:0]    state;
    reg          pend_ok;
    reg [79:0]   numbuf;   // 右对齐十进制缓冲

    // 十进制解析（sync_manual）：小状态机逐位累积
    reg [31:0] parse_v;
    reg [5:0]  parse_i;
    reg        parse_bad;

    wire is_get   = (act == "get_time");
    wire is_man   = (act == "sync_manual");
    wire is_sys   = (act == "sync_system");
    wire is_ntp   = (act == "sync_ntp");
    wire is_cfg   = (act == "configure_run");

    localparam S_IDLE = 0, S_PARSE = 1, S_B2D = 2, S_SET = 3;

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0; state <= S_IDLE;
            b2d_start <= 0; pend_ok <= 0; parse_v <= 0; parse_i <= 0; parse_bad <= 0;
        end else begin
            resp_start <= 1'b0;
            b2d_start  <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        pend_ok   <= 1'b1;
                        parse_bad <= 1'b0;
                        if (is_get || is_sys) begin
                            b2d_val   <= epoch;
                            b2d_start <= 1'b1;
                            state     <= S_B2D;
                        end else if (is_man) begin
                            if (args[7:0] == 8'h00) begin
                                pend_ok <= 1'b0;
                                s0 <= "missing epoch"; l0 <= 13;
                                ns <= 2'd1;
                                resp_start <= 1'b1; resp_ok <= 1'b0;
                                state <= S_IDLE;
                            end else begin
                                parse_v <= 0; parse_i <= 0; parse_bad <= 0;
                                state   <= S_PARSE;
                            end
                        end else if (is_ntp) begin
                            pend_ok <= 1'b0;
                            s0 <= "ntp sync failed"; l0 <= 15;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end else if (is_cfg) begin
                            s0 <= "configured"; l0 <= 10;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            s0 <= "unsupported command"; l0 <= 19;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end
                    end
                end
                S_PARSE: begin
                    // 最多 10 位数字；遇 0/非数字结束
                    if (parse_i < 10 && args[parse_i*8 +: 8] >= 8'h30 &&
                        args[parse_i*8 +: 8] <= 8'h39) begin
                        // 32 位溢出检测: 4294967295 = 2^32-1,
                        // 累加前 parse_v > 429496729 或 (==429496729 且 digit>5) 必然回绕
                        if (parse_bad) begin
                            parse_i <= parse_i + 1;
                        end else if (parse_v > 32'd429496729 ||
                                   (parse_v == 32'd429496729 && args[parse_i*8 +: 8] > 8'h35)) begin
                            parse_bad <= 1'b1;
                            parse_i   <= parse_i + 1;
                        end else begin
                            parse_v <= parse_v * 10 + args[parse_i*8 +: 8] - 8'h30;
                            parse_i <= parse_i + 1;
                        end
                    end else begin
                        if (parse_bad) begin
                            pend_ok <= 1'b0;
                            s0 <= "invalid epoch"; l0 <= 13;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end else if (parse_v == 0 && parse_i == 0) begin
                            pend_ok <= 1'b0;
                            s0 <= "invalid epoch"; l0 <= 13;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end else if (parse_v == 0) begin
                            pend_ok <= 1'b0;
                            s0 <= "invalid epoch"; l0 <= 13;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            epoch <= parse_v;
                            b2d_val   <= parse_v;
                            b2d_start <= 1'b1;
                            state     <= S_B2D;
                        end
                    end
                end
                S_B2D: begin
                    if (b2d_done) begin
                        state <= S_SET;
                    end
                end
                S_SET: begin
                    // 段填充：get_time/sys → "{\"epoch\":"+num+"}"；
                    // sync_manual → "epoch="+num
                    // bin2dec 输出 digits[7:0]=最高位；段缓冲右对齐需反转
                    for (i = 0; i < 10; i = i + 1) begin
                        if (i < b2d_nd)
                            numbuf[(b2d_nd-1-i)*8 +: 8] = b2d_digits[i*8 +: 8];
                    end
                    if (is_man) begin
                        s0 <= "epoch="; l0 <= 6;
                        s1 <= {944'h0, numbuf}; l1 <= {4'b0, b2d_nd};
                        ns <= 2'd2;
                    end else begin
                        s0 <= "{\"epoch\":"; l0 <= 9;
                        s1 <= {944'h0, numbuf}; l1 <= {4'b0, b2d_nd};
                        s2 <= "}"; l2 <= 1;
                        ns <= 2'd3;
                    end
                    resp_start <= 1'b1;
                    resp_ok    <= pend_ok;
                    state      <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    fe_resp emit(
        .clk(clk), .rst(rst), .start(resp_start), .nsegs(ns),
        .s0dat(s0), .s0len(l0), .s1dat(s1), .s1len(l1), .s2dat(s2), .s2len(l2),
        .resp_valid(resp_valid), .resp_data(resp_data),
        .resp_ready(resp_ready), .resp_done(resp_done)
    );
endmodule
