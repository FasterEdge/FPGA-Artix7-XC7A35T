// tb_fe_top.sv — FasterEdge FPGA 全链路仿真
// 通过 UART0 电平发送 CLI 命令并校验响应；UART1 校验 Modbus RTU 从站。
// 运行：iverilog -g2012 -I rtl -o tb.vvp sim/tb_fe_top.sv rtl/fe_top.v rtl/*.v && vvp tb.vvp
// 预期输出：ALL TESTS PASSED
`timescale 1ns/1ps

module tb_fe_top;
    reg clk = 0;
    reg btn_rst = 1;
    reg uart0_rx = 1;
    wire uart0_tx;
    reg uart1_rx = 1;
    wire uart1_tx;
    wire [3:0] led;

    always #5 clk = ~clk;

    fe_top dut(
        .clk100(clk), .btn_rst(btn_rst),
        .uart0_rx(uart0_rx), .uart0_tx(uart0_tx),
        .uart1_rx(uart1_rx), .uart1_tx(uart1_tx),
        .led(led)
    );

    // ---------------- UART 发送 ----------------
    task send_byte(input [7:0] b);
        integer k;
        begin
            uart0_rx = 1'b0; #8680;
            for (k = 0; k < 8; k = k + 1) begin
                uart0_rx = b[k]; #8680;
            end
            uart0_rx = 1'b1; #8680;
        end
    endtask

    task send_cmd(input [8*64-1:0] s, input integer len);
        integer i;
        begin
            for (i = 0; i < len; i = i + 1)
                send_byte(s[(len-1-i)*8 +: 8]);
        end
    endtask

    // ---------------- UART 接收 ----------------
    task recv_byte(output [7:0] b, output reg ok);
        integer k;
        begin
            ok = 1'b0;
            fork
                begin
                    @(negedge uart0_tx);
                    #4340;
                    for (k = 0; k < 8; k = k + 1) begin
                        #8680;
                        b[k] = uart0_tx;
                    end
                    #8680;   // 停止位
                    ok = 1'b1;
                end
                begin
                    #5000000;   // 5ms 超时
                end
            join_any
            disable fork;
        end
    endtask

    // 接收一行（含 \r\n），存入 rbuf（LSB-first），返回长度
    reg [7:0] rbuf [0:255];
    integer rlen;
    task recv_line;
        reg [7:0] b;
        reg ok;
        begin
            rlen = 0;
            forever begin
                recv_byte(b, ok);
                if (!ok) begin
                    if (rlen == 0) rlen = -1;
                    disable recv_line;
                end
                if (b == 8'h0A) begin
                    if (rlen > 0 && rbuf[rlen-1] == 8'h0D) rlen = rlen - 1;
                    disable recv_line;
                end
                rbuf[rlen] = b;
                rlen = rlen + 1;
            end
        end
    endtask

    integer errors;

    // rbuf 是否包含 needle（右对齐字面量，len 字节）
    function contains(input integer nlen, input [8*64-1:0] needle);
        integer i, j;
        reg found;
        begin
            contains = 1'b0;
            found = 1'b0;
            for (i = 0; i + nlen <= rlen && !found; i = i + 1) begin
                for (j = 0; j < nlen && rbuf[i+j] == needle[(nlen-1-j)*8 +: 8]; j = j + 1);
                if (j == nlen) found = 1'b1;
            end
            contains = found;
        end
    endfunction

    task check(input integer nlen, input [8*64-1:0] needle);
        begin
            if (contains(nlen, needle)) begin
                $display("PASS: %0s", needle);
            end else begin
                $display("FAIL: expect %0s, got:", needle);
                $write("      ");
                for (integer i = 0; i < rlen; i = i + 1) $write("%c", rbuf[i]);
                $write("\n");
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- Modbus RTU（UART1） ----------------
    function [15:0] crc16m(input [1023:0] data, input integer len);
        integer i, b;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            for (i = 0; i < len; i = i + 1) begin
                crc = crc ^ data[i*8 +: 8];
                for (b = 0; b < 8; b = b + 1)
                    crc = (crc[0]) ? ((crc >> 1) ^ 16'hA001) : (crc >> 1);
            end
            crc16m = crc;
        end
    endfunction

    task mb_send_byte(input [7:0] b);
        integer k;
        begin
            uart1_rx = 1'b0; #8680;
            for (k = 0; k < 8; k = k + 1) begin
                uart1_rx = b[k]; #8680;
            end
            uart1_rx = 1'b1; #8680;
        end
    endtask

    task mb_recv_byte(output [7:0] b, output reg ok);
        integer k;
        begin
            ok = 1'b0;
            fork
                begin
                    @(negedge uart1_tx);
                    #4340;
                    for (k = 0; k < 8; k = k + 1) begin
                        #8680;
                        b[k] = uart1_tx;
                    end
                    #8680;
                    ok = 1'b1;
                end
                begin #5000000; end
            join_any
            disable fork;
        end
    endtask

    reg [7:0] mb_r [0:63];
    integer mb_rlen;
    task mb_recv_frame;
        reg [7:0] b;
        reg ok;
        integer idle;
        begin
            mb_rlen = 0;
            // 收到首字节后持续收，靠帧间隔（响应连续发送）
            mb_recv_byte(b, ok);
            if (ok) begin
                mb_r[0] = b; mb_rlen = 1;
                // 连续收 16 字节或超时
                for (idle = 0; idle < 16; idle = idle + 1) begin
                    mb_recv_byte(b, ok);
                    if (!ok) disable mb_recv_frame;
                    mb_r[mb_rlen] = b;
                    mb_rlen = mb_rlen + 1;
                end
            end
        end
    endtask

    // ---------------- 主流程 ----------------
    reg [7:0] b;
    reg ok;
    reg [8*64-1:0] vcmd;
    integer vi;
    reg [7:0] tok [0:42];
    reg [7:0] rb;
    reg rok;
    integer idle;

    initial begin
        errors = 0;
        btn_rst = 1;
        repeat (10) @(posedge clk);
        btn_rst = 0;

        // 1) 吸收 banner（两行）
        recv_line;
        recv_line;
        $display("banner ok");

        // 2) RoleAbility
        send_cmd("ability_RoleAbility set_role edge", 33);
        send_byte(8'h0A);
        recv_line;
        check(23, "OK set_role -> role=edge");

        send_cmd("ability_RoleAbility get_role", 28);
        send_byte(8'h0A);
        recv_line;
        check(23, "OK get_role -> role=edge");

        // 3) TimeAbility
        send_cmd("ability_TimeAbility sync_manual 1700000000", 42);
        send_byte(8'h0A);
        recv_line;
        check(34, "OK sync_manual -> epoch=1700000000");

        send_cmd("ability_TimeAbility get_time", 28);
        send_byte(8'h0A);
        recv_line;
        check(28, "{\"epoch\":1700000000}");

        // 4) ConfigData
        send_cmd("data_ConfigData set wifi.ssid=MyNet", 35);
        send_byte(8'h0A);
        recv_line;
        check(17, "OK set -> saved");

        send_cmd("data_ConfigData get wifi.ssid", 29);
        send_byte(8'h0A);
        recv_line;
        check(31, "{\"wifi.ssid\":\"MyNet\"}");

        // 5) BaseAbility / BaseData
        send_cmd("ability_BaseAbility list_data_names", 35);
        send_byte(8'h0A);
        recv_line;
        check(43, "{\"names\":[BaseData,ConfigData]}");

        send_cmd("data_BaseData info", 18);
        send_byte(8'h0A);
        recv_line;
        check(9, "BaseData");

        // 6) OneKey：签发（seq=0，subject 默认）→ 与 Python 参考值比对
        send_cmd("ability_OneKeyAbility issue_token", 33);
        send_byte(8'h0A);
        recv_line;
        check(52, "3Jc0-GMdPoWinQCFTfIV9TN-UxJkU-XcJh8xPBk1E_A");
        // 回验
        send_cmd("ability_OneKeyAbility verify_token 0:3Jc0-GMdPoWinQCFTfIV9TN-UxJkU-XcJh8xPBk1E_A", 80);
        send_byte(8'h0A);
        recv_line;
        check(31, "OK verify_token -> {\"valid\":true}");

        // 7) Modbus CLI
        send_cmd("ability_ModbusAbility write_holding 0,42", 40);
        send_byte(8'h0A);
        recv_line;
        check(31, "OK write_holding -> {\"written\":true}");

        send_cmd("ability_ModbusAbility read_holding 0,4", 38);
        send_byte(8'h0A);
        recv_line;
        check(26, "OK read_holding -> [42,0,0,0]");

        // 8) 未知目标
        send_cmd("foo bar", 7);
        send_byte(8'h0A);
        recv_line;
        check(14, "unknown target");

        // 9) Modbus RTU 从站（UART1）：读保持寄存器 0..1（其中 [0]=42）
        begin
            reg [1023:0] req;
            reg [15:0] crc;
            reg [7:0] expect_crc_lo, expect_crc_hi;
            req = {8'h01, 8'h03, 8'h00, 8'h00, 8'h00, 8'h02};  // LSB-first: [0]=01
            // 上面拼接后 01 在最高字节；改用逐字节发送
            mb_send_byte(8'h01);
            mb_send_byte(8'h03);
            mb_send_byte(8'h00);
            mb_send_byte(8'h00);
            mb_send_byte(8'h00);
            mb_send_byte(8'h02);
            crc = crc16m({504'h0, 8'h01, 8'h03, 8'h00, 8'h00, 8'h00, 8'h02}, 6);
            // Modbus CRC 低字节在前
            mb_send_byte(crc[7:0]);
            mb_send_byte(crc[15:8]);
            // 期望响应：01 03 04 00 2A 00 00 crcL crcH
            mb_recv_frame;
            if (mb_rlen == 9 && mb_r[0] == 8'h01 && mb_r[1] == 8'h03 &&
                mb_r[2] == 8'h04 && mb_r[3] == 8'h00 && mb_r[4] == 8'h2A &&
                mb_r[5] == 8'h00 && mb_r[6] == 8'h00) begin
                $display("PASS: modbus rtu read_holding");
            end else begin
                $display("FAIL: modbus rtu response len=%0d first=%02x", mb_rlen, mb_r[0]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d ERRORS", errors);
        $finish;
    end

    initial begin
        #400_000_000;   // 400ms 上限
        $display("FAIL: global timeout");
        $finish;
    end
endmodule
