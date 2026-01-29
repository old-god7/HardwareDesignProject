`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2017/11/02 14:52:16
// Design Name: 
// Module Name: alu
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


module alu(
	input wire[31:0] a,b,
	input wire[2:0] op,
	input wire hassign, //判断是不是有符号的计算
	input wire shift,
	output reg[31:0] y,
	output reg[31:0] y_lo, //做乘除法时需要用到，结果的低32位
	output reg overflow,
	output wire zero
    );

	wire[31:0] s,bout;
	assign bout = op[2] ? ~b : b;
	assign s = a + bout + op[2];
	always @(*) begin
		y_lo <= 32'b0;
		case (op)
			3'b000:begin		//slt
				// SLT/SLTU must not raise overflow; implement with explicit signed/unsigned compare.
				if (hassign) begin
					y <= ($signed(a) < $signed(b)) ? 32'h1 : 32'h0;
				end else begin
					y <= (a < b) ? 32'h1 : 32'h0;
				end
			end

			3'b010: begin
				y <= s;			//add
			end

			3'b100: begin      	//mult
				if(hassign) begin
					{y,y_lo} <= $signed(a) * $signed(b);
				end
				else begin
					{y,y_lo} <= {32'b0, a} * {32'b0, b};
				end
            end
			
            3'b110: begin
				y <= s;			//sub
			end

            3'b001: begin
				if(shift) begin
					y <= b << a[4:0]; // SLL (a 传入 shamt)
				end
				else begin
					y <= a | bout;	//or
				end
			end

			3'b011: begin		
				if(shift) begin
					y <= b >> a[4:0];	// SRL
				end
				else begin
					y <= a & bout;	//and
				end
			end

			3'b101: begin	
				if(shift) begin
					y <= $signed(b) >>> a[4:0]; // SRA (算术右移)
				end	
				else begin
					y <= ~(a | b);//nor
				end
			end

			3'b111: begin		//xor
				y <= a ^ b;
			end
		endcase	
	end
	
	assign zero = (y == 32'b0);

	always @(*) begin
		case (op)
			3'b010:overflow <= a[31] & b[31] & ~s[31] |
							~a[31] & ~b[31] & s[31];
			3'b110:overflow <= ~a[31] & b[31] & s[31] |
							a[31] & ~b[31] & ~s[31];
			default : overflow <= 1'b0;
		endcase	
	end
endmodule
