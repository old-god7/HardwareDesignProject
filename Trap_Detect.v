`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2025/01/22
// Module Name: Trap_Detect
// Description: 自陷检测模块 - SYSCALL/BREAK指令检测
//
//////////////////////////////////////////////////////////////////////////////////

// verilator lint_off UNUSEDSIGNAL
module Trap_Detect (
    input  [31:0] instr,        // 当前指令
    output       is_syscall,    // SYSCALL检测信号
    output       is_break,      // BREAK检测信号
    output [5:0] trap_type      // 异常类型编码
);

    // verilator lint_off UNUSEDSIGNAL
    // SYSCALL: opcode=0, funct=0b001100 (十进制12)
    assign is_syscall = (instr[31:26] == 6'b000000) &&
                        (instr[5:0] == 6'b001100);

    // BREAK: opcode=0, funct=0b001101 (十进制13)
    assign is_break = (instr[31:26] == 6'b000000) &&
                      (instr[5:0] == 6'b001101);
    // verilator lint_on UNUSEDSIGNAL

    // 异常类型编码 (MIPS标准)
    // 8: Sys (系统调用异常)
    // 9: Bp (断点异常)
    assign trap_type = is_syscall ? 6'd8 :
                       is_break  ? 6'd9 :
                                   6'd0;  // 无异常

endmodule
