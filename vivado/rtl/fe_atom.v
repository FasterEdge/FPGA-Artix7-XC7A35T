`timescale 1ns/1ps
// fe_atom.v — FasterEdge Atom 框架核心（纯 RTL）
// 串口命令解释器："<data|ability>_<Name> <act> [args]"
// 组成：UART0 收发 + 行缓冲 + 分词 + 注册表分发 + 响应装配。
// 对应 MCU 版 main.c / fe.c 的 Atom 路由模型。
module fe_atom #(
    parameter integer CLK_FREQ = 100000000,
    parameter integer BAUD     = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_rx,
    output wire uart_tx,
    // 能力模块总线
    output reg          base_start,
    output reg          role_start,
    output reg          time_start,
    output reg          onekey_start,
    output reg          modbus_start,
    output reg          datab_start,
    output reg          config_start,
    output wire [255:0] cmd_act,
    output wire [511:0] cmd_args,
    // 各模块响应通道
    input  wire base_rs,   input  wire base_ok,
    input  wire base_v,    input  wire [7:0] base_d,
    output reg  base_r,    input  wire base_dn,
    input  wire role_rs,   input  wire role_ok,
    input  wire role_v,    input  wire [7:0] role_d,
    output reg  role_r,    input  wire role_dn,
    input  wire time_rs,   input  wire time_ok,
    input  wire time_v,    input  wire [7:0] time_d,
    output reg  time_r,    input  wire time_dn,
    input  wire onekey_rs, input  wire onekey_ok,
    input  wire onekey_v,  input  wire [7:0] onekey_d,
    output reg  onekey_r,  input  wire onekey_dn,
    input  wire modbus_rs, input  wire modbus_ok,
    input  wire modbus_v,  input  wire [7:0] modbus_d,
    output reg  modbus_r,  input  wire modbus_dn,
    input  wire datab_rs,  input  wire datab_ok,
    input  wire datab_v,   input  wire [7:0] datab_d,
    output reg  datab_r,   input  wire datab_dn,
    input  wire config_rs, input  wire config_ok,
    input  wire config_v,  input  wire [7:0] config_d,
    output reg  config_r,  input  wire config_dn,
    // 状态输出（LED）
    output wire led_busy,
    output wire led_rx
);
`include "fe_registry.vh"

    localparam integer BIT_PERIOD = CLK_FREQ / BAUD;

    // ---------------- UART0 ----------------
    wire [7:0] rxd;  wire rxv;
    reg        txs;  reg [7:0] txd;  wire txb;
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u0rx(
        .clk(clk), .rst(rst), .rx(uart_rx), .data(rxd), .valid(rxv));
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u0tx(
        .clk(clk), .rst(rst), .start(txs), .data(txd), .tx(uart_tx), .busy(txb));

    // ---------------- 文本常量 ----------------
    localparam integer BANNER_LEN = 89;
    localparam [8*89-1:0] BANNER =
        "FasterEdge-FPGA (Artix-7 XC7A35T)\015\012input: <data|ability>_<Name> <act> [args]  |  'help'\015\012";
    localparam integer HELP_LEN = 272;
    localparam [8*272-1:0] HELP =
        "Usage: <data|ability>_<Name> <act> [args]\015\012abilities: BaseAbility,RoleAbility,TimeAbility,OneKeyAbility,ModbusAbility\015\012data: BaseData,ConfigData\015\012examples:\015\012  ability_TimeAbility get_time\015\012  ability_ModbusAbility write_holding 0,42\015\012  data_ConfigData set wifi.ssid=MyNet\015\012";

    // ---------------- 行缓冲与分词 ----------------
    reg [767:0] line;        // 96B LSB-first
    reg [6:0]   line_len;
    reg [255:0] t_tok;       // target（右对齐）
    reg [255:0] a_tok;       // act（右对齐）
    reg [511:0] a_args;      // args（LSB-first）
    reg [5:0]   alen;
    reg [255:0] ttmp;
    reg [5:0]   tlen;
    reg [255:0] atmp;
    reg [5:0]   argi;
    reg [6:0]   ph;
    reg [1:0]   tphase;      // 0=target 1=act 2=args

    assign cmd_act  = a_tok;
    assign cmd_args = a_args;

    // 目标分发
    wire sel_base_ab = (t_tok == T_BASE_ABILITY);
    wire sel_role    = (t_tok == T_ROLE);
    wire sel_time    = (t_tok == T_TIME);
    wire sel_onekey  = (t_tok == T_ONEKEY);
    wire sel_modbus  = (t_tok == T_MODBUS);
    wire sel_datab   = (t_tok == T_BASE_DATA);
    wire sel_config  = (t_tok == T_CONFIG);
    wire sel_any = sel_base_ab | sel_role | sel_time | sel_onekey |
                   sel_modbus | sel_datab | sel_config;

    wire sel_rs = sel_base_ab ? base_rs  : sel_role ? role_rs  :
                  sel_time   ? time_rs  : sel_onekey ? onekey_rs :
                  sel_modbus ? modbus_rs : sel_datab ? datab_rs : config_rs;
    wire sel_ok = sel_base_ab ? base_ok  : sel_role ? role_ok  :
                  sel_time   ? time_ok  : sel_onekey ? onekey_ok :
                  sel_modbus ? modbus_ok : sel_datab ? datab_ok : config_ok;
    wire sel_v  = sel_base_ab ? base_v   : sel_role ? role_v   :
                  sel_time   ? time_v   : sel_onekey ? onekey_v  :
                  sel_modbus ? modbus_v : sel_datab ? datab_v  : config_v;
    wire [7:0] sel_d = sel_base_ab ? base_d : sel_role ? role_d :
                  sel_time ? time_d : sel_onekey ? onekey_d :
                  sel_modbus ? modbus_d : sel_datab ? datab_d : config_d;
    wire sel_dn = sel_base_ab ? base_dn : sel_role ? role_dn :
                  sel_time ? time_dn : sel_onekey ? onekey_dn :
                  sel_modbus ? modbus_dn : sel_datab ? datab_dn : config_dn;

    // ---------------- 主状态机 ----------------
    localparam BOOT = 0, RX = 1, TOK = 2, TOKEND = 3, DISPATCH = 4,
               WAIT = 5, TX_BYTE = 6, TX_WAITB = 7, TX_WAITI = 8, MODPASS = 9,
               IDLEWAIT = 10;
    // txphase: 0=banner/help 1=OK/ERR 2=act 3=sep 4=模块流 5=CRLF 6=未知目标文本
    reg [3:0]  state;
    reg [3:0]  txphase;
    reg [7:0]  txidx;
    reg [7:0]  txlen;
    reg [1023:0] txsrc;
    reg        tx_ok;
    reg        mod_active;
    reg        mod_done_q;
    reg [19:0] watchdog;
    reg        led_rx_q;
    reg [1:0]  rx_sync;
    reg [15:0] idle_cnt;
    reg        is_help;

    assign led_busy = (state != RX);
    assign led_rx   = led_rx_q;

    integer ri;

    always @(posedge clk) begin
        if (rst) begin
            state <= BOOT; txphase <= 0; txidx <= 0; txlen <= BANNER_LEN;
            txsrc <= BANNER; txs <= 0; txd <= 0;
            line <= 0; line_len <= 0; t_tok <= 0; a_tok <= 0; a_args <= 0; alen <= 0;
            ttmp <= 0; tlen <= 0; atmp <= 0; argi <= 0; ph <= 0; tphase <= 0;
            base_start <= 0; role_start <= 0; time_start <= 0;
            onekey_start <= 0; modbus_start <= 0;
            datab_start <= 0; config_start <= 0;
            base_r <= 0; role_r <= 0; time_r <= 0; onekey_r <= 0; modbus_r <= 0;
            datab_r <= 0; config_r <= 0;
            tx_ok <= 0; mod_active <= 0; mod_done_q <= 0;
            watchdog <= 0; led_rx_q <= 0;
            rx_sync <= 0; idle_cnt <= 0; is_help <= 0;
        end else begin
            txs <= 1'b0;
            rx_sync <= {rx_sync[0], uart_rx};
            // 模块 start 默认清零（仅 DISPATCH 拍一周期高电平），
            // 否则模块 S_SET 回 S_IDLE 后会因 start 持续为高而无限重触发
            base_start <= 1'b0; role_start <= 1'b0; time_start <= 1'b0;
            onekey_start <= 1'b0; modbus_start <= 1'b0;
            datab_start <= 1'b0; config_start <= 1'b0;
            base_r <= 1'b0; role_r <= 1'b0; time_r <= 1'b0;
            onekey_r <= 1'b0; modbus_r <= 1'b0; datab_r <= 1'b0; config_r <= 1'b0;
            if (sel_dn) mod_done_q <= 1'b1;   // 锁存模块完成脉冲

            case (state)
                BOOT: begin
                    txphase <= 0;
                    state   <= TX_BYTE;
                end
                RX: begin
                    if (rxv) begin
                        led_rx_q <= ~led_rx_q;
                        if (rxd == 8'h0A || rxd == 8'h0D) begin
                            if (line_len != 0) begin
                                if (line_len == 7'd4 && line[31:0] == "pleh") begin
                                    is_help  <= 1'b1;
                                    txphase  <= 0; txidx <= 0;
                                    txlen    <= HELP_LEN; txsrc <= HELP;
                                    line_len <= 0;
                                    idle_cnt <= 0;
                                    state    <= IDLEWAIT;
                                end else begin
                                    is_help  <= 1'b0;
                                    ph <= 0; tphase <= 0; argi <= 0;
                                    ttmp <= 0; tlen <= 0; atmp <= 0; alen <= 0;
                                    a_args <= 0;
                                    idle_cnt <= 0;
                                    state <= IDLEWAIT;
                                end
                            end
                        end else if (line_len < 96) begin
                            line[line_len*8 +: 8] <= rxd;
                            line_len <= line_len + 1;
                        end
                    end
                end
                TOK: begin
                    if (ph >= line_len) begin
                        state <= TOKEND;
                    end else begin
                        case (tphase)
                            2'd0: begin
                                if (line[ph*8 +: 8] == 8'h20) begin
                                    tphase <= 2'd1;
                                end else if (tlen < 32) begin
                                    ttmp[tlen*8 +: 8] <= line[ph*8 +: 8];
                                    tlen <= tlen + 1;
                                end
                            end
                            2'd1: begin
                                if (line[ph*8 +: 8] == 8'h20) begin
                                    tphase <= 2'd2;
                                end else if (alen < 32) begin
                                    atmp[alen*8 +: 8] <= line[ph*8 +: 8];
                                    alen <= alen + 1;
                                end
                            end
                            default: begin
                                if (argi < 64) begin
                                    a_args[argi*8 +: 8] <= line[ph*8 +: 8];
                                    argi <= argi + 1;
                                end
                            end
                        endcase
                        ph <= ph + 1;
                    end
                end
                TOKEND: begin
                    // 先整体清零，避免上次命令的高位字节残留污染比较
                    t_tok <= 0;
                    a_tok <= 0;
                    for (ri = 0; ri < 32; ri = ri + 1) begin
                        if (ri < tlen) t_tok[(tlen-1-ri)*8 +: 8] <= ttmp[ri*8 +: 8];
                        if (ri < alen) a_tok[(alen-1-ri)*8 +: 8] <= atmp[ri*8 +: 8];
                    end
                    state <= DISPATCH;
                end
                DISPATCH: begin
                    base_start   <= sel_base_ab;
                    role_start   <= sel_role;
                    time_start   <= sel_time;
                    onekey_start <= sel_onekey;
                    modbus_start <= sel_modbus;
                    datab_start  <= sel_datab;
                    config_start <= sel_config;
                    mod_active   <= sel_any;
                    mod_done_q   <= 1'b0;
                    tx_ok        <= 1'b0;
                    if (sel_any) begin
                        state <= WAIT;
                    end else begin
                        txphase <= 1; txidx <= 0;
                        txsrc   <= "ERR "; txlen <= 4;
                        state   <= TX_BYTE;
                    end
                end
                WAIT: begin
                    watchdog <= watchdog + 1;
                    if (sel_rs) begin
                        watchdog <= 0;
                        tx_ok    <= sel_ok;
                        txphase  <= 1; txidx <= 0;
                        txsrc    <= sel_ok ? "OK " : "ERR ";
                        txlen    <= sel_ok ? 3 : 4;
                        state    <= TX_BYTE;
                    end else if (watchdog == 20'hFFFFF) begin
                        watchdog <= 0;
                        line_len <= 0;
                        state    <= RX;
                    end
                end
                TX_BYTE: begin
                    if (txphase == 4) begin
                        state <= MODPASS;
                    end else if (txphase == 2) begin
                        // act 回显
                        if (txidx < alen) begin
                            if (!txb) begin
                                txd   <= a_tok[(alen-1-txidx)*8 +: 8];
                                txs   <= 1'b1;
                                txidx <= txidx + 1;
                                state <= TX_WAITB;
                            end
                        end else begin
                            txphase <= 3; txidx <= 0;
                            txsrc   <= tx_ok ? " -> " : ": ";
                            txlen   <= tx_ok ? 4 : 2;
                        end
                    end else begin
                        // 常量段（0/1/3/5/6 共用 txsrc/txlen）
                        if (txidx < txlen) begin
                            if (!txb) begin
                                txd   <= txsrc[(txlen-1-txidx)*8 +: 8];
                                txs   <= 1'b1;
                                txidx <= txidx + 1;
                                state <= TX_WAITB;
                            end
                        end else begin
                            case (txphase)
                                4'd0: begin
                                    line_len <= 0;
                                    state    <= RX;
                                end
                                4'd1: begin
                                    txphase <= 2; txidx <= 0;
                                end
                                4'd3: begin
                                    if (mod_active) begin
                                        txphase <= 4; txidx <= 0;
                                        state   <= MODPASS;
                                    end else begin
                                        txphase <= 6; txidx <= 0;
                                        txsrc   <= "unknown target";
                                        txlen   <= 14;
                                    end
                                end
                                4'd6: begin
                                    txphase <= 5; txidx <= 0;
                                    txsrc   <= "\015\012";
                                    txlen   <= 2;
                                end
                                default: begin   // 5 = CRLF 结束
                                    line_len <= 0;
                                    state    <= RX;
                                end
                            endcase
                        end
                    end
                end
                TX_WAITB: begin
                    if (txb) state <= TX_WAITI;
                end
                TX_WAITI: begin
                    if (!txb) state <= TX_BYTE;
                end
                IDLEWAIT: begin
                    // 等 uart_rx 保持高电平满 BIT_PERIOD，确保上一字节停止位结束
                    if (rx_sync[1]) idle_cnt <= idle_cnt + 1;
                    else           idle_cnt <= 0;
                    if (idle_cnt >= BIT_PERIOD[15:0]) begin
                        if (is_help) begin
                            txidx <= 0;
                            state <= TX_BYTE;
                        end else begin
                            state <= TOK;
                        end
                    end
                end
                MODPASS: begin
                    watchdog <= watchdog + 1;
                    // 先发送待发字节：最后一个字节与 resp_done 同拍出现，
                    // 必须先消费掉，避免 mod_done_q 提前导致丢尾字节。
                    if (sel_v && !txb) begin
                        watchdog <= 0;
                        txd      <= sel_d;
                        txs      <= 1'b1;
                        base_r   <= sel_base_ab;
                        role_r   <= sel_role;
                        time_r   <= sel_time;
                        onekey_r <= sel_onekey;
                        modbus_r <= sel_modbus;
                        datab_r  <= sel_datab;
                        config_r <= sel_config;
                        state    <= TX_WAITB;
                    end else if (mod_done_q || watchdog == 20'hFFFFF) begin
                        watchdog  <= 0;
                        mod_done_q<= 1'b0;
                        txphase   <= 5; txidx <= 0;
                        txsrc     <= "\015\012";
                        txlen     <= 2;
                        state     <= TX_BYTE;
                    end
                end
                default: state <= RX;
            endcase
        end
    end
endmodule
