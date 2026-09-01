// ─────────────────────────────────────────────────────────────
// FasterEdge 开源项目
// Github: https://github.com/FasterEdge
// Gitee:  https://gitee.com/FasterEdge
// ─────────────────────────────────────────────────────────────
`timescale 1ns/1ps
// fe_top.v — FasterEdge FPGA 顶层（Basys3 / XC7A35T）
// 100MHz 时钟直入，UART0 = 命令行控制台（板载 USB-UART），
// UART1 = Modbus RTU 从站（Pmod JB），LED 显示状态。
module fe_top (
    input  wire       clk100,        // 100MHz（Basys3: E3）
    input  wire       btn_rst,       // 复位（高有效；CPU_RESETN 低有效板卡请在外部取反）
    input  wire       uart0_rx,      // 控制台 RX（Basys3: B18）
    output wire       uart0_tx,      // 控制台 TX（Basys3: A18）
    input  wire       uart1_rx,      // Modbus RTU RX（Pmod JB）
    output wire       uart1_tx,      // Modbus RTU TX（Pmod JB）
    output wire [3:0] led            // [0]=命令处理中 [1]=收发活动 [2]=心跳 [3]=保留
);
    // 复位同步（高有效，两拍）
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_sync = 2'b11;
    // Asynchronously assert reset, then synchronously release it.  This also
    // gives simulation and hardware a defined power-up reset state.
    always @(posedge clk100 or posedge btn_rst) begin
        if (btn_rst) rst_sync <= 2'b11;
        else         rst_sync <= {rst_sync[0], 1'b0};
    end
    wire rst = rst_sync[1];

    // 心跳
    reg [23:0] hb;
    always @(posedge clk100) begin
        if (rst) hb <= 24'b0;
        else     hb <= hb + 1'b1;
    end

    // Atom ↔ 模块总线
    wire [255:0] atom_act;
    wire [511:0] atom_args;
    wire atom_base_start, atom_role_start, atom_time_start,
         atom_onekey_start, atom_modbus_start, atom_datab_start, atom_config_start;

    wire        base_rs, base_ok, base_v, base_dn, base_r;
    wire [7:0]  base_d;
    wire        role_rs, role_ok, role_v, role_dn, role_r;
    wire [7:0]  role_d;
    wire        time_rs, time_ok, time_v, time_dn, time_r;
    wire [7:0]  time_d;
    wire        onekey_rs, onekey_ok, onekey_v, onekey_dn, onekey_r;
    wire [7:0]  onekey_d;
    wire        modbus_rs, modbus_ok, modbus_v, modbus_dn, modbus_r;
    wire [7:0]  modbus_d;
    wire        datab_rs, datab_ok, datab_v, datab_dn, datab_r;
    wire [7:0]  datab_d;
    wire        config_rs, config_ok, config_v, config_dn, config_r;
    wire [7:0]  config_d;
    wire        led_busy, led_rx;

    fe_atom #(.CLK_FREQ(100000000), .BAUD(115200)) atom (
        .clk(clk100), .rst(rst),
        .uart_rx(uart0_rx), .uart_tx(uart0_tx),
        .base_start(atom_base_start), .role_start(atom_role_start),
        .time_start(atom_time_start), .onekey_start(atom_onekey_start),
        .modbus_start(atom_modbus_start),
        .datab_start(atom_datab_start), .config_start(atom_config_start),
        .cmd_act(atom_act), .cmd_args(atom_args),
        .base_rs(base_rs), .base_ok(base_ok), .base_v(base_v),
        .base_d(base_d), .base_r(base_r), .base_dn(base_dn),
        .role_rs(role_rs), .role_ok(role_ok), .role_v(role_v),
        .role_d(role_d), .role_r(role_r), .role_dn(role_dn),
        .time_rs(time_rs), .time_ok(time_ok), .time_v(time_v),
        .time_d(time_d), .time_r(time_r), .time_dn(time_dn),
        .onekey_rs(onekey_rs), .onekey_ok(onekey_ok), .onekey_v(onekey_v),
        .onekey_d(onekey_d), .onekey_r(onekey_r), .onekey_dn(onekey_dn),
        .modbus_rs(modbus_rs), .modbus_ok(modbus_ok), .modbus_v(modbus_v),
        .modbus_d(modbus_d), .modbus_r(modbus_r), .modbus_dn(modbus_dn),
        .datab_rs(datab_rs), .datab_ok(datab_ok), .datab_v(datab_v),
        .datab_d(datab_d), .datab_r(datab_r), .datab_dn(datab_dn),
        .config_rs(config_rs), .config_ok(config_ok), .config_v(config_v),
        .config_d(config_d), .config_r(config_r), .config_dn(config_dn),
        .led_busy(led_busy), .led_rx(led_rx)
    );

    fe_data_base datab0(
        .clk(clk100), .rst(rst), .start(atom_datab_start),
        .act(atom_act),
        .resp_start(datab_rs), .resp_ok(datab_ok), .resp_valid(datab_v),
        .resp_data(datab_d), .resp_ready(datab_r), .resp_done(datab_dn));

    fe_data_config config0(
        .clk(clk100), .rst(rst), .start(atom_config_start),
        .act(atom_act), .args(atom_args),
        .resp_start(config_rs), .resp_ok(config_ok), .resp_valid(config_v),
        .resp_data(config_d), .resp_ready(config_r), .resp_done(config_dn));

    fe_ability_base base0(
        .clk(clk100), .rst(rst), .start(atom_base_start),
        .act(atom_act),
        .resp_start(base_rs), .resp_ok(base_ok), .resp_valid(base_v),
        .resp_data(base_d), .resp_ready(base_r), .resp_done(base_dn));

    fe_ability_role role0(
        .clk(clk100), .rst(rst), .start(atom_role_start),
        .act(atom_act), .args(atom_args),
        .resp_start(role_rs), .resp_ok(role_ok), .resp_valid(role_v),
        .resp_data(role_d), .resp_ready(role_r), .resp_done(role_dn));

    fe_ability_time #(.CLK_FREQ(100000000)) time0(
        .clk(clk100), .rst(rst), .start(atom_time_start),
        .act(atom_act), .args(atom_args),
        .resp_start(time_rs), .resp_ok(time_ok), .resp_valid(time_v),
        .resp_data(time_d), .resp_ready(time_r), .resp_done(time_dn));

    fe_ability_onekey onekey0(
        .clk(clk100), .rst(rst), .start(atom_onekey_start),
        .act(atom_act), .args(atom_args),
        .resp_start(onekey_rs), .resp_ok(onekey_ok), .resp_valid(onekey_v),
        .resp_data(onekey_d), .resp_ready(onekey_r), .resp_done(onekey_dn));

    fe_ability_modbus #(.CLK_FREQ(100000000), .BAUD(115200)) modbus0(
        .clk(clk100), .rst(rst), .start(atom_modbus_start),
        .act(atom_act), .args(atom_args),
        .resp_start(modbus_rs), .resp_ok(modbus_ok), .resp_valid(modbus_v),
        .resp_data(modbus_d), .resp_ready(modbus_r), .resp_done(modbus_dn),
        .mb_rx(uart1_rx), .mb_tx(uart1_tx));

    assign led = {1'b0, hb[23], led_rx, led_busy};
endmodule
