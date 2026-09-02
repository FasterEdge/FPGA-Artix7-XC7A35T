// FasterEdge 开源项目 - Github: https://github.com/FasterEdge - Gitee: https://gitee.com/FasterEdge
`timescale 1ns/1ps
// fe_hmac_sha256.v — HMAC-SHA256（硬件版）
// 流程：ipad 块压缩 → 消息块压缩 → opad 块压缩 → 摘要块压缩，共 4 块。
// secret 32B（LSB 在前：secret[7:0] = 第 0 字节）；消息 ≤ 55 字节（单块）。
// mac 输出 LSB 在前（mac[7:0] = 摘要第 0 字节）。
module fe_hmac_sha256(
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [255:0] secret,
    input  wire [5:0]   msg_len,
    input  wire [439:0] msg,
    output reg          done,
    output reg  [255:0] mac
);
    localparam [255:0] H0 = 256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;

    localparam S_IDLE = 3'd0, S_B1 = 3'd1, S_B2 = 3'd2, S_B3 = 3'd3, S_B4 = 3'd4, S_OUT = 3'd5;

    reg [2:0] state;
    reg [255:0] sha_init, s1, s2, s3, s4;
    reg [511:0] sha_block;
    reg         sha_start;
    wire        sha_done, sha_busy;
    wire [255:0] sha_state;
    reg  [255:0] sha_state_q;

    fe_sha256_block sha (
        .clk(clk), .rst(rst),
        .start(sha_start),
        .init_state(sha_init),
        .block_in(sha_block),
        .busy(sha_busy),
        .done(sha_done),
        .state_out(sha_state)
    );

    // ---- ipad / opad 块（64B：前 32B = secret^pad，后 32B = pad） ----
    reg [511:0] ipad_block, opad_block;
    integer bi;
    always @* begin
        for (bi = 0; bi < 64; bi = bi + 1) begin
            ipad_block[511-bi*8 -: 8] = (bi < 32) ? (secret[bi*8 +: 8] ^ 8'h36) : 8'h36;
            opad_block[511-bi*8 -: 8] = (bi < 32) ? (secret[bi*8 +: 8] ^ 8'h5c) : 8'h5c;
        end
    end

    // ---- 消息块：msg || 0x80 || 0... || 位长((64+len)*8, 16bit) ----
    reg [511:0] msg_block;
    wire [15:0] msg_bitlen = 16'd512 + {10'b0, msg_len, 3'b000};
    always @* begin
        for (bi = 0; bi < 64; bi = bi + 1) begin
            if (bi < msg_len)
                msg_block[511-bi*8 -: 8] = msg[bi*8 +: 8];
            else if (bi == msg_len)
                msg_block[511-bi*8 -: 8] = 8'h80;
            else
                msg_block[511-bi*8 -: 8] = 8'h00;
        end
        msg_block[15:8] = msg_bitlen[15:8];
        msg_block[7:0]  = msg_bitlen[7:0];
    end

    // ---- 摘要块：inner(32B) || 0x80 || 0... || 位长(768) ----
    reg [511:0] dig_block;
    always @* begin
        for (bi = 0; bi < 64; bi = bi + 1) begin
            if (bi < 32)
                dig_block[511-bi*8 -: 8] = s2[255-bi*8 -: 8];
            else if (bi == 32)
                dig_block[511-bi*8 -: 8] = 8'h80;
            else
                dig_block[511-bi*8 -: 8] = 8'h00;
        end
        dig_block[15:8] = 8'h03;   // 768 = 0x0300
        dig_block[7:0]  = 8'h00;
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0; sha_start <= 1'b0;
            mac <= 0; s1 <= 0; s2 <= 0; s3 <= 0; s4 <= 0;
            sha_init <= 0; sha_block <= 0; sha_state_q <= 0;
        end else begin
            done <= 1'b0;
            sha_start <= 1'b0;
            case (state)
                S_IDLE: if (start) begin
                    sha_init  <= H0;
                    sha_block <= ipad_block;
                    sha_start <= 1'b1;
                    state     <= S_B1;
                end
                S_B1: if (sha_done) begin
                    s1 <= sha_state;
                    sha_init  <= sha_state;
                    sha_block <= msg_block;
                    sha_start <= 1'b1;
                    state     <= S_B2;
                end
                S_B2: if (sha_done) begin
                    s2 <= sha_state;
                    sha_init  <= H0;
                    sha_block <= opad_block;
                    sha_start <= 1'b1;
                    state     <= S_B3;
                end
                S_B3: if (sha_done) begin
                    s3 <= sha_state;
                    sha_init  <= sha_state;
                    sha_block <= dig_block;
                    sha_start <= 1'b1;
                    state     <= S_B4;
                end
                S_B4: if (sha_done) begin
                    s4 <= sha_state;
                    state <= S_OUT;
                end
                S_OUT: begin
                    for (bi = 0; bi < 32; bi = bi + 1)
                        mac[bi*8 +: 8] = s4[255-bi*8 -: 8];
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
