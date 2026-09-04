// ─────────────────────────────────────────────────────────────
// FasterEdge 开源项目
// Github: https://github.com/FasterEdge
// Gitee:  https://gitee.com/FasterEdge
// ─────────────────────────────────────────────────────────────
`timescale 1ns/1ps
// fe_ability_onekey.v — OneKeyAbility（纯 RTL）
// issue_token / verify_token / revoke_token / revoke_all / list_tokens /
// status / rotate。令牌 = base64url(HMAC-SHA256(secret, "seq:subject"))，
// 与 MCU 版 ability_onekey.c 同构。密钥为编译期参数（32B，LSB 在前），
// 吊销/旋转语义与 MCU 版一致（重置序列号）。
module fe_ability_onekey #(
    parameter [255:0] SECRET = 256'h0   // 由 fe_top 传入反转后的密钥字节
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
    // 字节序反转（密钥参数以字符串书写时首字符在最高字节）
    function [255:0] rev256(input [255:0] v);
        integer k;
        begin
            for (k = 0; k < 32; k = k + 1)
                rev256[k*8 +: 8] = v[255-k*8 -: 8];
        end
    endfunction

    // 未指定 SECRET 时使用内置默认密钥（与 tb/README 中的向量一致）
    localparam [255:0] SECRET_Q = (SECRET == 256'h0) ?
        rev256("FasterEdge-Artix7-Secret-Key-32B") : SECRET;

`include "fe_registry.vh"   // cbyte()

    // 序号
    reg [31:0] seq;

    // ---------------- bin2dec ----------------
    reg         b2d_start;
    reg [31:0]  b2d_val;
    wire        b2d_done;
    wire [79:0] b2d_digits;      // digits[7:0] = 最高位数字
    wire [3:0]  b2d_nd;
    fe_bin2dec b2d(.clk(clk), .rst(rst), .start(b2d_start), .value(b2d_val),
                   .done(b2d_done), .digits(b2d_digits), .ndigits(b2d_nd));

    // ---------------- HMAC ----------------
    reg         hmac_start;
    reg [5:0]   hmac_len;
    reg [439:0] hmac_msg;        // LSB-first
    wire        hmac_done;
    wire [255:0] hmac_mac;       // LSB-first
    fe_hmac_sha256 hmac(.clk(clk), .rst(rst), .start(hmac_start),
                        .secret(SECRET_Q), .msg_len(hmac_len), .msg(hmac_msg),
                        .done(hmac_done), .mac(hmac_mac));

    // ---------------- base64url ----------------
    function [7:0] b64c(input [5:0] v);
        case (v)
            6'd0:  b64c="A"; 6'd1:  b64c="B"; 6'd2:  b64c="C"; 6'd3:  b64c="D";
            6'd4:  b64c="E"; 6'd5:  b64c="F"; 6'd6:  b64c="G"; 6'd7:  b64c="H";
            6'd8:  b64c="I"; 6'd9:  b64c="J"; 6'd10: b64c="K"; 6'd11: b64c="L";
            6'd12: b64c="M"; 6'd13: b64c="N"; 6'd14: b64c="O"; 6'd15: b64c="P";
            6'd16: b64c="Q"; 6'd17: b64c="R"; 6'd18: b64c="S"; 6'd19: b64c="T";
            6'd20: b64c="U"; 6'd21: b64c="V"; 6'd22: b64c="W"; 6'd23: b64c="X";
            6'd24: b64c="Y"; 6'd25: b64c="Z"; 6'd26: b64c="a"; 6'd27: b64c="b";
            6'd28: b64c="c"; 6'd29: b64c="d"; 6'd30: b64c="e"; 6'd31: b64c="f";
            6'd32: b64c="g"; 6'd33: b64c="h"; 6'd34: b64c="i"; 6'd35: b64c="j";
            6'd36: b64c="k"; 6'd37: b64c="l"; 6'd38: b64c="m"; 6'd39: b64c="n";
            6'd40: b64c="o"; 6'd41: b64c="p"; 6'd42: b64c="q"; 6'd43: b64c="r";
            6'd44: b64c="s"; 6'd45: b64c="t"; 6'd46: b64c="u"; 6'd47: b64c="v";
            6'd48: b64c="w"; 6'd49: b64c="x"; 6'd50: b64c="y"; 6'd51: b64c="z";
            6'd52: b64c="0"; 6'd53: b64c="1"; 6'd54: b64c="2"; 6'd55: b64c="3";
            6'd56: b64c="4"; 6'd57: b64c="5"; 6'd58: b64c="6"; 6'd59: b64c="7";
            6'd60: b64c="8"; 6'd61: b64c="9"; 6'd62: b64c="-"; default: b64c="_";
        endcase
    endfunction

    reg [7:0]  tok_l [0:42];     // 43 字符（LSB-first）
    reg [7:0]  b64_cnt;
    wire [3:0] grp  = b64_cnt[5:2];          // 组号 0..10
    wire [1:0] cidx = b64_cnt[1:0];
    wire [7:0] mb0  = hmac_mac[grp*24 +: 8];
    wire [7:0] mb1  = hmac_mac[grp*24+8 +: 8];
    wire [7:0] mb2  = (grp == 4'd10) ? 8'h00 : hmac_mac[grp*24+16 +: 8];  // 末组补零
    wire [23:0] trip = {mb0, mb1, mb2};      // trip[23:16] = 第 3g 字节

    reg [7:0] b64_char;
    always @* begin
        if (grp < 4'd10)
            case (cidx)
                2'd0: b64_char = b64c(trip[23:18]);
                2'd1: b64_char = b64c(trip[17:12]);
                2'd2: b64_char = b64c(trip[11:6]);
                default: b64_char = b64c(trip[5:0]);
            endcase
        else
            case (cidx)
                2'd0: b64_char = b64c(trip[23:18]);
                2'd1: b64_char = b64c(trip[17:12]);
                default: b64_char = b64c(trip[11:6]);   // 末组 2 字节 → 3 字符
            endcase
    end

    // ---------------- 工作区 ----------------
    reg [127:0]  subj;           // subject（LSB-first ≤16B）
    reg [4:0]    subj_len;
    reg [79:0]   numbuf;         // 右对齐十进制（供段）
    reg [439:0]  work;           // HMAC 载荷（LSB-first，组合生成）
    reg [6:0]    worklen;
    reg [1023:0] resp_l;         // 响应构建（LSB-first）
    reg [7:0]    resp_len;
    reg [5:0]    parse_i;
    reg [1:0]    parse_ph;       // 0=seq 1=token 2=subject
    reg [31:0]   vseq;
    reg          vseq_bad;       // verify seq 解析非法/溢出标记
    reg [7:0]    vt [0:42];
    reg [6:0]    vlen;
    reg          vcolon2;
    reg          cmp_ok;
    reg          st_status, st_issue, st_verify;

    // 载荷 = dec(seq) + ':' + subject（组合）
    integer k;
    always @* begin
        work = 0; worklen = 0;
        for (k = 0; k < 28; k = k + 1) begin
            if (k < {4'b0, b2d_nd}) begin
                work[k*8 +: 8] = b2d_digits[k*8 +: 8];
                worklen = k[6:0] + 7'd1;
            end else if (k == {4'b0, b2d_nd}) begin
                work[k*8 +: 8] = 8'h3A;
                worklen = k[6:0] + 7'd1;
            end else if (k < {4'b0, b2d_nd} + 7'd1 + {2'b0, subj_len}) begin
                work[k*8 +: 8] = subj[(k - {4'b0, b2d_nd} - 7'd1)*8 +: 8];
                worklen = k[6:0] + 7'd1;
            end
        end
    end

    // issue 响应缓冲（LSB-first）：{"token":"TOK","seq":N}
    reg [1023:0] issue_buf;
    reg [7:0]    issue_len;
    integer q;
    always @* begin
        issue_buf = 0; issue_len = 0;
        for (q = 0; q < 128; q = q + 1) begin
            if (q < 10)
                issue_buf[q*8 +: 8] = cbyte("{\"token\":\"", 10, q);
            else if (q < 53)
                issue_buf[q*8 +: 8] = tok_l[q-10];
            else if (q < 61)
                issue_buf[q*8 +: 8] = cbyte("\",\"seq\":", 8, q-53);
            else if (q < 61 + {4'b0, b2d_nd})
                issue_buf[q*8 +: 8] = b2d_digits[(q-61)*8 +: 8];
            else if (q == 61 + {4'b0, b2d_nd}) begin
                issue_buf[q*8 +: 8] = 8'h7D;
                issue_len = q[7:0] + 8'd1;
            end
        end
    end

    // ---------------- 段寄存器 ----------------
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;

    wire is_status  = (act == "status");
    wire is_issue   = (act == "issue_token");
    wire is_verify  = (act == "verify_token");
    wire is_revoke  = (act == "revoke_token") | (act == "revoke_all");
    wire is_list    = (act == "list_tokens");
    wire is_rotate  = (act == "rotate");

    localparam S_IDLE = 0, S_PARSE = 1, S_MSG = 2, S_B2D = 3, S_HMAC = 4,
               S_B64 = 5, S_FINAL = 6;
    reg [2:0] state;

    integer j;
    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0;
            seq <= 0; b2d_start <= 0; hmac_start <= 0; hmac_len <= 0; hmac_msg <= 0;
            b64_cnt <= 0; subj <= 0; subj_len <= 0; numbuf <= 0;
            resp_l <= 0; resp_len <= 0; parse_i <= 0; parse_ph <= 0;
            vseq <= 0; vseq_bad <= 0; vlen <= 0; vcolon2 <= 0; cmp_ok <= 0;
            st_status <= 0; st_issue <= 0; st_verify <= 0;
            state <= S_IDLE;
            for (j = 0; j < 43; j = j + 1) begin
                tok_l[j] <= 0; vt[j] <= 0;
            end
        end else begin
            resp_start <= 1'b0;
            b2d_start  <= 1'b0;
            hmac_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        st_status <= 1'b0; st_issue <= 1'b0; st_verify <= 1'b0;
                        if (is_status) begin
                            st_status <= 1'b1;
                            b2d_val   <= seq + 1;
                            b2d_start <= 1'b1;
                            state     <= S_B2D;
                        end else if (is_issue) begin
                            st_issue <= 1'b1;
                            subj <= 0; subj_len <= 0;
                            if (args[7:0] == 8'h00) begin
                                subj <= "tluafed"; subj_len <= 7;  // "default" LSB-first（右对齐字面量反转）
                            end else begin
                                for (j = 0; j < 16; j = j + 1)
                                    if (args[j*8 +: 8] != 8'h00) begin
                                        subj[j*8 +: 8] <= args[j*8 +: 8];
                                        subj_len <= j[4:0] + 5'd1;
                                    end
                            end
                            b2d_val   <= seq;
                            b2d_start <= 1'b1;
                            state     <= S_B2D;
                        end else if (is_verify) begin
                            st_verify <= 1'b1;
                            vseq <= 0; vlen <= 0; vcolon2 <= 0;
                            subj <= 0; subj_len <= 0;
                            parse_i <= 0; parse_ph <= 2'd0;
                            state   <= S_PARSE;
                        end else if (is_revoke) begin
                            seq <= 0;
                            s0 <= "{\"revoked\":true}"; l0 <= 17; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b1;
                        end else if (is_list) begin
                            s0 <= "{\"tokens\":[]}"; l0 <= 14; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b1;
                        end else if (is_rotate) begin
                            seq <= 0;
                            s0 <= "{\"rotated\":true}"; l0 <= 17; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b1;
                        end else begin
                            s0 <= "unsupported command"; l0 <= 19; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                        end
                    end
                end
                S_PARSE: begin
                    // "seq:token[:subject]" 逐字符（1 字节/周期）
                    if (parse_i >= 64 || args[parse_i*8 +: 8] == 8'h00) begin
                        if (parse_ph == 2'd0) begin
                            s0 <= "bad format, expect seq:token"; l0 <= 26;
                            ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            state <= S_MSG;
                        end
                    end else if (parse_ph == 2'd0) begin
                        if (args[parse_i*8 +: 8] == 8'h3A) begin
                            parse_ph <= 2'd1;
                        end else if (args[parse_i*8 +: 8] >= 8'h30 &&
                                     args[parse_i*8 +: 8] <= 8'h39) begin
                            // 32 位溢出检测: 4294967295 = 2^32-1,
                            // 累加前 vseq > 429496729 或 (==429496729 且 digit>5) 必然回绕
                            if (vseq > 32'd429496729 ||
                                (vseq == 32'd429496729 && args[parse_i*8 +: 8] > 8'h35)) begin
                                vseq_bad <= 1'b1;
                            end else begin
                                vseq <= vseq * 10 + args[parse_i*8 +: 8] - 8'h30;
                            end
                        end else begin
                            // seq 段出现非数字且非冒号 → 格式非法
                            vseq_bad <= 1'b1;
                        end
                        parse_i <= parse_i + 1;
                    end else if (parse_ph == 2'd1) begin
                        if (args[parse_i*8 +: 8] == 8'h3A) begin
                            vcolon2 <= 1'b1; parse_ph <= 2'd2;
                        end else if (vlen < 43) begin
                            vt[vlen[5:0]] <= args[parse_i*8 +: 8];
                            vlen <= vlen + 1;
                        end
                        parse_i <= parse_i + 1;
                    end else begin
                        if (subj_len < 16) begin
                            subj[subj_len*8 +: 8] <= args[parse_i*8 +: 8];
                            subj_len <= subj_len + 5'd1;
                        end
                        parse_i <= parse_i + 1;
                    end
                end
                S_MSG: begin
                    // seq 段格式非法/溢出 → 直接拒绝, 不进入 HMAC
                    if (st_verify && vseq_bad) begin
                        s0 <= "bad format, expect seq:token"; l0 <= 26;
                        ns <= 2'd1;
                        resp_start <= 1'b1; resp_ok <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        // verify 无第二冒号 → subject 默认 "default"（同 MCU 版）
                        if (st_verify && !vcolon2 && subj_len == 0) begin
                            subj <= "tluafed"; subj_len <= 7;  // "default" LSB-first（右对齐字面量反转）
                        end
                        b2d_val   <= st_verify ? vseq : seq;
                        b2d_start <= 1'b1;
                        state     <= S_B2D;
                    end
                end
                S_B2D: begin
                    if (b2d_done) begin
                        hmac_msg  <= work;
                        hmac_len  <= worklen[5:0];
                        hmac_start<= 1'b1;
                        state     <= S_HMAC;
                    end
                end
                S_HMAC: begin
                    if (hmac_done) begin
                        if (st_issue) seq <= seq + 1;   // 计算完成后再递增
                        b64_cnt <= 0;
                        state   <= S_B64;
                    end
                end
                S_B64: begin
                    tok_l[b64_cnt[5:0]] <= b64_char;
                    if (b64_cnt == 42) state <= S_FINAL;
                    else b64_cnt <= b64_cnt + 1;
                end
                S_FINAL: begin
                    if (st_status) begin
                        // {"tokens":N}
                        for (j = 0; j < 10; j = j + 1)
                            if (j < b2d_nd)
                                numbuf[(b2d_nd-1-j)*8 +: 8] = b2d_digits[j*8 +: 8];
                        s0 <= "{\"tokens\":"; l0 <= 10;
                        s1 <= {944'h0, numbuf}; l1 <= {4'b0, b2d_nd};
                        s2 <= "}"; l2 <= 1;
                        ns <= 2'd3;
                        resp_start <= 1'b1; resp_ok <= 1'b1;
                    end else if (st_issue) begin
                        // 反转 LSB-first 缓冲 → 右对齐段
                        for (j = 0; j < 128; j = j + 1)
                            if (j < issue_len)
                                s0[(issue_len-1-j)*8 +: 8] = issue_buf[j*8 +: 8];
                        l0 <= issue_len;
                        ns <= 2'd1;
                        resp_start <= 1'b1; resp_ok <= 1'b1;
                    end else begin
                        // verify：比较 43 字节
                        cmp_ok = 1'b1;
                        for (j = 0; j < 43; j = j + 1)
                            if (tok_l[j] != vt[j]) cmp_ok = 1'b0;
                        if (cmp_ok) begin
                            s0 <= "{\"valid\":true}"; l0 <= 14; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b1;
                        end else begin
                            s0 <= "token invalid"; l0 <= 13; ns <= 2'd1;
                            resp_start <= 1'b1; resp_ok <= 1'b0;
                        end
                    end
                    state <= S_IDLE;
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
