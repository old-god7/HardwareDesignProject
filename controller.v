`timescale 1ns / 1ps

// Controller (extended) used by `HardwareDesignProject/mips.v`.
// Keeps the legacy `controller` intact (positional instantiations in old labs)
// while providing the wider interface required by the 52+/57 work.
module controller2(
    input  wire        clk,
    input  wire        rst,
    // --- Decode Stage ---
    input  wire [5:0]  opD,
    input  wire [5:0]  functD,
    input  wire [4:0]  rtD,
    input  wire        equalD,
    output wire        pcsrcD,
    output wire        branchD,
    output wire        jumpD,
    output wire        jumpregD,
    output wire [2:0]  branch_opD,

    // --- Execute Stage ---
    input  wire        flushE,
    output wire        memtoregE,
    output wire        alusrcE,
    output wire        regdstE,
    output wire        regwriteE,
    output wire [2:0]  alucontrolE,
    output wire        hassignE,
    output wire        isluiE,
    output wire        divE,
    output wire [1:0]  hilo_enE,
    output wire [1:0]  hilo_mfE,
    output wire [1:0]  shiftE,
    output wire        linkE,
    output wire        jalrE,

    // --- Memory Stage ---
    output wire        memtoregM,
    output wire        memwriteM,
    output wire        regwriteM,
    output wire [2:0]  mem_opM,
    output wire        linkM,
    output wire        jalrM,

    // --- Write Back Stage ---
    output wire        memtoregW,
    output wire        regwriteW,
    output wire        linkW,
    output wire        jalrW
);

    // Decode-stage internal signals
    wire [2:0] aluopD;
    wire memtoregD, memwriteD, alusrcD, regdstD, regwriteD_raw, regwriteD;
    wire [2:0] alucontrolD;
    wire hassign_md, hassign_ad, hassignD;
    wire divD, isluiD;
    wire [1:0] hilo_enD, hilo_mfD, shiftD;
    wire [2:0] mem_opD;
    wire linkD, linkD_final, jalrD;

    // Main decode + ALU decode
    maindec2 md(
        .op(opD),
        .rt(rtD),
        .funct(functD),
        .regwrite(regwriteD_raw),
        .regdst(regdstD),
        .alusrc(alusrcD),
        .branch(branchD),
        .memwrite(memwriteD),
        .memtoreg(memtoregD),
        .jump(jumpD),
        .aluop(aluopD),
        .hassign(hassign_md),
        .islui(isluiD),
        .mem_op(mem_opD),
        .branch_op(branch_opD),
        .link(linkD)
    );

    aludec ad(rst, functD, aluopD, alucontrolD, hassign_ad, hilo_enD, hilo_mfD, divD, shiftD);

    assign hassignD = hassign_md | hassign_ad;

    // JR/JALR detection (opcode=0)
    wire is_jr   = (opD == 6'b000000) && (functD == 6'b001000);
    wire is_jalr = (opD == 6'b000000) && (functD == 6'b001001);

    assign jumpregD = is_jr | is_jalr;
    assign jalrD    = is_jalr;
    assign pcsrcD   = branchD & equalD;

    // JR doesn't write GPR; JALR does.
    assign regwriteD = regwriteD_raw & ~is_jr;

    // Link semantics:
    // - JAL/JALR always link
    // - BLTZAL/BGEZAL also link even when the branch is not taken
    assign linkD_final = linkD;

    // Pipeline registers
    wire memwriteE;
    wire [2:0] mem_opE;
    floprc #(22) regE(
        clk, rst, flushE,
        {memtoregD, memwriteD, alusrcD, regdstD, regwriteD, alucontrolD, hassignD,
         hilo_enD, hilo_mfD, divD, isluiD, shiftD, mem_opD, linkD_final, jalrD},
        {memtoregE, memwriteE, alusrcE, regdstE, regwriteE, alucontrolE, hassignE,
         hilo_enE, hilo_mfE, divE, isluiE, shiftE, mem_opE, linkE, jalrE}
    );

    flopr #(8) regM(
        clk, rst,
        {memtoregE, memwriteE, regwriteE, mem_opE, linkE, jalrE},
        {memtoregM, memwriteM, regwriteM, mem_opM, linkM, jalrM}
    );

    flopr #(4) regW(
        clk, rst,
        {memtoregM, regwriteM, linkM, jalrM},
        {memtoregW, regwriteW, linkW, jalrW}
    );
endmodule
