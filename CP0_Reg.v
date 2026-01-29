`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: CP0_Reg
// Description: CP0协处理器寄存器 - 按A03规范实现必要寄存器语义
//////////////////////////////////////////////////////////////////////////////////

module CP0_Reg (
    input         clk,
    input         rst,

    // 读写接口 (MFC0/MTC0指令)
    input         we,          // 写使能 <- MTC0
    input  [4:0]  waddr,       // 写寄存器地址 (MTC0: rd)
    input  [4:0]  raddr,       // 读寄存器地址 (MFC0: rd)
    input  [31:0] wdata,       // 写入数据
    output reg [31:0] rdata,       // 读取数据 -> MFC0

    // 异常/中断接口（由流水线/控制逻辑产生；成员3仅实现CP0本体，不在此做译码/优先级）
    input         exc_valid_i,        // 本拍开始响应例外/中断
    input  [4:0]  exc_code_i,         // ExcCode (见A03表6-5)
    input  [31:0] pc_i,               // 触发例外的指令PC（若在延迟槽，为延迟槽指令PC）
    input         in_delay_slot_i,    // 触发例外的指令是否在分支延迟槽
    input  [31:0] badvaddr_i,         // 触发地址错例外的虚地址（AdEL/AdES）
    input         eret_i,             // 执行ERET：Status.EXL清0
    input  [5:0]  hw_int_i,           // 外部硬件中断输入 HW5..HW0 -> Cause.IP7..IP2

    // 常用输出（便于后续集成）
    output [31:0] epc_o,              // EPC寄存器值
    output        exl_o,              // Status.EXL
    output [31:0] status_o,           // Status寄存器（含Bev/IM/EXL/IE）
    output [31:0] cause_o,            // Cause寄存器（含BD/IP/ExcCode）
    output [31:0] badvaddr_o          // BadVAddr寄存器
);

    // CP0寄存器地址 (来自3-4对接_1.md)
    localparam ADDR_BADVADDR = 5'd8;   // BadVAddr - 错误虚拟地址
    localparam ADDR_COUNT    = 5'd9;   // Count - 计数器
    localparam ADDR_STATUS   = 5'd12;  // Status - 状态寄存器
    localparam ADDR_CAUSE    = 5'd13;  // Cause - 异常原因
    localparam ADDR_EPC      = 5'd14;  // EPC - 异常程序计数器

    // ExcCode 常量（A03表6-5）
    localparam [4:0] EXC_INT  = 5'h00;
    localparam [4:0] EXC_ADEL = 5'h04;
    localparam [4:0] EXC_ADES = 5'h05;
    localparam [4:0] EXC_SYS  = 5'h08;
    localparam [4:0] EXC_BP   = 5'h09;
    localparam [4:0] EXC_RI   = 5'h0a;
    localparam [4:0] EXC_OV   = 5'h0c;

    // Status: Bev恒为1（A03要求），IM[15:8]/EXL/IE可读写
    reg [7:0]  status_im_reg;
    reg        status_exl_reg;
    reg        status_ie_reg;

    wire [31:0] status_packed = {
        9'b0,            // [31:23] 0
        1'b1,            // [22] Bev 固定为1
        6'b0,            // [21:16] 0
        status_im_reg,   // [15:8] IM7..IM0
        6'b0,            // [7:2] 0
        status_exl_reg,  // [1] EXL
        status_ie_reg    // [0] IE
    };

    // EPC寄存器
    reg [31:0] epc_reg;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            epc_reg <= 32'd0;
        end else if (exc_valid_i && (status_exl_reg == 1'b0)) begin
            epc_reg <= in_delay_slot_i ? (pc_i - 32'd4) : pc_i;
        end else if (we && waddr == ADDR_EPC) begin
            epc_reg <= wdata;  // MTC0手动写EPC
        end
    end

    // Cause: BD/IP/ExcCode（仅IP1..IP0可由软件写）
    reg        cause_bd_reg;
    reg [1:0]  cause_sw_ip_reg;  // IP1..IP0
    reg [4:0]  cause_exccode_reg;

    wire [7:0] cause_ip = {hw_int_i, cause_sw_ip_reg}; // IP7..IP2=HW5..HW0, IP1..IP0=软件中断
    wire [31:0] cause_packed = {
        cause_bd_reg,     // [31] BD
        1'b0,             // [30] TI (未实现Compare/定时器)
        14'b0,            // [29:16] 0
        cause_ip,         // [15:8] IP7..IP0
        1'b0,             // [7] 0
        cause_exccode_reg,// [6:2] ExcCode
        2'b00             // [1:0] 0
    };

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cause_bd_reg <= 1'b0;
            cause_sw_ip_reg <= 2'b00;
            cause_exccode_reg <= 5'd0;
        end else begin
            // 软件仅允许写Cause.IP[1:0]
            if (we && waddr == ADDR_CAUSE) begin
                cause_sw_ip_reg <= wdata[9:8];
            end

            // 仅在EXL=0时更新BD/ExcCode（A03 5.1.3/6.4）
            if (exc_valid_i && (status_exl_reg == 1'b0)) begin
                cause_bd_reg <= in_delay_slot_i;
                cause_exccode_reg <= exc_code_i;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            status_im_reg <= 8'd0;
            status_exl_reg <= 1'b0;
            status_ie_reg <= 1'b0;
        end else begin
            // 例外入口：EXL置1（A03 5.1.3）
            if (exc_valid_i && (status_exl_reg == 1'b0)) begin
                status_exl_reg <= 1'b1;
            end

            // ERET：EXL清0（A03 3.10.1/5.1.3）
            if (eret_i) begin
                status_exl_reg <= 1'b0;
            end

            // 软件写Status（Bev恒1，其他域只接收IM/EXL/IE）
            if (we && waddr == ADDR_STATUS) begin
                status_im_reg <= wdata[15:8];
                status_exl_reg <= wdata[1];
                status_ie_reg <= wdata[0];
            end
        end
    end

    // Count寄存器：每两个CPU Clock自增1（A03 6.3）
    reg [31:0] count_reg;
    reg count_tick;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count_reg <= 32'd0;
            count_tick <= 1'b0;
        end else if (we && waddr == ADDR_COUNT) begin
            count_reg <= wdata;
        end else begin
            count_tick <= ~count_tick;
            if (count_tick) begin
                count_reg <= count_reg + 32'd1;
            end
        end
    end

    // BadVAddr寄存器：仅在AdEL/AdES触发时更新（A03 5.1.5/6.2）
    reg [31:0] badvaddr_reg;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            badvaddr_reg <= 32'd0;
        end else if (exc_valid_i && (status_exl_reg == 1'b0) &&
                     ((exc_code_i == EXC_ADEL) || (exc_code_i == EXC_ADES))) begin
            badvaddr_reg <= badvaddr_i;
        end
    end

    // 读数据多路选择 (MFC0)
    always @(*) begin
        case (raddr)
            ADDR_BADVADDR: rdata = badvaddr_reg;
            ADDR_COUNT:    rdata = count_reg;
            ADDR_STATUS:   rdata = status_packed;
            ADDR_CAUSE:    rdata = cause_packed;
            ADDR_EPC:      rdata = epc_reg;
            default:       rdata = 32'd0;
        endcase
    end

    assign epc_o = epc_reg;
    assign exl_o = status_exl_reg;
    assign status_o = status_packed;
    assign cause_o = cause_packed;
    assign badvaddr_o = badvaddr_reg;

endmodule
