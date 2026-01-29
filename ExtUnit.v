`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ExtUnit
// Description: 立即数扩展单元 - 支持符号扩展和零扩展
//////////////////////////////////////////////////////////////////////////////////

// verilator lint_off UNUSEDSIGNAL
module ExtUnit (
    input  [15:0] imm,        // 16位立即数 <- 指令
    input  [1:0]  ext_type_i, // 扩展类型 <- Control/ID_EX_Reg
    output [31:0] ext_result  // 32位扩展结果 -> datapath
);

    // ExtType编码 (来自2-3对接_1.md):
    // 00: 符号扩展 (默认) - LW, SW, BEQ, ADDI
    // 01: 零扩展 - ANDI, ORI, XORI
    // 10: Load符号扩展 - LB, LH
    // 11: Load零扩展 - LBU, LHU

    // 00和10都是符号扩展，01和11都是零扩展
    wire sign_ext = (ext_type_i == 2'b00) || (ext_type_i == 2'b10);
    wire zero_ext = (ext_type_i == 2'b01) || (ext_type_i == 2'b11);

    assign ext_result = zero_ext ? {16'b0, imm} :
                       {{16{imm[15]}}, imm};

endmodule
