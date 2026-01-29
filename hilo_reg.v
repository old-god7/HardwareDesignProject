`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/23 19:21:46
// Design Name: 
// Module Name: hilo_reg
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


module hilo_reg(
    input wire clk,rst,wediv,
    input wire [1:0] we,
    input wire [31:0] hi_in,
    input wire [31:0] lo_in,
    output reg [31:0] hi_out,
    output reg [31:0] lo_out
    );

    always @(posedge clk,posedge rst) begin
		if(rst) begin
			hi_out <= 32'b0;
            lo_out <= 32'b0;
		end 
        else if(we == 2'b01 || wediv) begin
			hi_out <= hi_in;
            lo_out <= lo_in;
		end
        else if(we == 2'b11) begin
            hi_out <= hi_in;
        end
        else if(we == 2'b10) begin
            lo_out <= lo_in;
        end
	end

endmodule
