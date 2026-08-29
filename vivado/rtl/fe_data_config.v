`timescale 1ns/1ps
// fe_data_config.v — ConfigData：扁平点号路径 KV 配置（get/set/delete/list/snapshot）
// 8 个槽位：key 16B（'.'/'/' 归一为 '_'，同 MCU norm_key）+ value 32B。
// 与 MCU 版一致：get 未命中返回空值；list/snapshot 返回空表。
module fe_data_config(
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
    output reg         resp_done
);
    localparam integer NSLOTS = 8;

    reg [127:0] keymem  [0:NSLOTS-1];   // LSB-first
    reg [255:0] valmem  [0:NSLOTS-1];
    reg [NSLOTS-1:0] valid;

    // 段寄存器
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;

    wire is_get    = (act == "get");
    wire is_set    = (act == "set");
    wire is_delete = (act == "delete");
    wire is_list   = (act == "list");
    wire is_snap   = (act == "snapshot");

    // args 长度：最后一个非零字节的下标 +1
    reg [6:0] alen;
    integer i;
    always @* begin
        alen = 0;
        for (i = 0; i < 64; i = i + 1)
            if (args[i*8 +: 8] != 8'h00) alen = i + 1;
    end

    // '=' 位置（第一个）
    reg [6:0] eqpos;
    reg       has_eq;
    always @* begin
        has_eq = 0; eqpos = 0;
        for (i = 0; i < 64; i = i + 1)
            if (!has_eq && args[i*8 +: 8] == 8'h3D) begin
                has_eq = 1; eqpos = i;
            end
    end

    // 归一化键（set 取 '=' 前，get/delete 取全部 args；'.'/'/' → '_'）
    reg [127:0] keyq;
    reg [4:0]   keyqlen;
    always @* begin
        keyq = 0; keyqlen = 0;
        for (i = 0; i < 16; i = i + 1) begin
            if (is_set) begin
                if (i < eqpos) begin
                    keyq[i*8 +: 8] =
                        (args[i*8 +: 8] == 8'h2E || args[i*8 +: 8] == 8'h2F) ?
                        8'h5F : args[i*8 +: 8];
                    keyqlen = i[4:0] + 5'd1;
                end
            end else begin
                if (i < alen) begin
                    keyq[i*8 +: 8] =
                        (args[i*8 +: 8] == 8'h2E || args[i*8 +: 8] == 8'h2F) ?
                        8'h5F : args[i*8 +: 8];
                    keyqlen = i[4:0] + 5'd1;
                end
            end
        end
    end

    // 槽位匹配 / 空槽
    reg [2:0] hit_slot, free_slot;
    reg       has_hit, has_free;
    always @* begin
        has_hit = 0; has_free = 0; hit_slot = 0; free_slot = 0;
        for (i = NSLOTS-1; i >= 0; i = i - 1)
            if (!valid[i]) begin has_free = 1; free_slot = i[2:0]; end
        for (i = NSLOTS-1; i >= 0; i = i - 1)
            if (valid[i] && keymem[i] == keyq) begin has_hit = 1; hit_slot = i[2:0]; end
    end

    // get 响应缓冲：{"key":"val"}（未命中 val 为空，同 MCU 版）
    reg [1023:0] getbuf;
    reg [7:0]    getlen;
    reg [7:0]    gp;
    always @* begin
        getbuf = 0; gp = 0;
        getbuf[gp*8 +: 8] = 8'h7B; gp = gp + 1;                  // '{'
        getbuf[gp*8 +: 8] = 8'h22; gp = gp + 1;                  // '"'
        for (i = 0; i < 16; i = i + 1) begin
            if (i < keyqlen) begin
                getbuf[gp*8 +: 8] = keyq[i*8 +: 8]; gp = gp + 1;
            end
        end
        getbuf[gp*8 +: 8] = 8'h22; gp = gp + 1;                  // '"'
        getbuf[gp*8 +: 8] = 8'h3A; gp = gp + 1;                  // ':'
        getbuf[gp*8 +: 8] = 8'h22; gp = gp + 1;                  // '"'
        if (has_hit) begin
            for (i = 0; i < 32; i = i + 1) begin
                if (valmem[hit_slot][i*8 +: 8] != 8'h00) begin
                    getbuf[gp*8 +: 8] = valmem[hit_slot][i*8 +: 8]; gp = gp + 1;
                end
            end
        end
        getbuf[gp*8 +: 8] = 8'h22; gp = gp + 1;                  // '"'
        getbuf[gp*8 +: 8] = 8'h7D; gp = gp + 1;                  // '}'
        getlen = gp;
    end

    reg [2:0] state;
    localparam S_IDLE = 0, S_WR = 1;

    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0; state <= S_IDLE;
            valid <= 0;
            for (i = 0; i < NSLOTS; i = i + 1) begin
                keymem[i] <= 0; valmem[i] <= 0;
            end
        end else begin
            resp_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        if (is_list) begin
                            resp_ok <= 1'b1; s0 <= "{\"keys\":[]}"; l0 <= 11; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end else if (is_snap) begin
                            resp_ok <= 1'b1; s0 <= "{\"snapshot\":{}}"; l0 <= 15; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end else if (is_get) begin
                            resp_ok <= 1'b1;
                            // getbuf 是 LSB-first，s0 需右对齐，故反转装入
                            for (i = 0; i < 128; i = i + 1)
                                if (i < getlen) s0[(getlen-1-i)*8 +: 8] = getbuf[i*8 +: 8];
                            l0 <= getlen; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end else if (is_set) begin
                            if (!has_eq) begin
                                resp_ok <= 1'b0;
                                s0 <= "bad format, expect key=value"; l0 <= 27; ns <= 2'd1;
                                resp_start <= 1'b1;
                            end else begin
                                state <= S_WR;   // 写完后才启动响应
                            end
                        end else if (is_delete) begin
                            if (has_hit) begin
                                valid[hit_slot]  <= 1'b0;
                                keymem[hit_slot] <= 0;
                                valmem[hit_slot] <= 0;
                            end
                            resp_ok <= 1'b1; s0 <= "deleted"; l0 <= 7; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end else begin
                            resp_ok <= 1'b0;
                            s0 <= "unsupported command"; l0 <= 19; ns <= 2'd1;
                            resp_start <= 1'b1;
                        end
                    end
                end
                S_WR: begin
                    // 写槽位：命中槽优先，否则空槽；值 ≤ 32B
                    if (has_hit || has_free) begin
                        if (has_hit) begin
                            keymem[hit_slot] <= keyq;
                            for (i = 0; i < 32; i = i + 1)
                                if (eqpos + 1 + i < 64)
                                    valmem[hit_slot][i*8 +: 8] <= args[(eqpos+1+i)*8 +: 8];
                        end else begin
                            keymem[free_slot] <= keyq;
                            for (i = 0; i < 32; i = i + 1)
                                if (eqpos + 1 + i < 64)
                                    valmem[free_slot][i*8 +: 8] <= args[(eqpos+1+i)*8 +: 8];
                            valid[free_slot] <= 1'b1;
                        end
                        resp_ok <= 1'b1; s0 <= "saved"; l0 <= 5; ns <= 2'd1;
                    end else begin
                        resp_ok <= 1'b0; s0 <= "no free slot"; l0 <= 12; ns <= 2'd1;
                    end
                    resp_start <= 1'b1;
                    state      <= S_IDLE;
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
endmodule
