# FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
# create_project.tcl — 生成 FPGA-Artix7-XC7A35T Vivado 工程（Basys3 / xc7a35tcpg236-1）
# 用法：
#   cd vivado/scripts
#   vivado -mode batch -source create_project.tcl
#   # 或在 Vivado Tcl Console 中: cd <本目录>; source create_project.tcl
#
# 工程内容：
#   - RTL: rtl/fe_*.v + uart_*.v（纯 PL 逻辑：Atom 指令通路 + Base/Role/Time/
#           OneKey/Modbus/Reg/HMAC-SHA256 能力子集，UART 8N1 与上位机交互）
#   - 顶层: fe_top（100MHz 时钟直入，控制台 UART0 + Modbus RTU UART1 + LED）
#   - SIM : sim/ 目录下的 testbench（tb_fe_top / tb_fe_hmac）
#   - XDC : xdc/Basys3.xdc（Basys3 板卡 pin 与时钟约束）
#
# 注意：README 同时提及 xc7a35tcsg324-1（Arty A7-35T）。fe_top 引脚注释
# 采用 Basys3（cpg236）命名；如需换用 csg324 封装，请按板卡原理图
# 调整 xdc/Basys3.xdc 中的 PACKAGE_PIN。

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ../..]]
set proj_dir   [file join $repo_dir vivado project]

create_project fe_artix7_xc7a35t $proj_dir -part xc7a35tcpg236-1 -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ------------------------------------------------------------
# 添加 RTL
# ------------------------------------------------------------
add_files -fileset sources_1 [file join $repo_dir vivado rtl]
set_property top fe_top [current_fileset]

add_files -fileset sim_1 [file join $repo_dir vivado sim]
# sim 顶层: tb_fe_top（也可单独跑 tb_fe_hmac 验证 HMAC-SHA256 模块）
set_property top tb_fe_top [get_filesets sim_1]

# ------------------------------------------------------------
# 添加约束
# ------------------------------------------------------------
add_files -fileset constrs_1 [file join $repo_dir vivado xdc]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: project created at $proj_dir"
puts "INFO: 顶层 fe_top | 器件 xc7a35tcpg236-1 | 约束 xdc/Basys3.xdc"