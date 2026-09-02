// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// fe_ability_modbus.v — ModbusAbility（纯 RTL）
// CLI 侧：set_unit_id / get_unit_id / read_holding / read_input /
//         read_coils / read_discrete / write_holding / write_coil
//         （直接读写本地寄存器堆，同 MCU 版语义；CLI read 计数 ≤ 8）
// RTU 从站：UART1 监听功能码 0x01/0x02/0x03/0x04/0x05/0x06，
//           3.5 字符帧间隔定界，CRC16 校验，读计数 ≤ 32。
module fe_ability_modbus #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD     = 115200
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
    output reg         resp_done,
    // UART1（RTU 从站）
    input  wire        mb_rx,
    output wire        mb_tx
);
    // ---------------- 寄存器堆 ----------------
    reg [15:0] holding  [0:63];
    reg [15:0] inputr   [0:63];
    reg [63:0] coils;
    reg [63:0] disc;
    reg [7:0]  unit_id;

    // ---------------- CRC16（Modbus，输入帧 LSB-first） ----------------
    function [15:0] crc16(input [1023:0] data, input integer len);
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

    // ---------------- CLI 响应发送 ----------------
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;

    wire is_setuid  = (act == "set_unit_id");
    wire is_getuid  = (act == "get_unit_id");
    wire is_rhold   = (act == "read_holding");
    wire is_rinput  = (act == "read_input");
    wire is_rcoils  = (act == "read_coils");
    wire is_rdisc   = (act == "read_discrete");
    wire is_whold   = (act == "write_holding");
    wire is_wcoil   = (act == "write_coil");

    // 参数解析 "addr[,value]"
    reg [31:0] pa, pv;
    reg [5:0]  pi;
    reg [1:0]  pph;

    reg [5:0]  rcnt;
    reg        do_read;

    // 按当前下标 i 读寄存器堆（响应循环内使用）
    function [15:0] readval(input [5:0] idx);
        begin
            if (is_rhold)       readval = holding[pa + idx];
            else if (is_rinput) readval = inputr[pa + idx];
            else if (is_rcoils) readval = {15'b0, coils[pa + idx]};
            else if (is_rdisc)  readval = {15'b0, disc[pa + idx]};
            else                readval = 16'h0;
        end
    endfunction

    // 16 位 → 十进制（5 位）
    function [39:0] dec16(input [15:0] v);
        reg [39:0] digits;
        reg [15:0] x;
        integer d;
        begin
            x = v;
            for (d = 4; d >= 0; d = d - 1) begin
                digits[d*8 +: 8] = "0" + (x % 10);
                x = x / 10;
            end
            dec16 = digits;
        end
    endfunction

    // 读取响应 "[v,v,...]"（LSB-first）
    integer i;
    reg [39:0] ds;
    reg [7:0]  ds_len;
    reg [15:0] rv1;
    reg [3:0]  dpos;
    reg [3:0]  msb;
    reg        fd;
    integer    dpos2;
    reg [1023:0] rbuf;
    reg [7:0]  rlen;
    always @* begin
        rbuf = 0; rlen = 0;
        rbuf[0*8 +: 8] = "["; rlen = 1;  // 字节 0（此前误用位选导致首字节=0x01）
        for (i = 0; i < 8; i = i + 1) begin
            if (i < rcnt) begin
                if (i != 0) begin rbuf[rlen*8 +: 8] = ","; rlen = rlen + 1; end
                if (is_rcoils || is_rdisc) begin
                    rv1 = readval(i[5:0]);
                    rbuf[rlen*8 +: 8] = rv1[0] ? "1" : "0"; rlen = rlen + 1;
                end else begin
                    rv1 = readval(i[5:0]);
                    ds = dec16(rv1);
                    // 找最高非零位（4=个位…0=万位）；全 0 → fd=0
                    msb = 0; fd = 1'b0;
                    for (dpos2 = 4; dpos2 >= 0; dpos2 = dpos2 - 1)
                        if (ds[dpos2*8 +: 8] != "0") begin msb = dpos2; fd = 1'b1; end
                    if (!fd) begin
                        rbuf[rlen*8 +: 8] = "0"; rlen = rlen + 1;
                    end else begin
                        for (dpos = msb; dpos <= 4; dpos = dpos + 1) begin
                            rbuf[rlen*8 +: 8] = ds[dpos*8 +: 8];
                            rlen = rlen + 1;
                        end
                    end
                end
            end
        end
        rbuf[rlen*8 +: 8] = "]"; rlen = rlen + 1;
    end

    // LSB-first → 右对齐段
    reg [1023:0] rrev;
    always @* begin
        rrev = 0;
        for (i = 0; i < 128; i = i + 1)
            if (i < rlen) rrev[(rlen-1-i)*8 +: 8] = rbuf[i*8 +: 8];
    end

    localparam S_IDLE = 0, S_PARSE = 1, S_EMIT = 2;
    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0; state <= S_IDLE;
            pa <= 0; pv <= 0; pi <= 0; pph <= 0;
            rcnt <= 0; do_read <= 0; unit_id <= 8'd1;
            coils <= 0; disc <= 0;
            for (i = 0; i < 64; i = i + 1) begin
                holding[i] <= 0; inputr[i] <= 0;
            end
        end else begin
            resp_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        do_read <= 1'b0;
                        pa <= 0; pv <= 0; pi <= 0; pph <= 0;
                        if (is_getuid) begin
                            resp_ok <= 1'b1;
                            s0 <= {"unit_id=", 3'b0, dec16(unit_id)}; l0 <= 12;
                            ns <= 2'd1;
                            resp_start <= 1'b1;
                        end else if (is_setuid || is_rhold || is_rinput ||
                                     is_rcoils || is_rdisc || is_whold || is_wcoil) begin
                            do_read <= is_rhold | is_rinput | is_rcoils | is_rdisc;
                            state   <= S_PARSE;
                        end else begin
                            resp_ok <= 1'b0;
                            s0 <= "unsupported command"; l0 <= 19; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end
                    end
                end
                S_PARSE: begin
                    if (args[pi*8 +: 8] == 8'h00 || pi >= 63) begin
                        // 读计数提前落定，供 S_EMIT 的组合响应缓冲使用
                        rcnt <= (pv == 0) ? 6'd1 : pv[5:0];
                        state <= S_EMIT;
                    end else if (args[pi*8 +: 8] == 8'h2C) begin
                        pph <= 2'd1; pi <= pi + 1;
                    end else if (args[pi*8 +: 8] >= 8'h30 &&
                                 args[pi*8 +: 8] <= 8'h39) begin
                        if (pph == 2'd0) pa <= pa * 10 + args[pi*8 +: 8] - 8'h30;
                        else             pv <= pv * 10 + args[pi*8 +: 8] - 8'h30;
                        pi <= pi + 1;
                    end else begin
                        pi <= pi + 1;
                    end
                end
                S_EMIT: begin
                    resp_start <= 1'b1;
                    if (is_setuid) begin
                        if (pa == 0 || pa > 247) begin
                            resp_ok <= 1'b0;
                            s0 <= "invalid unit id"; l0 <= 14; ns <= 2'd1;
                        end else begin
                            unit_id <= pa[7:0];
                            resp_ok <= 1'b1;
                            s0 <= {"unit_id=", 3'b0, dec16(pa[15:0])}; l0 <= 12; ns <= 2'd1;
                        end
                    end else if (do_read) begin
                        if (pa + pv > 64) begin
                            resp_ok <= 1'b0;
                            s0 <= "addr out of range"; l0 <= 16; ns <= 2'd1;
                        end else if (pv > 8) begin
                            resp_ok <= 1'b0;
                            s0 <= "count too large"; l0 <= 15; ns <= 2'd1;
                        end else begin
                            resp_ok <= 1'b1;
                            s0 <= rrev; l0 <= rlen; ns <= 2'd1;
                        end
                    end else if (is_whold) begin
                        if (pa >= 64) begin
                            resp_ok <= 1'b0;
                            s0 <= "addr out of range"; l0 <= 16; ns <= 2'd1;
                        end else begin
                            holding[pa[5:0]] <= pv[15:0];
                            resp_ok <= 1'b1;
                            s0 <= "{\"written\":true}"; l0 <= 16; ns <= 2'd1;
                        end
                    end else if (is_wcoil) begin
                        if (pa >= 64) begin
                            resp_ok <= 1'b0;
                            s0 <= "addr out of range"; l0 <= 16; ns <= 2'd1;
                        end else begin
                            coils[pa[5:0]] <= (pv != 0);
                            resp_ok <= 1'b1;
                            s0 <= "{\"written\":true}"; l0 <= 16; ns <= 2'd1;
                        end
                    end else begin
                        resp_ok <= 1'b0;
                        s0 <= "missing args"; l0 <= 12; ns <= 2'd1;
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

    // ============================================================
    // RTU 从站引擎（UART1，帧 LSB-first）
    // ============================================================
    wire [7:0] mb_rxd;  wire mb_rxv;
    reg        mb_txs;  reg [7:0] mb_txd;  wire mb_txb;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u1rx(
        .clk(clk), .rst(rst), .rx(mb_rx), .data(mb_rxd), .valid(mb_rxv)
    );
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u1tx(
        .clk(clk), .rst(rst), .start(mb_txs), .data(mb_txd), .tx(mb_tx), .busy(mb_txb)
    );

    // Modbus RTU requires at least 3.5 character times of silence.  With 8N1
    // one character is 10 bits, so use 35 bit periods (not four bit periods).
    localparam integer T35 = (CLK_FREQ / BAUD) * 35;

    localparam M_IDLE = 0, M_RX = 1, M_CHK = 2, M_EXEC = 3, M_EXECW = 4,
               M_CRC = 5, M_CRC2 = 6, M_TX = 7, M_TXW = 8;
    reg [3:0] mstate;

    reg [63:0]  fbuf;          // 请求帧（LSB-first，≤8 字节）
    reg [3:0]   fidx;
    reg [21:0]  gapcnt;
    reg [1023:0] respf;        // 响应帧（LSB-first）
    reg [7:0]   rflen;
    reg [7:0]   rfi;
    reg [15:0]  ra, rv, rc;
    reg [4:0]   exec_k;        // 读拷贝步进
    reg [7:0]   rbyte;
    reg [2:0]   bitk;
    reg [15:0]  m_crc;

    // RTU 位打包（组合）：第 exec_k 字节的 8 个位（LSB 在前）
    reg [7:0] packbits;
    reg [3:0] nvalid;
    wire [15:0] bits_left = rc - {10'b0, exec_k, 3'b000};
    always @* begin
        nvalid = (bits_left >= 16'd8) ? 4'd8 : bits_left[3:0];
        for (i = 0; i < 8; i = i + 1)
            packbits[i] = (i[3:0] < nvalid) ?
                ((fbuf[1*8 +: 8] == 8'h01) ?
                    coils[ra + {exec_k, 3'b000} + i[2:0]] :
                    disc[ra + {exec_k, 3'b000} + i[2:0]]) : 1'b0;
    end

    wire [15:0] req_crc = crc16(fbuf, fidx - 2);

    always @(posedge clk) begin
        if (rst) begin
            mstate <= M_IDLE; fidx <= 0; gapcnt <= 0; mb_txs <= 0;
            respf <= 0; rflen <= 0; rfi <= 0; ra <= 0; rv <= 0; rc <= 0;
            exec_k <= 0; rbyte <= 0; bitk <= 0; m_crc <= 0; fbuf <= 0;
        end else begin
            mb_txs <= 1'b0;
            case (mstate)
                M_IDLE: begin
                    if (mb_rxv) begin
                        fbuf[7:0] <= mb_rxd;
                        fidx   <= 1;
                        gapcnt <= 0;
                        mstate <= M_RX;
                    end
                end
                M_RX: begin
                    if (mb_rxv) begin
                        if (fidx < 8) begin
                            fbuf[fidx*8 +: 8] <= mb_rxd;
                            fidx <= fidx + 1;
                        end else begin
                            // 固定长度请求超过 8B 即丢弃。不要继续递增 4 位
                            // fidx，否则 16B 后会回绕成 8 并误验旧缓冲内容。
                            fidx <= 4'd9;
                        end
                        gapcnt <= 0;
                    end else begin
                        // 用原始 RX 线测空闲：低电平=有活动立即清零，
                        // 高电平持续 T35（≈3.5 字符）才判帧结束。
                        // 不能按 valid 脉冲计——字节间 valid 间隔≈10 位，会误判。
                        if (!mb_rx) gapcnt <= 0;
                        else begin
                            gapcnt <= gapcnt + 1;
                            if (gapcnt >= T35 - 1) mstate <= M_CHK;
                        end
                    end
                end
                M_CHK: begin
                    // 完整请求帧 = 8 字节（id fc aH aL cH cL crcL crcH）
                    if (fidx != 8 || fbuf[0*8 +: 8] != unit_id ||
                        req_crc != {fbuf[7*8 +: 8], fbuf[6*8 +: 8]}) begin
                        mstate <= M_IDLE;      // 静默丢弃
                    end else begin
                        ra <= {fbuf[2*8 +: 8], fbuf[3*8 +: 8]};
                        rc <= {fbuf[4*8 +: 8], fbuf[5*8 +: 8]};
                        rv <= {fbuf[4*8 +: 8], fbuf[5*8 +: 8]};
                        mstate <= M_EXEC;
                    end
                end
                M_EXEC: begin
                    // 装配响应头
                    respf[0*8 +: 8] <= fbuf[0*8 +: 8];   // 站号回显
                    respf[1*8 +: 8] <= fbuf[1*8 +: 8];   // 功能码回显
                    rflen <= 2;
                    exec_k <= 0;
                    case (fbuf[1*8 +: 8])
                        8'h03, 8'h04: begin
                            if (ra + rc > 64 || rc == 0) begin
                                respf[1*8 +: 8] <= fbuf[1*8 +: 8] | 8'h80;
                                respf[2*8 +: 8] <= 8'h02;
                                rflen <= 3;
                                mstate <= M_CRC;
                            end else begin
                                respf[2*8 +: 8] <= {5'b0, rc[4:0], 1'b0}; // cnt*2 ≤ 64
                                rflen <= 3;
                                mstate <= M_EXECW;
                            end
                        end
                        8'h01, 8'h02: begin
                            if (ra + rc > 64 || rc == 0) begin
                                respf[1*8 +: 8] <= fbuf[1*8 +: 8] | 8'h80;
                                respf[2*8 +: 8] <= 8'h02;
                                rflen <= 3;
                                mstate <= M_CRC;
                            end else begin
                                respf[2*8 +: 8] <= (rc + 7) >> 3;
                                rflen <= 3;
                                mstate <= M_EXECW;
                            end
                        end
                        8'h05: begin
                            // 写单线圈：地址必须在寄存器映射内，0xFF00=ON。
                            if (ra >= 64) begin
                                respf[1*8 +: 8] <= 8'h85;
                                respf[2*8 +: 8] <= 8'h02; // illegal data address
                                rflen <= 3;
                            end else if (rv == 16'hFF00 || rv == 16'h0000) begin
                                coils[ra[5:0]] <= (rv == 16'hFF00);
                                respf[2*8 +: 8] <= fbuf[2*8 +: 8];
                                respf[3*8 +: 8] <= fbuf[3*8 +: 8];
                                respf[4*8 +: 8] <= fbuf[4*8 +: 8];
                                respf[5*8 +: 8] <= fbuf[5*8 +: 8];
                                rflen <= 6;
                            end else begin
                                respf[1*8 +: 8] <= 8'h85;
                                respf[2*8 +: 8] <= 8'h03;
                                rflen <= 3;
                            end
                            mstate <= M_CRC;
                        end
                        8'h06: begin
                            // 写单保持寄存器；禁止高地址被 ra[5:0] 静默回绕。
                            if (ra >= 64) begin
                                respf[1*8 +: 8] <= 8'h86;
                                respf[2*8 +: 8] <= 8'h02; // illegal data address
                                rflen <= 3;
                            end else begin
                                holding[ra[5:0]] <= rv;
                                respf[2*8 +: 8] <= fbuf[2*8 +: 8];
                                respf[3*8 +: 8] <= fbuf[3*8 +: 8];
                                respf[4*8 +: 8] <= fbuf[4*8 +: 8];
                                respf[5*8 +: 8] <= fbuf[5*8 +: 8];
                                rflen <= 6;
                            end
                            mstate <= M_CRC;
                        end
                        default: mstate <= M_IDLE;
                    endcase
                end
                M_EXECW: begin
                    if (fbuf[1*8 +: 8] == 8'h03 || fbuf[1*8 +: 8] == 8'h04) begin
                        // 一字一拍：高字节在前
                        respf[rflen*8 +: 8] <= (fbuf[1*8 +: 8] == 8'h03) ?
                            holding[ra + exec_k][15:8] : inputr[ra + exec_k][15:8];
                        respf[(rflen+1)*8 +: 8] <= (fbuf[1*8 +: 8] == 8'h03) ?
                            holding[ra + exec_k][7:0] : inputr[ra + exec_k][7:0];
                        rflen  <= rflen + 2;
                        exec_k <= exec_k + 1;
                        if (exec_k + 1 >= rc[5:0]) mstate <= M_CRC;
                    end else begin
                        // 位模式：一字节一拍
                        respf[rflen*8 +: 8] <= packbits;
                        rflen  <= rflen + 1;
                        exec_k <= exec_k + 1;
                        if (exec_k + 1 >= ((rc + 7) >> 3)) mstate <= M_CRC;
                    end
                end
                M_CRC: begin
                    m_crc <= crc16(respf, rflen);
                    mstate <= M_CRC2;
                end
                M_CRC2: begin
                    respf[rflen*8 +: 8] <= m_crc[7:0];
                    respf[(rflen+1)*8 +: 8] <= m_crc[15:8];
                    rflen  <= rflen + 2;
                    rfi    <= 0;
                    mstate <= M_TX;
                end
                M_TX: begin
                    if (!mb_txb && rfi < rflen) begin
                        mb_txd <= respf[rfi*8 +: 8];
                        mb_txs <= 1'b1;
                        rfi    <= rfi + 1;
                        mstate <= M_TXW;
                    end else if (rfi >= rflen) begin
                        mstate <= M_IDLE;
                    end
                end
                M_TXW: begin
                    if (!mb_txb) mstate <= M_TX;
                end
                default: mstate <= M_IDLE;
            endcase
        end
    end
endmodule
