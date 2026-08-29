`timescale 1ns/1ps
// fe_ability_role.v — RoleAbility：describe / set_role / get_role
module fe_ability_role(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [255:0] act,
    input  wire [511:0] args,          // LSB-first
    output reg         resp_start,
    output reg         resp_ok,
    output reg         resp_valid,
    output reg  [7:0]  resp_data,
    input  wire        resp_ready,
    output reg         resp_done
);
    // 角色寄存器（LSB-first，0 填充；上电为空，同 MCU 版语义）
    reg [127:0] role;
    reg [7:0]   role_len;

    // 段寄存器
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;
    reg [2:0]    state;

    // role 是否等于某个合法值（LSB-first 比较）
    function role_is(input [127:0] want, input integer wlen);
        integer i;
        begin
            role_is = 1'b1;
            for (i = 0; i < 16; i = i + 1) begin
                if (i < wlen) begin
                    if (role[(wlen-1-i)*8 +: 8] !== want[(wlen-1-i)*8 +: 8]) role_is = 1'b0;
                end else if (role[i*8 +: 8] !== 8'h00) role_is = 1'b0;
            end
            if (role_len != wlen[7:0]) role_is = 1'b0;
        end
    endfunction

    // args 长度（≤16）：最后一个非零字节的下标 +1
    reg [4:0] alen;
    integer i;
    always @* begin
        alen = 0;
        for (i = 0; i < 16; i = i + 1)
            if (args[i*8 +: 8] != 8'h00) alen = i + 1;
    end

    // args（LSB-first）与右对齐字面量比较
    function arg_is(input [127:0] want, input integer wlen);
        integer j;
        begin
            arg_is = 1'b1;
            for (j = 0; j < 16; j = j + 1) begin
                if (j < wlen) begin
                    if (args[j*8 +: 8] !== want[(wlen-1-j)*8 +: 8]) arg_is = 1'b0;
                end else if (args[j*8 +: 8] !== 8'h00) arg_is = 1'b0;
            end
            if (alen != wlen[4:0]) arg_is = 1'b0;
        end
    endfunction

    // 取 args 前 n 字节并右对齐（LSB-first → 右对齐字符串）
    function [127:0] revargs(input [511:0] a, input [4:0] n);
        integer k;
        begin
            revargs = 0;
            for (k = 0; k < 16; k = k + 1)
                if (k < n) revargs[(n-1-k)*8 +: 8] = a[k*8 +: 8];
        end
    endfunction

    wire valid_role = role_is("edge", 4) | role_is("cloud", 5) | role_is("standalone", 10);
    wire is_describe = (act == "describe");
    wire is_set      = (act == "set_role");
    wire is_get      = (act == "get_role");

    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0; state <= 0;
            role <= 0; role_len <= 0;
        end else begin
            resp_start <= 1'b0;
            case (state)
                3'd0: begin
                    if (start) begin
                        resp_start <= 1'b1;
                        if (is_describe) begin
                            resp_ok <= 1'b1;
                            s0 <= "{\"name\":\"RoleAbility\",\"role\":\""; l0 <= 31;
                            s1 <= {384'h0, role}; l1 <= role_len;
                            s2 <= "\"}"; l2 <= 2;
                            ns <= 2'd3; state <= 3'd0;
                        end else if (is_get) begin
                            resp_ok <= 1'b1;
                            s0 <= "role="; l0 <= 5;
                            s1 <= {384'h0, role}; l1 <= role_len;
                            ns <= 2'd2; state <= 3'd0;
                        end else if (is_set) begin
                            if (alen == 0) begin
                                resp_ok <= 1'b0;
                                s0 <= "missing role"; l0 <= 12;
                                ns <= 2'd1;
                            end else if (arg_is("edge", 4)) begin
                                role <= revargs(args, 4); role_len <= 4;
                                resp_ok <= 1'b1;
                                s0 <= "role=edge"; l0 <= 9;
                                ns <= 2'd1;
                            end else if (arg_is("cloud", 5)) begin
                                role <= revargs(args, 5); role_len <= 5;
                                resp_ok <= 1'b1;
                                s0 <= "role=cloud"; l0 <= 10;
                                ns <= 2'd1;
                            end else if (arg_is("standalone", 10)) begin
                                role <= revargs(args, 10); role_len <= 10;
                                resp_ok <= 1'b1;
                                s0 <= "role=standalone"; l0 <= 15;
                                ns <= 2'd1;
                            end else begin
                                resp_ok <= 1'b0;
                                s0 <= "invalid role"; l0 <= 12;
                                ns <= 2'd1;
                            end
                            state <= 3'd0;
                        end else begin
                            resp_ok <= 1'b0;
                            s0 <= "unsupported command"; l0 <= 19;
                            ns <= 2'd1; state <= 3'd0;
                        end
                    end
                end
                default: state <= 3'd0;
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
