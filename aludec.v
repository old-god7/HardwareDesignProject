`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/10/23 15:27:24
// Design Name: 
// Module Name: aludec
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


module aludec(
    input wire rst,
	input wire[5:0] funct,
	input wire[2:0] aluop,
	output reg[2:0] alucontrol,
	output reg hassign,
    output reg[1:0] hilo_en,
    output reg[1:0] hilo_mf,
    output reg div,
    output reg[1:0] shift
    );
	always @(*) begin
        hassign <= 1'b0;
        hilo_en <= 2'b00;   //00表示不写hilo寄存器，01表示写HI和LO，11表示写HI，10表示写LO
        hilo_mf <= 2'b10;   //01表示HI写寄存器，00表示LO写寄存器，10表示没有HI和LO写寄存器。
        div <= 1'b0;
        shift <= 2'b00;
		case (aluop)
			3'b000: alucontrol <= 3'b010;   //add (for lw/sw/addi/addiu)
			3'b001: alucontrol <= 3'b110;   //sub (for beq)
			3'b011: alucontrol <= 3'b000;   //slt (for slti,sltiu)
            3'b100: alucontrol <= 3'b011;   //and (for andi)
            3'b101: alucontrol <= 3'b001;   //or  (for ori)
            3'b110: alucontrol <= 3'b111;   //xor (for xori)
			3'b010: case (funct)    // R型指令
                6'b100000:    begin    //ADD
                    alucontrol <= 3'b010; //add
                    hassign <= 1'b1;
                end
                6'b100001: begin    //ADDU
                    alucontrol <= 3'b010; //add
                end
                6'b100010: begin    //SUB
                    alucontrol <= 3'b110; //sub
                    hassign <= 1'b1;
                end
                6'b100011: begin    //SUBU
                    alucontrol <= 3'b110; //sub
                end
                6'b100100: begin    //AND
                    alucontrol <= 3'b011; //and
                end
                6'b100101: begin    //OR
                    alucontrol <= 3'b001; //or
                end
                6'b101010: begin    //SLT
                    alucontrol <= 3'b000; //slt
                    hassign <= 1'b1;    
                end
                6'b101011: begin    //SLTU
                    alucontrol <= 3'b000; //slt
                end
                6'b011000: begin    //MULT
                    alucontrol <= 3'b100; //mult
                    hassign <= 1'b1;
                    hilo_en <= 2'b01;
                end
                6'b011001:begin     //MULTU
                    alucontrol <= 3'b100; //mult
                    hilo_en <= 2'b01;
                end
                6'b010000:begin     //MFHI
                    alucontrol <= 3'b000; //不做计算
                    hilo_mf <= 2'b01;
                end
                6'b010010:begin     //MFLO
                    alucontrol <= 3'b000; //不做计算
                    hilo_mf <= 2'b00;      
                end
                6'b010001:begin     //MTHI
                    alucontrol <= 3'b000;
                    hilo_en <= 2'b11;
                end
                6'b010011:begin     //MTLO
                    alucontrol <= 3'b000;
                    hilo_en <= 2'b10;
                end
                6'b011010:begin     //DIV
                    alucontrol <= 3'b000;
                    div <= 1'b1;
                    hassign <= 1'b1;
                end
                6'b011011:begin     //DIVU
                    alucontrol <= 3'b000;
                    div <= 1'b1;
                    hassign <= 1'b0;
                end
                6'b100111:begin     //NOR
                    alucontrol <= 3'b101;   
                end
                6'b100110:begin     //XOR
                    alucontrol <= 3'b111;
                end
                6'b000000:begin     //SLL
                    alucontrol <= 3'b001;
                    if(~rst) begin
                        shift <= 2'b11;
                    end
                end
                6'b000010:begin     //SRL
                    alucontrol <= 3'b011;
                    shift <= 2'b11;
                end
                6'b000011:begin     //SRA
                    alucontrol <= 3'b101;
                    shift <= 2'b11;
                end
                6'b000100:begin     //SLLV
                    alucontrol <= 3'b001;
                    shift <= 2'b10;
                end
                6'b000110:begin     //SRLV
                    alucontrol <= 3'b011;
                    shift <= 2'b10;
                end
                6'b000111:begin     //SRAV
                    alucontrol <= 3'b101;
                    shift <= 2'b10;
                end
                default: begin 
                    alucontrol <= 3'b000;
                end
			endcase
		endcase
	
	end
endmodule
