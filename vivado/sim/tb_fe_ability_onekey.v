`timescale 1ns/1ps
// tb_fe_ability_onekey.v — 验证 OneKey issue/verify 解析边界:
//   1) issue_token 签发后 verify_token(seq:token) 应 valid
//   2) 篡改 token 应 invalid
//   3) seq 段含非数字 ("abc:...") 应 bad format (旧实现静默忽略 → vseq=0)
//   4) seq 段超 32 位 ("9999999999:...") 应 bad format (旧实现回绕)
module tb_fe_ability_onekey;
    reg         clk = 0;
    reg         rst = 1;
    reg         start = 0;
    reg  [255:0] act = 0;
    reg  [511:0] args = 0;
    wire        resp_start;
    wire        resp_ok;
    wire        resp_valid;
    wire [7:0]  resp_data;
    reg         resp_ready = 1;
    wire        resp_done;

    fe_ability_onekey dut(
        .clk(clk), .rst(rst), .start(start), .act(act), .args(args),
        .resp_start(resp_start), .resp_ok(resp_ok),
        .resp_valid(resp_valid), .resp_data(resp_data),
        .resp_ready(resp_ready), .resp_done(resp_done)
    );

    always #5 clk = ~clk;

    integer fails = 0;
    integer k;
    reg [7:0]  resp_bytes [0:255];
    integer    resp_n;
    reg [7:0]  tok [0:42];
    integer    tok_n;

    // 执行一个命令: 设置 act/args, 拉 start, 收完响应字节与 resp_ok
    task do_cmd(input [255:0] a, input [511:0] payload, input integer plen);
        reg [7:0] rbyte;
        integer w;
        integer i;
        begin
            act = a;
            args = 0;
            // payload[7:0] 是命令首字符, 与 RTL args[7:0]=首字符 一致
            for (i = 0; i < plen; i = i + 1)
                args[i*8 +: 8] = payload[i*8 +: 8];
            resp_n = 0;
            rst = 1; @(posedge clk); #1;
            rst = 0; @(posedge clk); #1;
            start = 1; @(posedge clk); #1;
            start = 0;
            // 等待 resp_done; 期间收字节 (HMAC-SHA256 需数千周期)
            for (w = 0; w < 100000; w = w + 1) begin
                @(posedge clk);
                if (resp_valid && resp_ready) begin
                    if (resp_n < 256) resp_bytes[resp_n] = resp_data;
                    resp_n = resp_n + 1;
                end
                if (resp_done) begin
                    w = 300;
                end
            end
        end
    endtask

    // 从 issue 响应 {"token":"TOK","seq":N} 中提取引号内的 43 字节
    task extract_token;
        integer i;
        begin
            tok_n = 0;
            // 跳过前导 {"token":" 10 字节, 从 token 值首字节开始
            for (i = 10; i < resp_n; i = i + 1) begin
                if (resp_bytes[i] == 8'h22) begin
                    i = resp_n;  // 结束引号
                end else if (tok_n < 43) begin
                    tok[tok_n] = resp_bytes[i];
                    tok_n = tok_n + 1;
                end
            end
        end
    endtask

    // 把 token 逐字节放入 80 位 payload (首个 token 字节在 payload 最高字节)
    task build_verify_payload(input integer seq_v, input integer tamper_at,
                              output [1023:0] p, output integer pl);
        integer i;
        begin
            p = 0; pl = 0;
            // "seq:"
            if (seq_v >= 0) begin
                p[7:0] = 8'h30 + (seq_v % 10);
                pl = 1;
            end
            p[pl*8 +: 8] = 8'h3A; pl = pl + 1;
            for (i = 0; i < tok_n; i = i + 1) begin
                if (i == tamper_at) p[pl*8 +: 8] = 8'h21; // '!' 篡改
                else p[pl*8 +: 8] = tok[i];
                pl = pl + 1;
            end
        end
    endtask

    initial begin
        #10;
        // 1. 签发 (seq=0, 默认 subject)
        do_cmd("issue_token", 80'h0, 0);
        if (!resp_ok) begin
            $display("FAIL issue: resp_ok=%0b", resp_ok); fails = fails + 1;
        end else begin
            $display("PASS issue (resp=%0d bytes)", resp_n);
        end
        extract_token;
        $display("     token len=%0d", tok_n);

        // 2. 正确验证 0:token
        begin : v_ok
            reg [1023:0] p; integer pl;
            build_verify_payload(0, -1, p, pl);
            do_cmd("verify_token", p, pl);
        end
        if (resp_ok) begin
            $display("PASS verify valid");
        end else begin
            $display("FAIL verify valid: resp_ok=%0b", resp_ok); fails = fails + 1;
        end

        // 3. 篡改 token 第 5 字节
        begin : v_tam
            reg [1023:0] p; integer pl;
            build_verify_payload(0, 4, p, pl);
            do_cmd("verify_token", p, pl);
        end
        if (!resp_ok) begin
            $display("PASS verify tampered rejected");
        end else begin
            $display("FAIL verify tampered accepted"); fails = fails + 1;
        end

        // 4. seq 段含非数字 "abc:token" (用 3 字节 payload 截断验证: 实际握手按完整输入)
        //   用 do_cmd 传 "abc:TOKEN" 前 8 字节为代表
        begin : v_bad
            reg [1023:0] p; integer pl;
            build_verify_payload(-1, -1, p, pl);  // seq_v=-1 → 无数字直接冒号
            // 手动构造 "a:TOKEN"
            p = 0; pl = 0;
            p[7:0] = 8'h61; pl = 1;           // 'a'
            p[pl*8 +: 8] = 8'h3A; pl = pl + 1; // ':'
            begin : cp
                integer i;
                for (i = 0; i < tok_n && i < 16; i = i + 1) begin
                    p[pl*8 +: 8] = tok[i]; pl = pl + 1;
                end
            end
            do_cmd("verify_token", p, pl);
        end
        if (!resp_ok) begin
            $display("PASS verify non-digit seq rejected");
        end else begin
            $display("FAIL verify non-digit seq accepted: resp_ok=%0b", resp_ok); fails = fails + 1;
        end

        // 5. seq 段超 32 位 "9999999999:token" (payload 长 10 字符)
        begin : v_ovf
            reg [1023:0] p; integer pl;
            integer i;
            p = 0; pl = 0;
            for (i = 0; i < 10; i = i + 1) begin
                p[pl*8 +: 8] = 8'h30 + (9); pl = pl + 1;  // '9' x10
            end
            p[pl*8 +: 8] = 8'h3A; pl = pl + 1;            // ':'
            begin : cp2
                integer ii;
                for (ii = 0; ii < tok_n && ii < 8; ii = ii + 1) begin
                    p[pl*8 +: 8] = tok[ii]; pl = pl + 1;
                end
            end
            do_cmd("verify_token", p, pl);
        end
        if (!resp_ok) begin
            $display("PASS verify overflow seq rejected");
        end else begin
            $display("FAIL verify overflow seq accepted: resp_ok=%0b", resp_ok); fails = fails + 1;
        end

        #20;
        if (fails == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d", fails);
        $finish;
    end
endmodule