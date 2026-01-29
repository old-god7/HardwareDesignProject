`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/11/02 15:12:22
// Design Name: 
// Module Name: datapath
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


module datapath(
    input wire clk, rst,
    // --- Fetch Stage ---
    output wire[31:0] pcF,
    input wire[31:0] instrF,
    // --- Decode Stage ---
    input wire pcsrcD, branchD,
    input wire [2:0] branch_opD,
    input wire jumpD,
    input wire jumpregD,
    output wire equalD,
    output wire[5:0] opD, functD,
    output wire[4:0] rtD,
    // --- Execute Stage ---
    input wire memtoregE, alusrcE, regdstE, regwriteE,
    input wire linkE, jalrE,
    input wire[2:0] alucontrolE,
    input wire hassignE, isluiE, divE,
    input wire [1:0] hilo_enE, hilo_mfE, shiftE,
    output wire flushE,
    // --- Mem Stage ---
    input wire memtoregM, memwriteM, regwriteM,
    input wire linkM, jalrM,
    input wire [2:0] mem_opM,
    output wire[31:0] aluoutM, writedataM,
    input wire[31:0] readdataM,
    // --- Writeback Stage ---
    input wire memtoregW, regwriteW,
    input wire linkW, jalrW,
    // --- Debug (WB stage) ---
    output wire[31:0] debug_wb_pc,
    output wire[3:0]  debug_wb_rf_wen,
    output wire[4:0]  debug_wb_rf_wnum,
    output wire[31:0] debug_wb_rf_wdata,
    // --- Exception/CP0 (MEM stage commit) ---
    output wire        exc_commitM,
    // --- Squash younger inst in MEM (one-cycle after exception/eret) ---
    output wire        squashM
);

    // --- 内部信号定义 ---
    wire stallF, stallD, flushD;
    wire flushE_hazard;
    wire flushE_eff;
    wire [31:0] pcnextFD, pcnextbrFD, pcplus4F, pcplus4D, pcplus8D, pcbranchD, pcjumpD, pcjumpregD, pcnextbrjD;
    wire [31:0] instrD, signimmD, signimmshD, zeroimmD, luiimmD;
    wire [31:0] srcaD, srca2D, srcbD, srcb2D;
    wire [4:0] rsD, rdD, saD;
    wire forwardaD, forwardbD;

    wire [1:0] forwardaE, forwardbE;
    wire [4:0] rsE, rtE, rdE, saE, writeregE, writeregE_temp;
    wire [31:0] srcaE, srca2E, srca3E, srcbE, srcb2E, srcb3E, srcimmE;
    wire [31:0] aluoutE, aluresultE, aluresult_loE, finaloutE;
    wire [31:0] signimmE, zeroimmE, luiimmE, pcplus8E;
    wire [31:0] hi_inE, lo_inE, hi_outE, lo_outE, qE, rE;
    wire divbusyE, divdoneE;

    wire [4:0] writeregM;
    wire [31:0] pcplus8M;
    wire [4:0] writeregW;
    wire [31:0] aluoutW, readdataW, resultW, resultW_temp, pcplus8W;
    // Local jalr detect pipeline (keeps jalr return-address behavior correct even if control-path jalr is mis-generated)
    wire is_jalrD_local, is_jalrE_local, is_jalrM_local, is_jalrW_local;
    // CP0 / Exception control (local decode + pipeline)
    wire mfc0D, mtc0D, eretD;
    wire mfc0E, mtc0E, eretE;
    wire mfc0M, mtc0M, eretM;
    wire mfc0W;
    wire [4:0] cp0_addrD, cp0_addrE, cp0_addrM, cp0_addrW;
    wire [31:0] cp0_wdataD, cp0_wdataE, cp0_wdataM;
    wire [31:0] cp0_rdata;
    wire [31:0] cp0_rdataE, cp0_rdataM, cp0_rdataW;
    wire [31:0] cp0_epc, cp0_status, cp0_cause, cp0_badvaddr;
    wire cp0_exl;
    wire eret_commitM;
    wire flush_except;
    reg  squashM_r;
    reg  squashW_r;

    // Exception/Interrupt pipeline (commit in MEM stage)
    // NOTE: ExcCode=0 represents "interrupt" (Int). Therefore we must carry an explicit
    //       valid bit instead of using (exc_code != 0) as the exception predicate.
    wire       exc_validD;
    wire [4:0] exc_codeD;
    wire       exc_validE_base, exc_validE;
    wire [4:0] exc_codeE_base, exc_codeE;
    wire       exc_validM_base, exc_validM;
    wire [4:0] exc_codeM_base;
    wire [4:0] exc_codeM;
    wire [31:0] badvaddrM;
    wire exc_commitW; // kill WB writeback for the excepting instruction
    wire ov_enD, ov_enE;
    wire overflowE, zeroE;

    // Delay slot flag pipeline (for CP0 BD/EPC)
    reg  in_delayslotD;
    wire in_delayslotE, in_delayslotM;
    // Precise exception/ERET: keep younger instructions out of the pipeline until commit in MEM.
    reg  exc_hold;

    // Effective regwrite for hazards/writeback (include MFC0, exclude killed WB)
    wire regwriteW_eff = (regwriteW | mfc0W) & ~exc_commitW & ~squashW_r;
    wire regwriteM_eff = (regwriteM | mfc0M) & ~squashM_r;
    wire regwriteE_eff = regwriteE | mfc0E;

    // --- Hazard Detection ---
    hazard h(
        .stallF(stallF), .rsD(rsD), .rtD(rtD), .branchD(branchD), .jumpregD(jumpregD),
        .cp0writeD(mtc0D),
        .forwardaD(forwardaD), .forwardbD(forwardbD), .stallD(stallD),
        .rsE(rsE), .rtE(rtE), .writeregE(writeregE), .regwriteE(regwriteE_eff), .memtoregE(memtoregE),
        .divE(divE), .divbusyE(divbusyE), .forwardaE(forwardaE), .forwardbE(forwardbE), .flushE(flushE_hazard),
        .writeregM(writeregM), .regwriteM(regwriteM_eff), .memtoregM(memtoregM & ~squashM_r),
        .writeregW(writeregW), .regwriteW(regwriteW_eff)
    );

    localparam [31:0] EXC_VECTOR = 32'hBFC0_0380;
    assign flush_except = exc_commitM | eret_commitM;
    // If an exception/ERET is already in Execute stage, flush Execute's incoming pipeline
    // (kills the instruction currently in Decode which is younger than the excepting one).
    wire exc_or_eretD = exc_validD | eretD;
    // If Decode is stalled, do NOT "fire" exception/eret handling yet; keep the instruction in D
    // until it can advance into E. Otherwise we may drop the exception and latch `exc_hold` forever.
    wire exc_or_eretD_fire = exc_or_eretD & ~stallD;
    wire exc_or_eretE = exc_validE | eretE;
    assign flushE_eff = flushE_hazard | flush_except | exc_or_eretE;
    assign flushE = flushE_eff;

    // --- Fetch Stage Logic ---
    wire [31:0] pcnextF = exc_commitM ? EXC_VECTOR :
                          eret_commitM ? cp0_epc :
                          pcnextFD;
    pc #(.WIDTH(32), .RESET_VALUE(32'hBFC0_0000)) pcreg(clk, rst, (~stallF) | flush_except, pcnextF, pcF);
    adder pcadd1(pcF, 32'h4, pcplus4F);

    // --- Decode Stage Logic ---
    flopenr #(32) r1D(clk, rst, ~stallD, pcplus4F, pcplus4D);
    // 【修改点 1】延迟槽下，跳转不再冲刷 Decode 级；异常/ERET 需要冲刷 Decode/Execute。
    assign flushD = flush_except | exc_or_eretD_fire | exc_hold;
    flopenrc #(32) r2D(clk, rst, ~stallD, flushD, instrF, instrD);
    
    assign opD = instrD[31:26];
    assign functD = instrD[5:0];
    assign rsD = instrD[25:21];
    assign rtD = instrD[20:16];
    assign rdD = instrD[15:11];
    assign saD = instrD[10:6];

    // Local CP0 decode (minimal set for func_test: MFC0/MTC0/ERET)
    assign cp0_addrD = rdD;
    assign mfc0D = (opD == 6'b010000) && (rsD == 5'b00000);
    assign mtc0D = (opD == 6'b010000) && (rsD == 5'b00100);
    assign eretD = (opD == 6'b010000) && (rsD == 5'b10000) && (functD == 6'b011000);

    // Reserved instruction detect (RI): if op/funct not in the supported set
    reg valid_instrD;
    always @(*) begin
        valid_instrD = 1'b1;
        case (opD)
            6'b000000: begin
                case (functD)
                    6'b100000, // ADD
                    6'b100001, // ADDU
                    6'b100010, // SUB
                    6'b100011, // SUBU
                    6'b100100, // AND
                    6'b100101, // OR
                    6'b100110, // XOR
                    6'b100111, // NOR
                    6'b101010, // SLT
                    6'b101011, // SLTU
                    6'b011000, // MULT
                    6'b011001, // MULTU
                    6'b011010, // DIV
                    6'b011011, // DIVU
                    6'b010000, // MFHI
                    6'b010010, // MFLO
                    6'b010001, // MTHI
                    6'b010011, // MTLO
                    6'b000000, // SLL
                    6'b000010, // SRL
                    6'b000011, // SRA
                    6'b000100, // SLLV
                    6'b000110, // SRLV
                    6'b000111, // SRAV
                    6'b001000, // JR
                    6'b001001, // JALR
                    6'b001100, // SYSCALL
                    6'b001101: // BREAK
                        valid_instrD = 1'b1;
                    default:
                        valid_instrD = 1'b0;
                endcase
            end
            6'b000001: begin // REGIMM
                case (rtD)
                    5'b00000, // BLTZ
                    5'b00001, // BGEZ
                    5'b10000, // BLTZAL
                    5'b10001: // BGEZAL
                        valid_instrD = 1'b1;
                    default:
                        valid_instrD = 1'b0;
                endcase
            end
            6'b010000: begin // COP0
                valid_instrD = mfc0D | mtc0D | eretD;
            end
            6'b100011, // LW
            6'b101011, // SW
            6'b100000, // LB
            6'b100100, // LBU
            6'b100001, // LH
            6'b100101, // LHU
            6'b101000, // SB
            6'b101001, // SH
            6'b000100, // BEQ
            6'b000101, // BNE
            6'b000111, // BGTZ
            6'b000110, // BLEZ
            6'b001000, // ADDI
            6'b001001, // ADDIU
            6'b001111, // LUI
            6'b001010, // SLTI
            6'b001011, // SLTIU
            6'b001100, // ANDI
            6'b001101, // ORI
            6'b001110, // XORI
            6'b000010, // J
            6'b000011: // JAL
                valid_instrD = 1'b1;
            default:
                valid_instrD = 1'b0;
        endcase
    end

    // Delay slot tracking: the instruction that enters Decode is marked as "in delay slot"
    // iff the previous Decode-stage instruction (the one leaving Decode this cycle) is a
    // control-transfer (branch/jump/jr/jal/jalr). This formulation is stall-safe.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            in_delayslotD <= 1'b0;
        end else if (flush_except) begin
            in_delayslotD <= 1'b0;
        end else if (~stallD) begin
            in_delayslotD <= (branchD | jumpD | jumpregD);
        end
    end

    // Precise exception/ERET: once an exception (sys/break/ri/ov) or ERET is detected
    // in the pipeline (D or E stage), keep Decode flushed until it is committed in MEM.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            exc_hold <= 1'b0;
        end else if (flush_except) begin
            exc_hold <= 1'b0;
        end else if (exc_hold) begin
            exc_hold <= 1'b1;
        end else if (exc_or_eretD_fire | exc_or_eretE) begin
            exc_hold <= 1'b1;
        end else begin
            exc_hold <= 1'b0;
        end
    end

    // 成员3：ExtUnit 接入（替代 signext）
    wire [1:0] ext_typeD;
    assign ext_typeD = (opD == 6'b001100 ||  // ANDI
                        opD == 6'b001101 ||  // ORI
                        opD == 6'b001110) ?  // XORI
                       2'b01 :               // 零扩展
                       2'b00;                // 符号扩展
    ExtUnit extu(instrD[15:0], ext_typeD, signimmD);

    // Trap detect -> exception decode (Sys/Break)
    wire trap_syscallD, trap_breakD;
    wire [5:0] trap_typeD;
    Trap_Detect u_trap_detect(.instr(instrD), .is_syscall(trap_syscallD), .is_break(trap_breakD), .trap_type(trap_typeD));

    // Instruction-fetch address error (AdEL): misaligned PC (pc[1:0] != 0)
    // NOTE: pcplus4D is pcF+4, so it has the same [1:0] bits as pcF.
    wire adel_ifD = |pcplus4D[1:0];

    // Pending interrupt detect (software interrupts are written via MTC0 to Cause.IP[1:0]).
    // Take interrupt only when IE=1 and EXL=0 and (IP & IM) != 0.
    wire int_pendingD = cp0_status[0] & ~cp0_exl & (|(cp0_status[15:8] & cp0_cause[15:8]));

    // Exception/Interrupt in D (pipelined and committed in MEM stage)
    // Priority: IF AdEL > Int > Sys/Break > RI
    assign exc_validD = adel_ifD | int_pendingD | trap_syscallD | trap_breakD | (~valid_instrD);
    assign exc_codeD  = adel_ifD       ? 5'h04 :   // AdEL (IF)
                        int_pendingD   ? 5'h00 :   // Int
                        trap_syscallD  ? 5'h08 :   // Sys
                        trap_breakD    ? 5'h09 :   // Bp
                        (~valid_instrD) ? 5'h0a :  // RI
                        5'h00;
    sl2 immsh(signimmD, signimmshD);
    adder pcadd2(pcplus4D, signimmshD, pcbranchD);
    // 【修改点 2】返回地址计算。
    // 在延迟槽架构中，JAL 存入的应该是当前跳转指令地址 + 8。
    // 此时 pcplus4D 已经是跳转指令的 PC+4，所以再加 4 得到 PC+8。
    adder pcadd3(pcplus4D, 32'h4, pcplus8D); 

    mux2 #(32) forwardamux(srcaD, aluoutM, forwardaD, srca2D);
    mux2 #(32) forwardbmux(srcbD, aluoutM, forwardbD, srcb2D);

    Branch_Cmp branch_cmp(
        .a(srca2D), .b(srcb2D), .cmp_op(branch_opD), .cmp_result(equalD)
    );

    assign pcjumpD = {pcplus4D[31:28], instrD[25:0], 2'b00};
    assign pcjumpregD = srca2D;
    
    mux2 #(32) pcbrmux(pcplus4F, pcbranchD, pcsrcD, pcnextbrFD);
    mux2 #(32) pcjumpmux(pcjumpD, pcjumpregD, jumpregD, pcnextbrjD);
    mux2 #(32) pcfinalmux(pcnextbrFD, pcnextbrjD, jumpD | jumpregD, pcnextFD);

    assign zeroimmD = {16'b0, instrD[15:0]};
    assign luiimmD = {instrD[15:0], 16'b0};

    // WB write enable is locally augmented for MFC0 and masked on exception-commit.
    regfile rf(clk, regwriteW_eff, rsD, rtD, writeregW, resultW, srcaD, srcbD);
    assign cp0_wdataD = srcb2D;

    // Overflow-enable (only ADD/SUB/ADDI should raise OV)
    assign ov_enD = (opD == 6'b001000) || // ADDI
                    ((opD == 6'b000000) && ((functD == 6'b100000) || (functD == 6'b100010))); // ADD/SUB

    // Local detect for `jalr` (opcode=0, funct=0x09). This is for selecting PC+8 as writeback data.
    assign is_jalrD_local = (instrD[31:26] == 6'b000000) && (instrD[5:0] == 6'b001001);

    // --- Execute Stage Logic ---
    // 【修改点 3】由于不冲刷 Decode，我们需要把跳转后的那条指令（延迟槽指令）送入 Execute。
    // 注意：srca2D 和 srcb2D 已经包含了从 Memory 级前推的数据，这对于跳转指令本身很重要。
    // 延迟槽指令作为普通指令，流水线寄存器正常传递。
    // E-stage sideband pipeline
    floprc #(1)  r_delayE(clk, rst, flushE_eff, in_delayslotD, in_delayslotE);
    floprc #(1)  r_excVE (clk, rst, flushE_eff, exc_validD,   exc_validE_base);
    floprc #(5)  r_excE  (clk, rst, flushE_eff, exc_codeD,    exc_codeE_base);
    floprc #(1)  r_ovE   (clk, rst, flushE_eff, ov_enD,       ov_enE);
    floprc #(1)  r_mfc0E (clk, rst, flushE_eff, mfc0D,        mfc0E);
    floprc #(1)  r_mtc0E (clk, rst, flushE_eff, mtc0D,        mtc0E);
    floprc #(1)  r_eretE (clk, rst, flushE_eff, eretD,        eretE);
    floprc #(5)  r_cp0aE (clk, rst, flushE_eff, cp0_addrD,    cp0_addrE);
    floprc #(32) r_cp0wE (clk, rst, flushE_eff, cp0_wdataD,   cp0_wdataE);
    floprc #(32) r_cp0rE (clk, rst, flushE_eff, cp0_rdata,    cp0_rdataE);

    // E-stage main pipeline
    floprc #(32) r1E(clk, rst, flushE_eff, srcaD, srcaE);
    floprc #(32) r2E(clk, rst, flushE_eff, srcbD, srcbE);
    floprc #(32) r3E(clk, rst, flushE_eff, signimmD, signimmE);
    floprc #(5)  r4E(clk, rst, flushE_eff, rsD, rsE);
    floprc #(5)  r5E(clk, rst, flushE_eff, rtD, rtE);
    floprc #(5)  r6E(clk, rst, flushE_eff, rdD, rdE);
    floprc #(32) r7E(clk, rst, flushE_eff, zeroimmD, zeroimmE);
    floprc #(32) r8E(clk, rst, flushE_eff, luiimmD, luiimmE);
    floprc #(5)  r9E(clk, rst, flushE_eff, saD, saE);
    floprc #(32) r10E(clk, rst, flushE_eff, pcplus8D, pcplus8E);
    floprc #(1)  r11E_jalr_local(clk, rst, flushE_eff, is_jalrD_local, is_jalrE_local);

    mux3 #(32) forwardaemux(srcaE, resultW, aluoutM, forwardaE, srca2E);
    mux3 #(32) forwardbemux(srcbE, resultW, aluoutM, forwardbE, srcb2E);

    mux3 #(32) srcextmux(signimmE, zeroimmE, luiimmE, {isluiE, alucontrolE[0]}, srcimmE);
    mux2 #(32) srcamux(srca2E, {27'b0, saE}, shiftE[0], srca3E);
    mux2 #(32) srcbmux(srcb2E, srcimmE, alusrcE, srcb3E);

    alu alu(srca3E, srcb3E, alucontrolE, hassignE, shiftE[1], aluresultE, aluresult_loE, overflowE, zeroE);
    // Overflow exception (OV=0x0c), committed in MEM stage
    wire overflow_excE = ov_enE && overflowE;
    assign exc_validE = exc_validE_base | overflow_excE;
    assign exc_codeE  = exc_validE_base ? exc_codeE_base :
                        overflow_excE   ? 5'h0c :
                        5'h00;

    // Precise exception: when an exception/ERET is committed in MEM stage, the younger instruction in EX stage
    // must not produce architectural side-effects (e.g., HI/LO writeback, divider start/done writeback).
    wire       divE_eff      = divE & ~flush_except;
    wire       divdoneE_eff  = divdoneE & ~flush_except;
    wire [1:0] hilo_enE_eff  = flush_except ? 2'b00 : hilo_enE;

    divider div_inst(clk, rst, divE_eff, hassignE, srca3E, srcb3E, qE, rE, divbusyE, divdoneE);

    mux3 #(32) hiinmux(aluresultE, srca3E, rE, {divdoneE_eff, hilo_enE_eff[1]}, hi_inE);
    mux3 #(32) loinmux(aluresult_loE, srca3E, qE, {divdoneE_eff, hilo_enE_eff[1]}, lo_inE);
    hilo_reg hilo_reg(clk,rst,divdoneE_eff,hilo_enE_eff,hi_inE,lo_inE,hi_outE,lo_outE);	//写hi_lo寄存器堆，是在EX阶段做的

    mux3 #(32) aluoutmux(lo_outE, hi_outE, aluresultE, hilo_mfE, aluoutE);
    
    wire [31:0] finaloutE_link;
    mux2 #(32) linkemux(aluoutE, pcplus8E, linkE | jalrE | is_jalrE_local, finaloutE_link);
    // MFC0 writes CP0 value to GPR (treat as an ALU-like result)
    assign finaloutE = mfc0E ? cp0_rdataE : finaloutE_link;
    
    mux2 #(5) wrmux(rtE, rdE, regdstE, writeregE_temp);
    mux2 #(5) linkregmux(writeregE_temp, 5'd31, linkE, writeregE); 

    // --- Memory Stage Logic ---
    flopr #(32) r1M(clk, rst, srcb2E, writedataM);
    flopr #(32) r2M(clk, rst, finaloutE, aluoutM);
    flopr #(5) r3M(clk, rst, writeregE, writeregM);
    flopr #(32) r4M(clk, rst, pcplus8E, pcplus8M);
    flopr #(1) r5M_jalr_local(clk, rst, is_jalrE_local, is_jalrM_local);
    flopr #(1)  r6M_delay(clk, rst, in_delayslotE, in_delayslotM);
    flopr #(1)  r7M_excV (clk, rst, exc_validE,   exc_validM_base);
    flopr #(5)  r7M_exc  (clk, rst, exc_codeE,    exc_codeM_base);
    flopr #(1)  r8M_mfc0 (clk, rst, mfc0E,        mfc0M);
    flopr #(1)  r9M_mtc0 (clk, rst, mtc0E,        mtc0M);
    flopr #(1)  r10M_eret(clk, rst, eretE,        eretM);
    flopr #(5)  r11M_cp0a(clk, rst, cp0_addrE,    cp0_addrM);
    flopr #(32) r12M_cp0w(clk, rst, cp0_wdataE,   cp0_wdataM);

    // Address error (AdEL/AdES) detection in MEM stage
    wire [1:0] mem_addr_low = aluoutM[1:0];
    wire adel_lw  = (memtoregM & ~squashM_r) && (mem_opM == 3'b000) && (mem_addr_low != 2'b00);
    wire adel_lh  = (memtoregM & ~squashM_r) && ((mem_opM == 3'b100) || (mem_opM == 3'b101)) && mem_addr_low[0];
    wire ades_sw  = (memwriteM & ~squashM_r) && (mem_opM == 3'b000) && (mem_addr_low != 2'b00);
    wire ades_sh  = (memwriteM & ~squashM_r) && (mem_opM == 3'b001) && mem_addr_low[0];
    wire addr_exc_valid = adel_lw | adel_lh | ades_sw | ades_sh;
    wire [4:0] addr_exc_code = (adel_lw | adel_lh) ? 5'h04 :
                               (ades_sw | ades_sh) ? 5'h05 :
                               5'h00;

    assign exc_validM = addr_exc_valid ? 1'b1 : exc_validM_base;
    assign exc_codeM  = addr_exc_valid ? addr_exc_code : exc_codeM_base;
    // BadVAddr source:
    // - Data address errors: use data address (aluoutM)
    // - IF AdEL: use faulting PC (pcM)
    assign badvaddrM = addr_exc_valid ? aluoutM :
                       ((exc_validM_base && (exc_codeM_base == 5'h04)) ? pcM : 32'b0);
    assign exc_commitM = exc_validM & ~squashM_r;
    assign eret_commitM = eretM & ~exc_commitM & ~squashM_r;

    // Squash the instruction that is in EX stage when exception/eret is committed in MEM stage.
    // That younger instruction will enter MEM stage in the next cycle unless masked.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            squashM_r <= 1'b0;
            squashW_r <= 1'b0;
        end else begin
            squashM_r <= flush_except;
            squashW_r <= squashM_r;
        end
    end

    assign squashM = squashM_r;

    // CP0 register file (supports exception entry/return + MFC0/MTC0)
    wire [31:0] pcM = pcplus8M - 32'h8;
    wire [31:0] cp0_rdata_raw;
    CP0_Reg u_cp0(
        .clk(clk),
        .rst(rst),
        .we(mtc0M & ~exc_commitM & ~eret_commitM & ~squashM_r),
        .waddr(cp0_addrM),
        .raddr(cp0_addrD),
        .wdata(cp0_wdataM),
        .rdata(cp0_rdata_raw),
        .exc_valid_i(exc_commitM),
        .exc_code_i(exc_codeM),
        .pc_i(pcM),
        .in_delay_slot_i(in_delayslotM),
        .badvaddr_i(badvaddrM),
        .eret_i(eret_commitM),
        .hw_int_i(6'd0),
        .epc_o(cp0_epc),
        .exl_o(cp0_exl),
        .status_o(cp0_status),
        .cause_o(cp0_cause),
        .badvaddr_o(cp0_badvaddr)
    );

    // CP0 read bypass:
    // - MTC0 writes take effect at the clock edge, so a following MFC0 needs bypassing to observe the new value.
    // - Provide E/M-stage bypass to the D-stage CP0 read port (captured into E stage).
    wire cp0_bypassE = mtc0E && (cp0_addrE == cp0_addrD);
    wire cp0_bypassM = (mtc0M & ~exc_commitM & ~eret_commitM) && (cp0_addrM == cp0_addrD);
    assign cp0_rdata = cp0_bypassE ? cp0_wdataE :
                       cp0_bypassM ? cp0_wdataM :
                       cp0_rdata_raw;

    // --- Writeback Stage Logic ---
    flopr #(32) r1W(clk, rst, aluoutM, aluoutW);
    flopr #(32) r2W(clk, rst, readdataM, readdataW);
    flopr #(5) r3W(clk, rst, writeregM, writeregW);
    flopr #(32) r4W(clk, rst, pcplus8M, pcplus8W);
    flopr #(1) r5W_jalr_local(clk, rst, is_jalrM_local, is_jalrW_local);
    flopr #(1) r6W_mfc0(clk, rst, mfc0M, mfc0W);
    flopr #(1) r7W_exc_commit(clk, rst, exc_commitM, exc_commitW);

    mux2 #(32) resmux(aluoutW, readdataW, memtoregW, resultW_temp);
    mux2 #(32) linkwmux(resultW_temp, pcplus8W, linkW | jalrW | is_jalrW_local, resultW);

    // Debug outputs (trace compare)
    assign debug_wb_pc = pcplus8W - 32'h8;
    assign debug_wb_rf_wen = (regwriteW_eff && (writeregW != 5'd0)) ? 4'b1111 : 4'b0000;
    assign debug_wb_rf_wnum = writeregW;
    assign debug_wb_rf_wdata = resultW;

endmodule
