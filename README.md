<div align="center">
<img src="https://avatars.githubusercontent.com/u/245985800?s=200&v=4" style="width:100px;" width="100"/>
<h2>FasterEdge FPGA - Artix-7 XC7A35T</h2>
<h3>FasterEdge 框架的 Artix-7 FPGA（Vivado RTL）平台实现</h3>
</div>

### 一、简介

本项目是 **[FasterEdge](https://github.com/FasterEdge/FasterEdge)** 框架在 **Xilinx Artix-7（XC7A35T）** FPGA 上的纯 RTL 实现（Verilog）。以**硬件逻辑**实现 FasterEdge 的能力子集（Base/Role/Time/OneKey/Reg/Modbus/HMAC-SHA256 等），通过 UART 与上位机交互，展示"一棵树"也可以由逻辑门直接长成。

- ✅ 纯 Verilog RTL，Vivado 综合实现（xc7a35tcsg324-1）
- ✅ UART 8N1 串口命令通路（uart_rx / uart_tx）
- ✅ HMAC-SHA256 硬件模块（fe_sha256_block / fe_hmac_sha256）
- ✅ 与主仓库**同名同命令**，云边协同对等编程
- ✅ 自校验 testbench（tb_fe_top.sv / tb_fe_hmac.v）

### 二、已实现能力（RTL 子集）

| 模块 | 类别 | 说明 |
|------|------|------|
| `fe_atom` | 框架 | Atom 容器：Data/Ability 注册表与路由 |
| `fe_ability_base` | 基础 | `list_data_names` / `list_ability_names` |
| `fe_ability_role` | 角色 | `describe` / `set_role` / `get_role` |
| `fe_ability_time` | 时间 | `sync_manual` / `get_time`（无 NTP）|
| `fe_ability_onekey` | 令牌 | `issue_token` / `verify_token` / `list_tokens`（HMAC-SHA256）|
| `fe_ability_modbus` | Modbus | `set_unit_id` / `read_holding` / `write_holding`（RTU 从站）|
| `fe_data_base` | 元信息 | `logo` / `info` |
| `fe_data_config` | 配置 | `get` / `set` / `delete` / `list` |
| `fe_bin2dec` | 工具 | 二进制→十进制转换（响应编码）|

### 三、目录结构

```
FPGA-Artix7-XC7A35T/
├── vivado/
│   ├── rtl/          # 全部 RTL 源码（fe_*.v / uart_*.v）
│   ├── sim/          # testbench（tb_fe_top.sv / tb_fe_hmac.v）
│   ├── scripts/      # 建工程 Tcl 脚本
│   └── xdc/          # 约束文件
├── LICENSE           # Apache-2.0
└── README.md
```

### 四、使用说明

1. **Vivado**（2021.x+）打开或按 `scripts/create_project.tcl` 建工程，器件选 **xc7a35tcsg324-1**
2. 添加 `vivado/rtl/*.v` 到设计源，`vivado/sim/*.sv` 到仿真源
3. 综合 → 实现 → 生成比特流，下载到开发板
4. 串口 115200-8N1 连接，输入命令（与 MCU 版一致）：

```
help
ability_BaseAbility list_ability_names
ability_RoleAbility set_role edge
ability_TimeAbility sync_manual 1700000000
ability_OneKeyAbility issue_token sensor01
ability_ModbusAbility set_unit_id 3
ability_ModbusAbility write_holding 0,42
data_BaseData info
```

### 五、版本

- **1.0.20260829**（与 FasterEdge MCU 各平台版本同步）

### 六、姊妹项目

- **[FasterEdge FPGA - Zynq-7020 (ALINX)](https://github.com/FasterEdge/FPGA-Zynq-7020-ALINX)**：MicroBlaze 软核 + HLS 加速
- **[FasterEdge](https://github.com/FasterEdge/FasterEdge)**：框架主仓库
