`timescale 1ns/1ps
// tb_fe_ability_modbus.v — 验证 RTU 从站读路径边界:
//   1) 0x03 读 ra=0 rc=4        → 正常响应 bc=8
//   2) 0x03 ra=0xFFF0 rc=0x10   → 异常 0x83/0x02 (旧实现 16 位加法回绕绕过检查→越界读)
//   3) 0x03 ra=0 rc=64          → 异常 0x83/0x02 (旧实现 rc[4:0] 截断字节计数=0 且超容)
//   4) 0x03 ra=0 rc=32          → 正常响应 bc=64 (合法上限, 验证不误伤)
//   5) 0x01 ra=0xFFF0 rc=0x10   → 异常 0x81/0x02 (coils 读回绕)
module tb_fe_ability_modbus;
    parameter integer CLK_FREQ = 100000000;
    parameter integer BAUD     = 115200;
    localparam integer BIT_T = 8680; // 约 1 位时长(ns)

    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg [255:0] act = 0;
    reg [511:0] args = 0;
    wire resp_start, resp_ok, resp_valid, resp_done;
    wire [7:0] resp_data;
    reg resp_ready = 1;
    reg mb_rx = 1;
    wire mb_tx;

    fe_ability_modbus dut(
        .clk(clk), .rst(rst), .start(start), .act(act), .args(args),
        .resp_start(resp_start), .resp_ok(resp_ok),
        .resp_valid(resp_valid), .resp_data(resp_data),
        .resp_ready(resp_ready), .resp_done(resp_done),
        .mb_rx(mb_rx), .mb_tx(mb_tx)
    );

    always #5 clk = ~clk;

    integer fails = 0;

    // ---------- CRC16 (Modbus) ----------
    function [15:0] crc16(input [127:0] data, input integer len);
        integer i, b;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            for (i = 0; i < len; i = i + 1) begin
                crc = crc ^ data[i*8 +: 8];
                for (b = 0; b < 8; b = b + 1)
                    crc = (crc[0]) ? ((crc >> 1) ^ 16'hA001) : (crc >> 1);
            end
            crc16 = crc;
        end
    endfunction

    // ---------- UART 发送一字节 (LSB 先行) ----------
    task uart_send(input [7:0] b);
        integer k;
        begin
            mb_rx = 1'b0; #BIT_T;
            for (k = 0; k < 8; k = k + 1) begin
                mb_rx = b[k]; #BIT_T;
            end
            mb_rx = 1'b1; #BIT_T;
        end
    endtask

    // ---------- UART 接收一字节 (中点采样) ----------
    task uart_recv(output [7:0] b, output reg ok);
        integer k;
        begin
            ok = 1'b0;
            fork
                begin
                    @(negedge mb_tx);
                    #(BIT_T/2);
                    for (k = 0; k < 8; k = k + 1) begin
                        #BIT_T;
                        b[k] = mb_tx;
                    end
                    #BIT_T;   // 停止位
                    ok = 1'b1;
                end
                begin
                    #(BIT_T * 200);   // 超时
                end
            join_any
            disable fork;
        end
    endtask

    // ---------- 发送完整 RTU 帧 ----------
    task send_frame(input [127:0] payload, input integer len);
        integer i;
        reg [15:0] crc;
        begin
            crc = crc16(payload, len);
            for (i = 0; i < len; i = i + 1)
                uart_send(payload[i*8 +: 8]);
            uart_send(crc[7:0]);
            uart_send(crc[15:8]);
            // 注意: 不能在此等待帧间隔 — 从站 3.5 字符静默后即发起响应,
            // 若静默太长响应起始沿会在 recv_frame 就绪前发生, 首字节被吞。
            // 由 recv_frame 先就绪再等沿。
        end
    endtask

    // ---------- 接收完整 RTU 响应帧 ----------
    reg [7:0]  rbuf [0:255];
    integer    rlen;
    task recv_frame;
        reg [7:0] b; reg ok;
        integer guard;
        begin
            rlen = 0;
            guard = 0;
            // 先等第一个字节 (有超时)
            uart_recv(b, ok);
            if (!ok) begin
                rlen = -1;
            end else begin
                rbuf[0] = b; rlen = 1;
                // 随后按 3.5 字符间隔判结束
                while (rlen < 128 && guard == 0) begin
                    fork
                        begin
                            uart_recv(b, ok);
                            if (ok) begin
                                rbuf[rlen] = b; rlen = rlen + 1;
                                guard = 0;
                            end else begin
                                guard = 1;
                            end
                        end
                    join_any
                    disable fork;
                end
            end
        end
    endtask

    // ---------- 用例 ----------
    integer i;

    task run_case(input [127:0] payload, input integer len,
                  input integer expect_first, input integer expect_second);
        reg [7:0] b; reg ok;
        begin
            send_frame(payload, len);
            recv_frame;
            if (rlen < 1) begin
                $display("FAIL: no response"); fails = fails + 1;
            end else if (rlen == 1) begin
                // 单字节 = 异常帧? 不, 异常至少 5B。视为异常处理: 检查首字节
                if (rbuf[0] !== expect_first) begin
                    $display("FAIL: first=0x%02x expect=0x%02x", rbuf[0], expect_first);
                    fails = fails + 1;
                end else begin
                    $display("PASS: exception 0x%02x", rbuf[0]);
                end
            end else begin
                $display("DUMP len=%0d: %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                         rlen, rbuf[0], rbuf[1], rbuf[2], rbuf[3], rbuf[4], rbuf[5],
                         rbuf[6], rbuf[7], rbuf[8], rbuf[9]);
                if (rlen >= 3 && rbuf[1] == expect_first && rbuf[2] == expect_second) begin
                    $display("PASS: resp[0..2]=%02x %02x %02x len=%0d", rbuf[0], rbuf[1], rbuf[2], rlen);
                end else begin
                    $display("FAIL: resp[0..2]=%02x %02x %02x len=%0d expect=%02x %02x",
                             rbuf[0], rbuf[1], rbuf[2], rlen, expect_first, expect_second);
                    fails = fails + 1;
                end
            end
        end
    endtask

    // 构造 "id fc aH aL cH cL" 前 6 字节
    function [127:0] mk6(input [7:0] id, input [7:0] fc,
                         input [15:0] addr, input [15:0] cnt);
        begin
            mk6[7:0]    = id;
            mk6[15:8]   = fc;
            mk6[23:16]  = addr[15:8];
            mk6[31:24]  = addr[7:0];
            mk6[39:32]  = cnt[15:8];
            mk6[47:40]  = cnt[7:0];
        end
    endfunction

    initial begin
        #10;
        // 预热寄存器堆: holding[0]=0x1234
        act = "write_holding";
        args = 0;
        args[7:0] = 8'h30;              // '0'
        args[15:8] = 8'h2C;             // ','
        args[23:16] = 8'h31;            // '1'
        args[31:24] = 8'h32;            // '2'
        args[39:32] = 8'h33;            // '3'
        args[47:40] = 8'h34;            // '4'
        rst = 1; @(posedge clk); #1;
        rst = 0; @(posedge clk); #1;
        start = 1; @(posedge clk); #1;
        start = 0;
        #2000;

        // 用例 1: 合法读 ra=0 rc=4
        run_case(mk6(8'h01, 8'h03, 16'h0000, 16'h0004), 6, 8'h03, 8'h08);

        // 用例 2: ra=0xFFF0 rc=0x10 (旧: 16 位加法回绕 0 绕过检查 → 越界读)
        run_case(mk6(8'h01, 8'h03, 16'hFFF0, 16'h0010), 6, 8'h83, 8'h02);

        // 用例 3: ra=0 rc=64 (旧: rc[4:0] 截断字节计数=0, 且数据超 128B 容量)
        run_case(mk6(8'h01, 8'h03, 16'h0000, 16'h0040), 6, 8'h83, 8'h02);

        // 用例 4: ra=0 rc=32 合法上限 → bc=64
        run_case(mk6(8'h01, 8'h03, 16'h0000, 16'h0020), 6, 8'h03, 8'h40);

        // 用例 5: coils 读 ra=0xFFF0 rc=0x10 (旧: 回绕)
        run_case(mk6(8'h01, 8'h01, 16'hFFF0, 16'h0010), 6, 8'h81, 8'h02);

        #1000;
        if (fails == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d", fails);
        $finish;
    end
endmodule