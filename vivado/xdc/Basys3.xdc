## FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
## Basys3.xdc — FPGA-Artix7-XC7A35T 板卡约束（Digilent Basys3, xc7a35tcpg236-1）
## 对应 fe_top.v 引脚注释：
##   clk100   = E3   (100MHz 板载时钟)
##   btn_rst  = C12  (CPU_RESETN, 低有效, 高有效复位请在外部取反)
##   uart0_rx = B18  (USB-UART RXD, 控制台 115200-8N1)
##   uart0_tx = A18  (USB-UART TXD)
##   uart1_rx = J17  (Pmod JB pin1, Modbus RTU 从站 RX)
##   uart1_tx = K17  (Pmod JB pin3, Modbus RTU 从站 TX)
##   led[3:0] = R2/T2/U2/V2 (LD0..LD3: [0]=命令处理中 [1]=收发活动 [2]=心跳 [3]=保留)

## 时钟
set_property PACKAGE_PIN E3    [get_ports clk100]
set_property IOSTANDARD LVCMOS33 [get_ports clk100]
create_clock -period 10.000 -name clk100 [get_ports clk100]

## 复位（Basys3 CPU_RESETN，按下为低）
set_property PACKAGE_PIN C12   [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

## 控制台 UART0（USB-UART）
set_property PACKAGE_PIN B18   [get_ports uart0_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_rx]
set_property PACKAGE_PIN A18   [get_ports uart0_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_tx]

## Modbus RTU UART1（Pmod JB）
set_property PACKAGE_PIN J17   [get_ports uart1_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart1_rx]
set_property PACKAGE_PIN K17   [get_ports uart1_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart1_tx]

## LED 状态指示
set_property PACKAGE_PIN R2    [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN T2    [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U2    [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN V2    [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
