`timescale 1ns/1ps
// tb_fe_bin2dec.v — 验证 32 位二进制转十进制 ASCII 的行为
module tb_fe_bin2dec;
    reg        clk = 0;
    reg        rst = 1;
    reg        start = 0;
    reg  [31:0] value = 0;
    wire       done;
    wire [79:0] digits;
    wire [3:0]  ndigits;

    fe_bin2dec dut(
        .clk(clk), .rst(rst), .start(start), .value(value),
        .done(done), .digits(digits), .ndigits(ndigits)
    );

    always #5 clk = ~clk;

    integer fails = 0;
    reg [31:0] vals [0:10];
    integer i;

    task run_case(input [31:0] v, input [31:0] expect_dec);
        integer expected_nd;
        reg [79:0] expected_digits;
        integer j;
        begin
            // 期望结果: 十进制字符串 (按字节, digits[7:0]为最高位)
            expected_nd = 0;
            expected_digits = 0;
            begin : mk
                integer t;
                integer nd;
                reg [31:0] x;
                reg [31:0] digs [0:9];
                integer k;
                nd = 0; x = v;
                if (x == 0) begin
                    nd = 1; digs[0] = 0;
                end else begin
                    while (x != 0) begin
                        digs[nd] = x % 10;
                        x = x / 10;
                        nd = nd + 1;
                    end
                end
                for (k = 0; k < nd; k = k + 1)
                    expected_digits[k*8 +: 8] = 8'h30 + digs[nd-1-k];
                expected_nd = nd;
            end

            rst = 1; @(posedge clk); #1;
            rst = 0; @(posedge clk); #1;
            value = v;
            start = 1; @(posedge clk); #1;
            start = 0;
            // 等待 done: 先查当前值 (v=0 时 done 在 start 沿即置位), 再等沿
            begin : waitdone
                integer w;
                for (w = 0; w < 40; w = w + 1) begin
                    if (done) disable waitdone;
                    @(posedge clk); #1;
                end
            end
            // 再等一拍: done 为单周期脉冲, 读 digits/ndigits 需在稳定窗口内
            #1;
            if (!done) begin
                $display("FAIL v=%0d: done 未置位", v);
                fails = fails + 1;
            end else if (ndigits !== expected_nd) begin
                $display("FAIL v=%0d: ndigits=%0d expect=%0d", v, ndigits, expected_nd);
                fails = fails + 1;
            end else begin
                // 按字节比较 (digits[j*8 +: 8] 与期望)
                begin : cmp
                    integer k;
                    integer bad;
                    reg [7:0] gotb, wantb;
                    bad = 0;
                    for (k = 0; k < expected_nd; k = k + 1) begin
                        gotb = digits[k*8 +: 8];
                        wantb = expected_digits[k*8 +: 8];
                        if (gotb !== wantb) bad = 1;
                    end
                    if (bad) begin
                        $display("FAIL v=%0d: bytes mismatch nd=%0d", v, expected_nd);
                        $display("  got : %h", digits);
                        $display("  want: %h", expected_digits);
                        fails = fails + 1;
                    end else begin
                        $display("PASS v=%0d (nd=%0d) digits_hex=%h", v, expected_nd, digits);
                    end
                end
            end
        end
    endtask

    initial begin
        vals[0] = 0;        vals[1] = 1;     vals[2] = 9;
        vals[3] = 10;       vals[4] = 99;    vals[5] = 100;
        vals[6] = 123;      vals[7] = 1234;  vals[8] = 99999;
        vals[9] = 2147483647; vals[10] = 4294967295;

        for (i = 0; i < 11; i = i + 1) begin
            run_case(vals[i], vals[i]);
        end

        if (fails == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d FAILURES ===", fails);
        $finish;
    end
endmodule