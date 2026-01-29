`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/25 18:57:35
// Design Name: 
// Module Name: divider
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


module divider(
    input clk,rst,en,hassign,
    input wire [31:0] a,    //被除数
    input wire [31:0] b,    //除数
    output reg [31:0] q,    //商
    output reg [31:0] r,    //余数
    output reg busy,done,overflow   //结束和忙碌、除零溢出
    );

    // 状态定义
    localparam IDLE = 1'b0;
    localparam CALC = 1'b1;

    wire [32:0] res = {1'b0,s[62:31]} - {1'b0,divisor}; 
    wire [31:0] sign_a = (hassign && a[31]) ? (~a + 1'b1) : a;
    wire [31:0] sign_b = (hassign && b[31]) ? (~b + 1'b1) : b;

    reg state;
    reg [63:0] s;          //存储被除数和商
    reg [31:0] divisor;    //除数
    reg [5:0]cnt;
    reg sign_q,sign_r;

    // CLZ(Leading Zeros Optimization)：计算前导零个数，减少计算周期数
    function [5:0] clz32(input [31:0] val);
        integer i;
        begin
            clz32 = 32;
            for (i = 31; i >= 0; i = i - 1) begin
                if (val[i]) begin
                    clz32 = 31 - i;
                    i = -1; // 找到即跳出
                end
            end
        end
    endfunction

    wire [5:0] clz_a = clz32(sign_a);   
    wire [5:0] clz_b = clz32(sign_b);
    wire [5:0] pre_shift = clz_a - clz_b + 31;

    always @(posedge clk,posedge rst) begin
		if(rst) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
			q <= 32'b0;
            r <= 32'b0;
            cnt <= 32'b0;
            overflow <= 1'b0;
		end else begin
            case(state)
                IDLE: begin
                    // Default in IDLE: not busy.
                    busy <= 1'b0;
                    done <= 1'b0;
                    overflow <= 1'b0;
                    if(en) begin
                        if (b == 0) begin // 除零处理，HI和LO会变成特殊值。
                            q <= 32'hFFFFFFFF;
                            r <= 32'b0;
                            done <= 1'b1;
                            overflow <= 1'b1;
                            busy <= 1'b0;
                            state <= IDLE;
                        end 
                        else if(sign_a < sign_b) begin
                            q <= 32'b0;
                            r <= a; 
                            done <= 1'b1;
                            busy <= 1'b0;
                            state <= IDLE;
                        end
                        else begin
                            sign_q <= hassign ? (a[31] ^ b[31]) : 1'b0;
                            sign_r <= hassign ? a[31] : 1'b0;

                            s <= {32'b0,sign_a} << pre_shift;
                            divisor <= sign_b;

                            cnt <= pre_shift;
                            busy <= 1'b1;
                            state <= CALC;
                        end
                    end
                end

                CALC: begin
                        if (cnt < 32) begin
                            if (res[32]) begin
                                s <= {s[62:0],1'b0};
                            end else begin
                                s <= {res[31:0],s[30:0],1'b1}; 
                            end
                            cnt <= cnt + 1'b1;
                        end 
                        else begin  // 因为非阻塞赋值的缘故，最好不要再这里判断第32次，否则商和余数很可能是旧值
                            q <= (sign_q) ? (~s[31:0] + 1'b1) : s[31:0];
                            r <= (sign_r) ? (~s[63:32] + 1'b1) : s[63:32];
                            done <= 1'b1;
                            busy <= 1'b0;
                            state <= IDLE;
                        end
                    end
            endcase
         
		end
	end

endmodule
