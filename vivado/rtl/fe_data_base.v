`timescale 1ns/1ps
// fe_data_base.v — BaseData：logo / info
module fe_data_base(
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
    reg [1023:0] s0, s1, s2;
    reg [7:0]    l0, l1, l2;
    reg [1:0]    ns;

    // 与 MCU 版 data_base.c 相同的 ASCII logo（96 字节）
    localparam [8*96-1:0] LOGO =
        "  __ _        _\n / _| |_ _  _(_)__ _\n|  _|  _| || | / _` |\n|_|  \\__|\\_, |_\\__,_|\n        |__/\n";

    always @(posedge clk) begin
        if (rst) begin
            resp_start <= 0; resp_ok <= 0; s0 <= 0; s1 <= 0; s2 <= 0;
            l0 <= 0; l1 <= 0; l2 <= 0; ns <= 0;
        end else begin
            resp_start <= 1'b0;
            if (start) begin
                resp_start <= 1'b1;
                if (act == "logo") begin
                    resp_ok <= 1'b1;
                    s0 <= LOGO; l0 <= 94;
                    ns <= 2'd1;
                end else if (act == "info") begin
                    resp_ok <= 1'b1;
                    s0 <= "{\"name\":\"BaseData\",\"firmware\":\"FasterEdge-FPGA 1.0.20260829\",\"chip\":\"XC7A35T\",\"sdk\":\"Vivado RTL\"}"; l0 <= 97;
                    ns <= 2'd1;
                end else begin
                    resp_ok <= 1'b0;
                    s0 <= "unsupported command"; l0 <= 19;
                    ns <= 2'd1;
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
