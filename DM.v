`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: DM
// Description: 数据存储器 - 支持字节/半字/字访存
//////////////////////////////////////////////////////////////////////////////////

// verilator lint_off UNUSEDSIGNAL
module DM (
    input         clk,
    input         rst,
    input  [31:0] addr_i,       // 访存地址
    input  [31:0] wdata_i,      // 写入数据
    input         we_i,         // 写使能
    input  [2:0]  mem_op_i,     // 访存操作类型
    output [31:0] rdata_o,      // 读取数据
    output        adel_o,       // 地址错例外（读数据，AdEL）
    output        ades_o        // 地址错例外（写数据，AdES）
);

    // MemOp编码:
    // 000: LW/SW (字)
    // 001: SH (半字存储)
    // 010: SB (字节存储)
    // 100: LH (半字符号扩展)
    // 101: LHU (半字零扩展)
    // 110: LB (字节符号扩展)
    // 111: LBU (字节零扩展)

    // 对齐检查（A03 5.1.5）
    wire is_word_op = (mem_op_i == 3'b000);
    wire is_half_op = (mem_op_i == 3'b001) || (mem_op_i == 3'b100) || (mem_op_i == 3'b101);
    wire is_byte_op = (mem_op_i == 3'b010) || (mem_op_i == 3'b110) || (mem_op_i == 3'b111);

    wire is_store = we_i && (is_word_op || (mem_op_i == 3'b001) || (mem_op_i == 3'b010));
    wire is_load = (~we_i) && (is_word_op || (mem_op_i == 3'b100) || (mem_op_i == 3'b101) || (mem_op_i == 3'b110) || (mem_op_i == 3'b111));

    wire word_misalign = is_word_op && (addr_i[1:0] != 2'b00);
    wire half_misalign = is_half_op && (addr_i[0] != 1'b0);

    assign adel_o = is_load && (word_misalign || half_misalign);
    assign ades_o = is_store && (word_misalign || half_misalign);

    wire [3:0] byte_we;

    // 字节写使能逻辑
    assign byte_we = (mem_op_i == 3'b000) ? 4'b1111 :
                     (mem_op_i == 3'b001 ||
                      mem_op_i == 3'b100 ||
                      mem_op_i == 3'b101) ?
                       (addr_i[1] ? 4'b1100 : 4'b0011) :
                     (mem_op_i == 3'b010 ||
                      mem_op_i == 3'b110 ||
                      mem_op_i == 3'b111) ?
                       (4'b0001 << addr_i[1:0]) :
                     4'b0000;

    // 写数据对齐到目标字节/半字位置
    // - SB: 将 wdata_i[7:0] 放到 addr_i[1:0] 指定的字节位置
    // - SH: 将 wdata_i[15:0] 放到 addr_i[1] 指定的半字位置
    // - SW: 直接写入整字
    wire [31:0] wdata_aligned;
    wire [4:0] byte_shift = {addr_i[1:0], 3'b000};          // 0/8/16/24
    wire [4:0] half_shift = addr_i[1] ? 5'd16 : 5'd0;       // 0/16
    assign wdata_aligned = (mem_op_i == 3'b010) ? ({24'b0, wdata_i[7:0]}  << byte_shift) :
                          (mem_op_i == 3'b001) ? ({16'b0, wdata_i[15:0]} << half_shift) :
                          wdata_i;

    // verilator lint_off MULTIDRIVEN
    reg [31:0] data_mem [0:4095];
    // verilator lint_on MULTIDRIVEN

    wire [31:0] rdata_raw;
    assign rdata_raw = data_mem[addr_i[13:2]];

    always @(posedge clk) begin
        if (we_i && ~ades_o) begin
            if (byte_we[0]) data_mem[addr_i[13:2]][7:0] <= wdata_aligned[7:0];
            if (byte_we[1]) data_mem[addr_i[13:2]][15:8] <= wdata_aligned[15:8];
            if (byte_we[2]) data_mem[addr_i[13:2]][23:16] <= wdata_aligned[23:16];
            if (byte_we[3]) data_mem[addr_i[13:2]][31:24] <= wdata_aligned[31:24];
        end
    end

    // 读数据字节/半字选择逻辑
    wire [7:0] byte_sel;
    assign byte_sel = (addr_i[1:0] == 2'b00) ? rdata_raw[7:0] :
                      (addr_i[1:0] == 2'b01) ? rdata_raw[15:8] :
                      (addr_i[1:0] == 2'b10) ? rdata_raw[23:16] :
                                               rdata_raw[31:24];

    wire [15:0] halfword_sel;
    assign halfword_sel = addr_i[1] ? rdata_raw[31:16] : rdata_raw[15:0];

    reg [31:0] rdata_ext;
    always @(*) begin
        case (mem_op_i)
            3'b000: rdata_ext = rdata_raw;                                    // LW
            3'b110: rdata_ext = {{24{byte_sel[7]}}, byte_sel};                // LB
            3'b111: rdata_ext = {24'b0, byte_sel};                            // LBU
            3'b100: rdata_ext = {{16{halfword_sel[15]}}, halfword_sel};       // LH
            3'b101: rdata_ext = {16'b0, halfword_sel};                        // LHU
            default: rdata_ext = rdata_raw;
        endcase
    end

    integer j;
    initial begin
        for (j = 0; j < 4096; j = j + 1) begin
            data_mem[j] = 32'd0;
        end
    end

    assign rdata_o = rdata_ext;

endmodule
