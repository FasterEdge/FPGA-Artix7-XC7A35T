// ─────────────────────────────────────────────────────────────
// FasterEdge 开源项目
// Github: https://github.com/FasterEdge
// Gitee:  https://gitee.com/FasterEdge
// ─────────────────────────────────────────────────────────────
// tb_fe_hmac.v — HMAC-SHA256 核自校验
// 向量：key = "Jefe"+28×0x00（32B），msg = "The quick brown fox jumps over
// the lazy dog"（43B）→ 90bfc305...；key = "key"+29×0x00，msg = "Hi There"。
// 运行：iverilog -g2012 -o tb.vvp sim/tb_fe_hmac.v rtl/fe_hmac_sha256.v rtl/fe_sha256_block.v && vvp tb.vvp
`timescale 1ns/1ps

module tb_fe_hmac;
    reg clk = 0, rst = 1;
    reg start = 0;
    reg [255:0] secret;
    reg [5:0] msg_len;
    reg [439:0] msg;
    wire done;
    wire [255:0] mac;

    always #5 clk = ~clk;

    fe_hmac_sha256 dut (.clk(clk), .rst(rst), .start(start), .secret(secret),
                        .msg_len(msg_len), .msg(msg), .done(done), .mac(mac));

    // 字符串 → LSB-first（byte0 在 [7:0]，0 填充到宽度 W*8 位）
    function [255:0] str32_to_lsb(input [8*32-1:0] s, input integer len);
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                str32_to_lsb[i*8 +: 8] = (i < len) ? s[(len-1-i)*8 +: 8] : 8'h00;
        end
    endfunction
    function [439:0] str_to_lsb(input [8*55-1:0] s, input integer len);
        integer i;
        begin
            for (i = 0; i < 55; i = i + 1)
                str_to_lsb[i*8 +: 8] = (i < len) ? s[(len-1-i)*8 +: 8] : 8'h00;
        end
    endfunction

    task run_case(input [255:0] key, input [439:0] m, input integer mlen,
                  input [31:0] want4);
        begin
            @(negedge clk);
            secret = key; msg = m; msg_len = mlen[5:0];
            start = 1;
            @(negedge clk);
            start = 0;
            wait (done);
            @(negedge clk);
            // want4 = 摘要前 4 字节（大端书写），mac LSB-first 后应等于字节反转
            if (mac[31:0] !== want4) begin
                $display("FAIL: mac[31:0]=%h (want %h)", mac[31:0], want4);
                $display("      full mac=%h", mac);
                $stop;
            end else
                $display("PASS: first4=%02x%02x%02x%02x", mac[7:0], mac[15:8], mac[23:16], mac[31:24]);
        end
    endtask

    reg [439:0] m1, m2;
    reg [255:0] k1, k2;
    initial begin
        repeat (4) @(negedge clk);
        rst = 0;

        k1 = str32_to_lsb("Jefe", 4);   // 32B 密钥："Jefe" + 0x00×28，byte0='J'
        m1 = str_to_lsb("The quick brown fox jumps over the lazy dog", 43);
        run_case(k1, m1, 43, {8'h05, 8'hc3, 8'hbf, 8'h90});

        k2 = str32_to_lsb("key", 3);
        m2 = str_to_lsb("Hi There", 8);
        run_case(k2, m2, 8, {8'hac, 8'h65, 8'h58, 8'he7});

        $display("HMAC ALL TESTS PASSED");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
