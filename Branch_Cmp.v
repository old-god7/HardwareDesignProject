`timescale 1ns / 1ps

// Branch comparator for MIPS branch family.
// cmp_op encoding (matches `maindec2`):
// 000: BEQ   (a == b)
// 001: BNE   (a != b)
// 010: BGTZ  (a > 0)
// 011: BLEZ  (a <= 0)
// 100: BLTZ  (a < 0)
// 101: BGEZ  (a >= 0)
module Branch_Cmp(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  cmp_op,
    output wire        cmp_result
);
    wire eq  = (a == b);
    wire neq = ~eq;

    wire a_neg = a[31];
    wire a_zero = (a == 32'b0);

    // signed comparisons for >0 / <=0 / <0 / >=0
    wire gt0 = (~a_neg) & (~a_zero);
    wire le0 = a_neg | a_zero;
    wire lt0 = a_neg;
    wire ge0 = ~a_neg;

    assign cmp_result =
        (cmp_op == 3'b000) ? eq  :
        (cmp_op == 3'b001) ? neq :
        (cmp_op == 3'b010) ? gt0 :
        (cmp_op == 3'b011) ? le0 :
        (cmp_op == 3'b100) ? lt0 :
        (cmp_op == 3'b101) ? ge0 :
                             1'b0;
endmodule

