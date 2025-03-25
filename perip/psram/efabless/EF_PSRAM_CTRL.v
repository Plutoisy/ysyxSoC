/*
	Copyright 2020 Efabless Corp.

	Author: Mohamed Shalan (mshalan@efabless.com)

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at:
	http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
*/
/*
    QSPI PSRAM Controller

    Pseudostatic RAM (PSRAM) is DRAM combined with a self-refresh circuit.
    It appears externally as slower SRAM, albeit with a density/cost advantage
    over true SRAM, and without the access complexity of DRAM.

    The controller was designed after https://www.issi.com/WW/pdf/66-67WVS4M8ALL-BLL.pdf
    utilizing both EBh and 38h commands for reading and writting.

    Benchmark data collected using CM0 CPU when memory is PSRAM only

        Benchmark       PSRAM (us)  1-cycle SRAM (us)   Slow-down
        ---------       ----------  -----------------   ---------
        xtea            840         212                 3.94
        stress          1607        446                 3.6
        hash            5340        1281                4.16
        chacha          2814        320                 8.8
        aes sbox        2370        322                 7.3
        nqueens         3496        459                 7.6
        mtrans          2171        2034                1.06
        rle             903         155                 5.8
        prime           549         97                  5.66
*/

`timescale              1ns/1ps
`default_nettype        none

module PSRAM_READER (
    // 系统接口
    input   wire            clk,        // 系统时钟
    input   wire            rst_n,      // 低电平有效的复位信号
    input   wire [23:0]     addr,       // 要读取的PSRAM地址
    input   wire            rd,         // 读取请求信号，高电平有效
    input   wire [2:0]      size,       // 读取大小控制（影响读取的字节数）
    output  wire            done,       // 读取完成指示信号
    output  wire [31:0]     line,       // 读取的32位数据输出

    // PSRAM物理接口
    output  reg             sck,        // PSRAM串行时钟
    output  reg             ce_n,       // PSRAM片选信号，低电平有效
    input   wire [3:0]      din,        // 从PSRAM接收的4位数据
    output  wire [3:0]      dout,       // 发送到PSRAM的4位数据
    output  wire            douten      // 输出使能信号，控制数据方向
);

    // 状态机状态定义
    localparam  IDLE = 1'b0,            // 空闲状态
                READ = 1'b1;            // 读取状态

    // 根据size计算最终计数值，决定读取多少数据
    // 13是基础开销（命令+地址等），size*2表示每增加1的size值，需要额外2个时钟周期
    wire [7:0]  FINAL_COUNT = 13 + size*2; 

    // 内部寄存器
    reg         state, nstate;          // 当前状态和下一状态
    reg [7:0]   counter;                // 操作计数器，用于跟踪当前操作阶段
    reg [23:0]  saddr;                  // 存储读取地址
    reg [7:0]   data [3:0];             // 存储接收到的数据，4个字节

    // PSRAM读取命令：0xEB (Fast Read Quad I/O)
    wire[7:0]   CMD_EBH = 8'heb;

    // 状态机下一状态逻辑
    always @*
        case (state)
            IDLE: if(rd) nstate = READ; else nstate = IDLE;  // 收到读请求时进入READ状态
            READ: if(done) nstate = IDLE; else nstate = READ; // 读取完成时返回IDLE状态
        endcase

    // 状态寄存器更新
    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;       // 复位时进入IDLE状态
        else state <= nstate;           // 否则更新为下一状态

    // 生成PSRAM串行时钟(sck)，频率为系统时钟的一半
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;                // 复位时sck为低
        else if(~ce_n)                  // 当片选有效时
            sck <= ~ sck;               // 每个系统时钟周期翻转sck
        else if(state == IDLE)
            sck <= 1'b0;                // 空闲状态时sck保持低电平

    // 片选信号(ce_n)控制逻辑
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;               // 复位时禁用片选
        else if(state == READ)
            ce_n <= 1'b0;               // 读取状态时启用片选
        else
            ce_n <= 1'b1;               // 其他状态禁用片选

    // 计数器控制，用于跟踪操作进度
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'b0;            // 复位时清零计数器
        else if(sck & ~done)            // 在sck上升沿且未完成时
            counter <= counter + 1'b1;  // 计数器加1
        else if(state == IDLE)
            counter <= 8'b0;            // 空闲状态时清零计数器

    // 地址寄存器更新
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;             // 复位时清零地址
        else if((state == IDLE) && rd)  // 空闲状态收到读请求时
            saddr <= {addr[23:0]};      // 保存读取地址

    // 计算当前接收的数据应该存储在哪个字节位置
    wire[1:0] byte_index = {counter[7:1] - 8'd3}[1:0];
    
    // 在sck上升沿采样数据（从计数器值14开始接收数据）
    always @ (posedge clk)
        if(counter >= 14 && counter <= FINAL_COUNT)
            if(sck)
                // 将接收到的4位数据移入对应字节的寄存器
                data[byte_index] <= {data[byte_index][3:0], din};

    // 输出数据多路复用器，根据计数器值决定输出什么数据
    assign dout     =   (counter == 0)  ?   CMD_EBH[7:4]        : // 命令高4位
                        (counter == 1)  ?   CMD_EBH[3:0]        : // 命令低4位
                        (counter == 2)  ?   saddr[23:20]        : // 地址[23:20]
                        (counter == 3)  ?   saddr[19:16]        : // 地址[19:16]
                        (counter == 4)  ?   saddr[15:12]        : // 地址[15:12]
                        (counter == 5)  ?   saddr[11:8]         : // 地址[11:8]
                        (counter == 6)  ?   saddr[7:4]          : // 地址[7:4]
                        (counter == 7)  ?   saddr[3:0]          : // 地址[3:0]
                        4'h0;                                     // 其他情况输出0

    // 输出使能控制，仅在发送命令和地址时启用（前8个周期）
    assign douten   = (counter < 8);

    // 完成信号，当计数器达到最终值加1时表示操作完成
    assign done     = (counter == FINAL_COUNT+1);

    // 将4个8位数据字节组合成32位输出
    generate
        genvar i;
        for(i=0; i<4; i=i+1)
            assign line[i*8+7: i*8] = data[i];
    endgenerate

endmodule


// Using 38H Command
// 使用0x38命令的PSRAM写入器
module PSRAM_WRITER (
    // 系统接口
    input   wire            clk,        // 系统时钟
    input   wire            rst_n,      // 低电平有效的复位信号
    input   wire [23:0]     addr,       // 要写入的PSRAM地址
    input   wire [31: 0]    line,       // 要写入的32位数据
    input   wire [2:0]      size,       // 写入大小控制（影响写入的字节数）
    input   wire            wr,         // 写入请求信号，高电平有效
    output  wire            done,       // 写入完成指示信号

    // PSRAM物理接口
    output  reg             sck,        // PSRAM串行时钟
    output  reg             ce_n,       // PSRAM片选信号，低电平有效
    input   wire [3:0]      din,        // 从PSRAM接收的4位数据（写入时通常不使用）
    output  wire [3:0]      dout,       // 发送到PSRAM的4位数据
    output  wire            douten      // 输出使能信号，控制数据方向
);
    // 状态机状态定义
    localparam  IDLE = 1'b0,            // 空闲状态
                WRITE = 1'b1;           // 写入状态

    // 根据size计算最终计数值，决定写入多少数据
    // 7是基础开销（命令+地址），size*2表示每增加1的size值，需要额外2个时钟周期
    wire[7:0]        FINAL_COUNT = 7 + size*2;

    // 内部寄存器
    reg         state, nstate;          // 当前状态和下一状态
    reg [7:0]   counter;                // 操作计数器，用于跟踪当前操作阶段
    reg [23:0]  saddr;                  // 存储写入地址

    // PSRAM写入命令：0x38 (Quad Write)
    wire[7:0]   CMD_38H = 8'h38;

    // 状态机下一状态逻辑
    always @*
        case (state)
            IDLE: if(wr) nstate = WRITE; else nstate = IDLE;    // 收到写请求时进入WRITE状态
            WRITE: if(done) nstate = IDLE; else nstate = WRITE; // 写入完成时返回IDLE状态
        endcase

    // 状态寄存器更新
    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;       // 复位时进入IDLE状态
        else state <= nstate;           // 否则更新为下一状态

    // 生成PSRAM串行时钟(sck)，频率为系统时钟的一半
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;                // 复位时sck为低
        else if(~ce_n)                  // 当片选有效时
            sck <= ~ sck;               // 每个系统时钟周期翻转sck
        else if(state == IDLE)
            sck <= 1'b0;                // 空闲状态时sck保持低电平

    // 片选信号(ce_n)控制逻辑
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;               // 复位时禁用片选
        else if(state == WRITE)
            ce_n <= 1'b0;               // 写入状态时启用片选
        else
            ce_n <= 1'b1;               // 其他状态禁用片选

    // 计数器控制，用于跟踪操作进度
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'b0;            // 复位时清零计数器
        else if(sck & ~done)            // 在sck上升沿且未完成时
            counter <= counter + 1'b1;  // 计数器加1
        else if(state == IDLE)
            counter <= 8'b0;            // 空闲状态时清零计数器

    // 地址寄存器更新
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;             // 复位时清零地址
        else if((state == IDLE) && wr)  // 空闲状态收到写请求时
            saddr <= addr;              // 保存写入地址

    // 输出数据多路复用器，根据计数器值决定输出什么数据
    assign dout     =   (counter == 0)  ?   CMD_38H[7:4]        : // 命令高4位
                        (counter == 1)  ?   CMD_38H[3:0]        : // 命令低4位
                        (counter == 2)  ?   saddr[23:20]        : // 地址[23:20]
                        (counter == 3)  ?   saddr[19:16]        : // 地址[19:16]
                        (counter == 4)  ?   saddr[15:12]        : // 地址[15:12]
                        (counter == 5)  ?   saddr[11:8]         : // 地址[11:8]
                        (counter == 6)  ?   saddr[7:4]          : // 地址[7:4]
                        (counter == 7)  ?   saddr[3:0]          : // 地址[3:0]
                        (counter == 8)  ?   line[7:4]           : // 数据字节0高4位
                        (counter == 9)  ?   line[3:0]           : // 数据字节0低4位
                        (counter == 10) ?   line[15:12]         : // 数据字节1高4位
                        (counter == 11) ?   line[11:8]          : // 数据字节1低4位
                        (counter == 12) ?   line[23:20]         : // 数据字节2高4位
                        (counter == 13) ?   line[19:16]         : // 数据字节2低4位
                        (counter == 14) ?   line[31:28]         : // 数据字节3高4位
                        line[27:24];                              // 数据字节3低4位

    // 输出使能控制，在整个写入过程中都保持启用
    assign douten   = (~ce_n);

    // 完成信号，当计数器达到最终值加1时表示操作完成
    assign done     = (counter == FINAL_COUNT + 1);

endmodule
