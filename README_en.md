<div align="center">
<img src="https://avatars.githubusercontent.com/u/245985800?s=200&v=4" style="width:100px;" width="100"/>
<h2>FasterEdge FPGA - Artix-7 XC7A35T</h2>
<h3>FasterEdge framework on Artix-7 FPGA (Vivado RTL)</h3>
</div>

### 1. Introduction

This repo implements the **[FasterEdge](https://github.com/FasterEdge/FasterEdge)** framework in pure RTL (Verilog) on a **Xilinx Artix-7 (XC7A35T)** FPGA. The capability subset (Base/Role/Time/OneKey/Reg/Modbus/HMAC-SHA256 etc) is built directly in logic gates and driven over UART, showing that "a tree" can be grown from logic as well.

- ✅ Pure Verilog RTL, Vivado synthesis & implementation (xc7a35tcsg324-1)
- ✅ UART 8N1 serial command path (uart_rx / uart_tx)
- ✅ HMAC-SHA256 hardware module (fe_sha256_block / fe_hmac_sha256)
- ✅ Same names & commands as the main repo
- ✅ Self-checking testbenches (tb_fe_top.sv / tb_fe_hmac.v)

### 2. Implemented Capabilities (RTL subset)

| Module | Type | Description |
|--------|------|-------------|
| `fe_atom` | Framework | Atom container: Data/Ability registry & routing |
| `fe_ability_base` | Base | `list_data_names` / `list_ability_names` |
| `fe_ability_role` | Role | `describe` / `set_role` / `get_role` |
| `fe_ability_time` | Time | `sync_manual` / `get_time` (no NTP) |
| `fe_ability_onekey` | Token | `issue_token` / `verify_token` / `list_tokens` (HMAC-SHA256) |
| `fe_ability_modbus` | Modbus | `set_unit_id` / `read_holding` / `write_holding` (RTU slave) |
| `fe_data_base` | Meta | `logo` / `info` |
| `fe_data_config` | Config | `get` / `set` / `delete` / `list` |
| `fe_bin2dec` | Utility | binary→decimal conversion (response encoding) |

### 3. Directory Layout

```
FPGA-Artix7-XC7A35T/
├── vivado/
│   ├── rtl/          # all RTL sources (fe_*.v / uart_*.v)
│   ├── sim/          # testbenches (tb_fe_top.sv / tb_fe_hmac.v)
│   ├── scripts/      # project Tcl scripts
│   └── xdc/          # constraints
├── LICENSE           # Apache-2.0
└── README.md
```

### 4. Usage

1. **Vivado** (2021.x+): open project (or run `scripts/create_project.tcl`), device **xc7a35tcsg324-1**
2. Add `vivado/rtl/*.v` as design sources, `vivado/sim/*.sv` as simulation sources
3. Synthesize → Implement → Generate bitstream, download to the board
4. Serial 115200-8N1, send commands (identical to the MCU editions):

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

### 5. Version

- **1.0.20260829** (in sync with all FasterEdge MCU platform versions)

### 6. Sibling Projects

- **[FasterEdge FPGA - Zynq-7020 (ALINX)](https://github.com/FasterEdge/FPGA-Zynq-7020-ALINX)**: MicroBlaze soft core + HLS acceleration
- **[FasterEdge](https://github.com/FasterEdge/FasterEdge)**: framework main repo
