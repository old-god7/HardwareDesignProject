`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/11/07 10:58:03
// Design Name: 
// Module Name: mips
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


module mips(
    input wire clk, rst,
    // --- 指令/程序计数器 ---
    output wire[31:0] pcF,
    input wire[31:0] instrF,
    // --- 存储器接口 ---
    output wire memwriteM,
    output wire memtoregM,
    output wire[31:0] aluoutM, writedataM,
    output wire[2:0] mem_opM,       // 保留第一个模块的内存操作位
    input wire[31:0] readdataM,
    // --- Debug (WB stage) ---
    output wire[31:0] debug_wb_pc,
    output wire[3:0]  debug_wb_rf_wen,
    output wire[4:0]  debug_wb_rf_wnum,
    output wire[31:0] debug_wb_rf_wdata
);

    // --- Decode Stage 信号 ---
    wire [5:0] opD, functD;
    wire [4:0] rtD;
    wire pcsrcD, branchD, jumpD, jumpregD, equalD;
    wire [2:0] branch_opD;

    // --- Execute Stage 信号 ---
    wire regdstE, alusrcE, memtoregE, regwriteE;
    wire [2:0] alucontrolE;
    wire hassignE, isluiE, divE;    // 保留第一个模块的特性
    wire [1:0] hilo_enE, hilo_mfE, shiftE;
    wire flushE;
    wire linkE, jalrE;              // 融合新增跳转信号

	    // --- Memory Stage 信号 ---
	    wire regwriteM;
	    wire linkM, jalrM;              // 融合新增跳转信号

	    // --- Write Back Stage 信号 ---
	    wire memtoregW, regwriteW;
	    wire linkW, jalrW;              // 融合新增跳转信号

	    // --- Exception commit (from datapath, MEM stage) ---
	    wire exc_commitM;
	    wire squashM;

	    // Raw memwrite from controller (must be visible to datapath for AdES detect)
	    wire memwriteM_raw;
	    wire memtoregM_raw;

	    // --- 1. 实例化融合后的 Controller ---
	    controller2 c(
	        .clk(clk), .rst(rst),
        // Decode stage
        .opD(opD), .functD(functD), .rtD(rtD),
        .pcsrcD(pcsrcD), .branchD(branchD), .equalD(equalD), .jumpD(jumpD), .jumpregD(jumpregD),
        .branch_opD(branch_opD),
        
        // Execute stage
        .flushE(flushE),
        .memtoregE(memtoregE), .alusrcE(alusrcE),
        .regdstE(regdstE), .regwriteE(regwriteE),  
        .alucontrolE(alucontrolE),
        .hassignE(hassignE), .isluiE(isluiE), .divE(divE),
        .hilo_enE(hilo_enE), .hilo_mfE(hilo_mfE), .shiftE(shiftE),
	        .linkE(linkE), .jalrE(jalrE),

		        // Mem stage
		        .memtoregM(memtoregM_raw), .memwriteM(memwriteM_raw),
		        .regwriteM(regwriteM), .mem_opM(mem_opM),
		        .linkM(linkM), .jalrM(jalrM),

	        // Write back stage
        .memtoregW(memtoregW), .regwriteW(regwriteW),
        .linkW(linkW), .jalrW(jalrW)
    );

    // --- 2. 实例化更新后的 Datapath ---
	    datapath dp(
	        .clk(clk), .rst(rst),
        // Fetch stage
        .pcF(pcF),
        .instrF(instrF),

        // Decode stage
        .pcsrcD(pcsrcD), .branchD(branchD), .branch_opD(branch_opD),
        .jumpD(jumpD), .jumpregD(jumpregD),
        .equalD(equalD),
        .opD(opD), .functD(functD), .rtD(rtD),

        // Execute stage
        .memtoregE(memtoregE), .alusrcE(alusrcE), .regdstE(regdstE),
        .regwriteE(regwriteE),
        .alucontrolE(alucontrolE),
        .hassignE(hassignE), .isluiE(isluiE), .divE(divE),
        .hilo_enE(hilo_enE), .hilo_mfE(hilo_mfE), .shiftE(shiftE),
        .flushE(flushE),
        .linkE(linkE), .jalrE(jalrE),

		        // Mem stage
		        .memtoregM(memtoregM_raw), .memwriteM(memwriteM_raw), .regwriteM(regwriteM),
		        .linkM(linkM), .jalrM(jalrM),
		        .mem_opM(mem_opM),
		        .aluoutM(aluoutM), .writedataM(writedataM),
		        .readdataM(readdataM),

        // Writeback stage
        .memtoregW(memtoregW), .regwriteW(regwriteW),
        .linkW(linkW), .jalrW(jalrW),
        // debug
        .debug_wb_pc(debug_wb_pc),
		        .debug_wb_rf_wen(debug_wb_rf_wen),
		        .debug_wb_rf_wnum(debug_wb_rf_wnum),
		        .debug_wb_rf_wdata(debug_wb_rf_wdata),
		        .exc_commitM(exc_commitM),
		        .squashM(squashM)
		    );

		    // Gate memory access when:
		    // - current MEM stage instruction commits an exception (AdES, etc.)
		    // - the MEM stage instruction is the younger one that must be squashed after exception/eret
		    assign memtoregM = memtoregM_raw & ~exc_commitM & ~squashM;
		    assign memwriteM = memwriteM_raw & ~exc_commitM & ~squashM;

endmodule
