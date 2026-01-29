`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/11/22 10:23:13
// Design Name: 
// Module Name: hazard
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hazard(
    //fetch stage
    output wire stallF,
    //decode stage
    input wire[4:0] rsD, rtD,
    input wire branchD,
    input wire jumpregD,
    input wire cp0writeD,
    output wire forwardaD, forwardbD,
    output wire stallD,
    //execute stage
    input wire[4:0] rsE, rtE,
    input wire[4:0] writeregE,
    input wire regwriteE,
    input wire memtoregE,
    input wire divE,
    input wire divbusyE,
    output reg[1:0] forwardaE, forwardbE,
    output wire flushE,
    //mem stage
    input wire[4:0] writeregM,
    input wire regwriteM,
    input wire memtoregM,
    //write back stage
    input wire[4:0] writeregW,
    input wire regwriteW
);

	wire lwstallD, branchstallD, divstallD;
	wire cp0stallD;

    // --- Decode 阶段前推 (用于 Branch/JR 提前判断) ---
    assign forwardaD = (rsD != 0 & rsD == writeregM & regwriteM);
    assign forwardbD = (rtD != 0 & rtD == writeregM & regwriteM);
    
    // --- Execute 阶段前推 (ALU 数据流) ---
    always @(*) begin
        forwardaE = 2'b00;
        forwardbE = 2'b00;
        if(rsE != 0) begin
            if(rsE == writeregM & regwriteM)      forwardaE = 2'b10;
            else if(rsE == writeregW & regwriteW) forwardaE = 2'b01;
        end
        if(rtE != 0) begin
            if(rtE == writeregM & regwriteM)      forwardbE = 2'b10;
            else if(rtE == writeregW & regwriteW) forwardbE = 2'b01;
        end
    end

    // --- 停顿逻辑 ---

    // 1. Load-Use 冲突
    assign lwstallD = memtoregE & (rtE == rsD | rtE == rtD);

	// 2. 分支/跳转寄存器冲突
    // 如果 D 级是分支或 JR/JALR，且前面的指令（E 级或 M 级的 Load）会修改所需的寄存器
    assign branchstallD = (branchD | jumpregD) & 
                        ((regwriteE & (writeregE == rsD | writeregE == rtD)) |
                         (memtoregM & (writeregM == rsD | writeregM == rtD)));

	// 2b. CP0 写（MTC0）数据相关：MTC0 在 D 级读取 rtD 作为写入 CP0 的数据。
	// - E 级 ALU 结果无法前推到 D 级 -> 需要停顿 1 拍
	// - M 级 load 数据无法前推到 D 级 -> 需要停顿 1 拍
	assign cp0stallD = cp0writeD &
	                  ((regwriteE & (writeregE == rtD)) |
	                   (memtoregM & (writeregM == rtD)));

    // 3. 除法器忙停顿
    assign divstallD = divE | divbusyE;

    // --- 控制信号汇总 ---
    
	// 只要有任何冲突需要停顿，就固定住 F 和 D 级
	assign stallD = lwstallD | branchstallD | cp0stallD | divstallD;
    assign stallF = stallD;

    // --- 【关键修改点】 ---
    // 在支持延迟槽的机器中，flushE 仅在发生 Stall 时触发，用于在 EX 级插入气泡（NOP）。
    // 正常跳转时，stallD 为 0，因此 flushE 为 0，延迟槽指令（下一条指令）得以进入 EX 级执行。
    // 如果 stallD 为 1，说明下一条指令暂时不能进 EX，所以冲刷 EX 级。
    assign flushE = stallD;

endmodule
