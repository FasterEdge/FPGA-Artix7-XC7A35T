// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// fe_ability_base.v — BaseAbility：list_data_names / list_ability_names
module fe_ability_base(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [255:0] act,
    output reg         resp_start,
    output reg         resp_ok,
    output reg         resp_valid,
    output reg  [7:0]  resp_data,
    input  wire        resp_ready,
    output reg         resp_done
);
`include "fe_registry.vh"

    wire is_list_ab   = (act == "list_ability_names");
    wire is_list_data = (act == "list_data_names");

    // 段寄存器：成功 = {"names":[ + 列表 + ]}；失败 = 错误文本
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;

    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0;
        end else begin
            resp_start <= 1'b0;
            if (start) begin
                resp_start <= 1'b1;
                if (is_list_ab) begin
                    resp_ok <= 1'b1;
                    s0 <= "{\"names\":["; l0 <= 10;
                    s1 <= LIST_ABILITIES;        l1 <= LIST_AB_LEN[7:0];
                    s2 <= "]}";             l2 <= 2;
                    ns  <= 2'd3;
                end else if (is_list_data) begin
                    resp_ok <= 1'b1;
                    s0 <= "{\"names\":["; l0 <= 10;
                    s1 <= LIST_DATAS;            l1 <= LIST_DATA_LEN[7:0];
                    s2 <= "]}";             l2 <= 2;
                    ns  <= 2'd3;
                end else begin
                    resp_ok <= 1'b0;
                    s0 <= "unsupported command"; l0 <= 19;
                    ns  <= 2'd1;
                end
            end
        end
    end

    fe_resp emit(
        .clk(clk), .rst(rst), .start(resp_start), .nsegs(ns),
        .s0dat(s0), .s0len(l0), .s1dat(s1), .s1len(l1), .s2dat(s2), .s2len(l2),
        .resp_valid(resp_valid), .resp_data(resp_data),
        .resp_ready(resp_ready), .resp_done(resp_done)
    );
endmodule
