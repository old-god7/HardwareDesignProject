`timescale 1ns / 1ps

// Main decoder (extended) used by `controller2`.
// Derived from the project’s 52-instruction baseline decode.
module maindec2(
    input  wire [5:0] op,
    input  wire [4:0] rt,
    input  wire [5:0] funct,  // reserved for JR/JALR, etc.

    output wire       regwrite,
    output wire       regdst,
    output wire       alusrc,
    output wire       branch,
    output wire       memwrite,
    output wire       memtoreg,
    output wire       jump,
    output wire [2:0] aluop,
    output wire       hassign,
    output wire       islui,
    output wire [2:0] mem_op,
    output wire [2:0] branch_op,
    output wire       link
);
    reg [18:0] controls;
    assign {regwrite, regdst, alusrc, branch, memwrite, memtoreg, jump,
            aluop, hassign, islui, mem_op, branch_op, link} = controls;

    always @(*) begin
        case (op)
            // R-type
            6'b000000: controls <= 19'b1100000_010_0_0_000_000_0;

            // Base load/store
            6'b100011: controls <= 19'b1010010_000_0_0_000_000_0; // LW
            6'b101011: controls <= 19'b0110100_000_0_0_000_000_0; // SW

            // Extended load/store (member3)
            6'b100000: controls <= 19'b1010010_000_0_0_110_000_0; // LB
            6'b100100: controls <= 19'b1010010_000_0_0_111_000_0; // LBU
            6'b100001: controls <= 19'b1010010_000_0_0_100_000_0; // LH
            6'b100101: controls <= 19'b1010010_000_0_0_101_000_0; // LHU
            6'b101000: controls <= 19'b0010100_000_0_0_010_000_0; // SB
            6'b101001: controls <= 19'b0010100_000_0_0_001_000_0; // SH

            // Branches
            6'b000100: controls <= 19'b0001000_001_0_0_000_000_0; // BEQ
            6'b000101: controls <= 19'b0001000_001_0_0_000_001_0; // BNE
            6'b000111: controls <= 19'b0001000_001_0_0_000_010_0; // BGTZ
            6'b000110: controls <= 19'b0001000_001_0_0_000_011_0; // BLEZ

            // REGIMM (BLTZ/BGEZ/BLTZAL/BGEZAL)
            6'b000001: begin
                case (rt)
                    5'b00000: controls <= 19'b0001000_001_0_0_000_100_0; // BLTZ
                    5'b00001: controls <= 19'b0001000_001_0_0_000_101_0; // BGEZ
                    5'b10000: controls <= 19'b1001000_001_0_0_000_100_1; // BLTZAL
                    5'b10001: controls <= 19'b1001000_001_0_0_000_101_1; // BGEZAL
                    default:  controls <= 19'b0000000_000_0_0_000_000_0;
                endcase
            end

            // I-type
            6'b001000: controls <= 19'b1010000_000_0_0_000_000_0; // ADDI
            6'b001001: controls <= 19'b1010000_000_0_0_000_000_0; // ADDIU
            6'b001111: controls <= 19'b1010000_000_0_1_000_000_0; // LUI
            6'b001010: controls <= 19'b1010000_011_1_0_000_000_0; // SLTI
            6'b001011: controls <= 19'b1010000_011_0_0_000_000_0; // SLTIU
            6'b001100: controls <= 19'b1010000_100_0_0_000_000_0; // ANDI
            6'b001101: controls <= 19'b1010000_101_0_0_000_000_0; // ORI
            6'b001110: controls <= 19'b1010000_110_0_0_000_000_0; // XORI

            // Jumps
            6'b000010: controls <= 19'b0000001_000_0_0_000_000_0; // J
            6'b000011: controls <= 19'b1000001_000_0_0_000_000_1; // JAL

            default:   controls <= 19'b0000000_000_0_0_000_000_0;
        endcase
    end
endmodule

