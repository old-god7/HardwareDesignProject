`timescale 1ns / 1ps

// SRAM-like mycpu_top wrapper intended for the official `soc_sram_func` environment.
// - Storage is provided by the SoC (Block Memory Generator IPs: inst_ram/data_ram).
// - This wrapper only generates correct byte-lane enables and load data extension based on `mem_opM`.
module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    input  wire [5:0]  int_i,

    // inst sram-like interface
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_wen,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    // data sram-like interface
    output wire        data_sram_en,
    output wire [3:0]  data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,

    // debug interface (WB stage)
    output wire [31:0] debug_wb_pc,
    output wire [3 :0] debug_wb_rf_wen,
    output wire [4 :0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
    wire _unused = |int_i;

    // MIPS kseg mapping: for kseg0/kseg1 (0x8000_0000~0xBFFF_FFFF),
    // physical address is {3'b000, vaddr[28:0]}.
    function [31:0] vaddr_to_paddr;
        input [31:0] vaddr;
        begin
            if ((vaddr[31:29] == 3'b100) || (vaddr[31:29] == 3'b101)) begin
                vaddr_to_paddr = {3'b000, vaddr[28:0]};
            end else begin
                vaddr_to_paddr = vaddr;
            end
        end
    endfunction

    // Core clocking: memory IPs are clk-posedge; core samples rdata at ~clk-posedge (half-cycle later).
    wire core_clk = ~clk;
    wire rst      = ~resetn;

    // Core <-> memory signals
    wire        memwriteM;
    wire        memtoregM;
    wire [31:0] pcF;
    wire [31:0] aluoutM;
    wire [31:0] writedataM;
    wire [2:0]  mem_opM;

    // Load data extension (member3)
    // Little-endian byte-lane mapping within a 32-bit word:
    //   addr[1:0]==00 -> [7:0], 01 -> [15:8], 10 -> [23:16], 11 -> [31:24]
    wire [7:0]  load_byte = (aluoutM[1:0] == 2'b00) ? data_sram_rdata[7:0]   :
                            (aluoutM[1:0] == 2'b01) ? data_sram_rdata[15:8]  :
                            (aluoutM[1:0] == 2'b10) ? data_sram_rdata[23:16] :
                                                     data_sram_rdata[31:24];
    wire [15:0] load_half = aluoutM[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];
    reg  [31:0] load_ext;
    always @(*) begin
        case (mem_opM)
            3'b000: load_ext = data_sram_rdata;                         // LW
            3'b110: load_ext = {{24{load_byte[7]}}, load_byte};         // LB
            3'b111: load_ext = {24'b0, load_byte};                      // LBU
            3'b100: load_ext = {{16{load_half[15]}}, load_half};        // LH
            3'b101: load_ext = {16'b0, load_half};                      // LHU
            default: load_ext = data_sram_rdata;
        endcase
    end

    // Store byte-lane enables and write data alignment (member3)
    // Byte-lane mapping matches the load mapping above:
    //   addr[1:0]==00 -> wea[0], 01 -> wea[1], 10 -> wea[2], 11 -> wea[3]
    wire [3:0] store_wen =
        (mem_opM == 3'b000) ? 4'b1111 :                              // SW
        (mem_opM == 3'b001) ? (aluoutM[1] ? 4'b1100 : 4'b0011) :     // SH
        (mem_opM == 3'b010) ? (4'b0001 << aluoutM[1:0]) :            // SB
                              4'b0000;

    // For byte/half stores, replicate the payload and let byte write-enables select lanes.
    wire [31:0] store_wdata =
        (mem_opM == 3'b010) ? {4{writedataM[7:0]}}  :                // SB
        (mem_opM == 3'b001) ? {2{writedataM[15:0]}} :                // SH
                              writedataM;                            // SW

    mips u_core(
        .clk(core_clk),
        .rst(rst),
        .pcF(pcF),
        .instrF(inst_sram_rdata),
        .memwriteM(memwriteM),
        .memtoregM(memtoregM),
        .aluoutM(aluoutM),
        .writedataM(writedataM),
        .mem_opM(mem_opM),
        .readdataM(load_ext),
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata)
    );

    // inst SRAM (read-only)
    assign inst_sram_en    = 1'b1;
    assign inst_sram_wen   = 4'b0000;
    assign inst_sram_addr  = vaddr_to_paddr(pcF);
    assign inst_sram_wdata = 32'b0;

    // data SRAM
    assign data_sram_en    = memtoregM | memwriteM;
    assign data_sram_wen   = memwriteM ? store_wen : 4'b0000;
    assign data_sram_addr  = vaddr_to_paddr(aluoutM);
    assign data_sram_wdata = store_wdata;
endmodule
