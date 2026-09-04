`timescale 1ns/1ps
// tb_fe_ability_time.v — 验证 TimeAbility 硬件 sync_manual 边界行为:
//   1) 合法 10 位上限 4294967295 应被接受
//   2) 超 32 位范围 "9999999999" 应报 invalid epoch, 不得回绕改坏时钟
module tb_fe_ability_time;
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

    fe_ability_time dut(
        .clk(clk), .rst(rst), .start(start), .act(act), .args(args),
        .resp_start(resp_start), .resp_ok(resp_ok),
        .resp_valid(resp_valid), .resp_data(resp_data),
        .resp_ready(resp_ready), .resp_done(resp_done)
    );

    always #5 clk = ~clk;

    integer fails = 0;
    integer k;

    task run_case(input [79:0] digits, input integer expect_ok, input [31:0] expect_epoch);
        begin
            rst = 1; @(posedge clk); #1;
            rst = 0; @(posedge clk); #1;
            act = "sync_manual";
            args = 0;
            // 字符串字面量最高字节=首字符; RTL 期望 args[7:0] 是首字符
            for (k = 0; k < 10; k = k + 1)
                args[k*8 +: 8] = digits[(9-k)*8 +: 8];
            start = 1; @(posedge clk); #1;
            start = 0;
            // 等待 resp_done (valid/ready 握手, ready 常 1)
            begin : waitdone
                integer w;
                reg done_seen;
                done_seen = 0;
                for (w = 0; w < 100; w = w + 1) begin
                    @(posedge clk);
                    if (resp_done) begin
                        done_seen = 1;
                        w = 100;
                    end
                end
            end
            if (resp_ok != expect_ok) begin
                $display("FAIL %0s: resp_ok=%0b expect=%0b", digits, resp_ok, expect_ok);
                fails = fails + 1;
            end else if (expect_ok && dut.epoch !== expect_epoch) begin
                $display("FAIL %0s: epoch=%0d expect=%0d", digits, dut.epoch, expect_epoch);
                fails = fails + 1;
            end else begin
                $display("PASS %0s (ok=%0b)", digits, resp_ok);
            end
        end
    endtask

    initial begin
        #10;
        // 合法: 1700000000
        run_case("1700000000", 1, 32'd1700000000);
        // 合法上限: 4294967295 (2^32-1)
        run_case("4294967295", 1, 32'd4294967295);
        // 超范围: 9999999999 — 不得回绕
        run_case("9999999999", 0, 32'd0);
        // 全零: 应报 invalid epoch (与软件版一致)
        run_case("0000000000", 0, 32'd0);
        #20;
        if (fails == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d", fails);
        $finish;
    end
endmodule