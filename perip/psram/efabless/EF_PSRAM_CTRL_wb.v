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

`timescale              1ns/1ps
`default_nettype        none
// 使用 EBH 命令的 PSRAM Wishbone 总线控制器
module EF_PSRAM_CTRL_wb (
    // Wishbone 总线接口信号
    input   wire        clk_i,      // 系统时钟输入
    input   wire        rst_i,      // 系统复位信号，高电平有效
    input   wire [31:0] adr_i,      // 地址输入总线
    input   wire [31:0] dat_i,      // 数据输入总线（主机到从机）
    output  wire [31:0] dat_o,      // 数据输出总线（从机到主机）
    input   wire [3:0]  sel_i,      // 字节选择信号，指示有效的数据字节
    input   wire        cyc_i,      // 总线周期有效信号
    input   wire        stb_i,      // 选通信号，表示有效的总线事务
    output  wire        ack_o,      // 应答信号，表示总线事务完成
    input   wire        we_i,       // 写使能信号，高电平为写操作

    // 到 PSRAM 的外部四线接口
    output  wire            sck,    // 串行时钟输出
    output  wire            ce_n,   // 片选信号，低电平有效
    input   wire [3:0]      din,    // 来自 PSRAM 的 4 位数据输入
    output  wire [3:0]      dout,   // 到 PSRAM 的 4 位数据输出
    output  wire [3:0]      douten  // 数据输出使能信号，控制三态缓冲器
);

    // 状态机的状态定义
    localparam  ST_INIT = 2'd0,     // 初始化状态
                ST_IDLE = 2'd1,     // 空闲状态
                ST_WAIT = 2'd2;     // 等待状态（等待操作完成）

    // 读取模块接口信号
    wire        mr_sck;             // 读取模块的时钟信号
    wire        mr_ce_n;            // 读取模块的片选信号
    wire [3:0]  mr_din;             // 读取模块的数据输入
    wire [3:0]  mr_dout;            // 读取模块的数据输出
    wire        mr_doe;             // 读取模块的数据输出使能

    // 写入模块接口信号
    wire        mw_sck;             // 写入模块的时钟信号
    wire        mw_ce_n;            // 写入模块的片选信号
    wire [3:0]  mw_din;             // 写入模块的数据输入
    wire [3:0]  mw_dout;            // 写入模块的数据输出
    wire        mw_doe;             // 写入模块的数据输出使能

    // 初始化模块控制信号
    reg         init_start;         // 初始化开始信号
    wire        init_done;          // 初始化完成信号
    wire        init_sck;           // 初始化模块的时钟信号
    wire        init_ce_n;          // 初始化模块的片选信号
    wire [3:0]  init_dout;          // 初始化模块的数据输出
    wire        init_doe;           // 初始化模块的数据输出使能

    // PSRAM 读写控制信号
    wire        mr_rd;              // 读取请求信号
    wire        mr_done;            // 读取完成信号
    wire        mw_wr;              // 写入请求信号
    wire        mw_done;            // 写入完成信号

    // Wishbone 总线控制信号解析
    wire        wb_valid = cyc_i & stb_i;    // 总线请求有效
    wire        wb_we = we_i & wb_valid;     // 有效的写请求
    wire        wb_re = ~we_i & wb_valid;    // 有效的读请求

    // 状态机实现
    reg  [1:0]    state, nstate;    // 当前状态和下一状态
    
    // 状态寄存器更新逻辑
    always @ (posedge clk_i or posedge rst_i)
        if(rst_i)
            state <= ST_INIT;       // 复位时进入初始化状态
        else
            state <= nstate;        // 否则更新为下一状态

    // 初始化控制信号生成
    always @(*) begin
        if(state == ST_INIT)
            init_start = 1'b1;      // 在初始化状态下激活初始化启动信号
        else
            init_start = 1'b0;      // 其他状态下禁用初始化启动信号
    end

    // 状态转换逻辑
    always @* begin
        case(state)
            ST_INIT :begin
                if(init_done)
                    nstate = ST_IDLE;   // 初始化完成后进入空闲状态
                else
                    nstate = ST_INIT;   // 否则保持在初始化状态
            end
            ST_IDLE :
                if(wb_valid)
                    nstate = ST_WAIT;   // 收到有效总线请求后进入等待状态
                else
                    nstate = ST_IDLE;   // 否则保持在空闲状态

            ST_WAIT :
                if((mw_done & wb_we) | (mr_done & wb_re))
                    nstate = ST_IDLE;   // 操作完成后返回空闲状态
                else
                    nstate = ST_WAIT;   // 否则继续等待
            default :
                nstate = ST_IDLE;       // 默认情况下进入空闲状态
        endcase
    end

    // 传输大小解码逻辑，基于字节选择信号
    wire [2:0]  size =  (sel_i == 4'b0001) ? 1 :  // 1 字节，第 0 字节
                        (sel_i == 4'b0010) ? 1 :  // 1 字节，第 1 字节
                        (sel_i == 4'b0100) ? 1 :  // 1 字节，第 2 字节
                        (sel_i == 4'b1000) ? 1 :  // 1 字节，第 3 字节
                        (sel_i == 4'b0011) ? 2 :  // 2 字节，第 0-1 字节
                        (sel_i == 4'b1100) ? 2 :  // 2 字节，第 2-3 字节
                        (sel_i == 4'b1111) ? 4 : 4; // 4 字节，全字

    // 写入数据字节重排序逻辑，根据选择信号和传输大小
    // 字节 0 选择逻辑
    wire [7:0]  byte0 = (sel_i[0])          ? dat_i[7:0]   :   // 选择第 0 字节
                        (sel_i[1] & size==1)? dat_i[15:8]  :   // 仅第 1 字节有效时
                        (sel_i[2] & size==1)? dat_i[23:16] :   // 仅第 2 字节有效时
                        (sel_i[3] & size==1)? dat_i[31:24] :   // 仅第 3 字节有效时
                        (sel_i[2] & size==2)? dat_i[23:16] :   // 选择第 2-3 字节时
                        dat_i[7:0];                            // 默认使用原始第 0 字节

    // 字节 1 选择逻辑
    wire [7:0]  byte1 = (sel_i[1])          ? dat_i[15:8]  :   // 选择第 1 字节
                        dat_i[31:24];                          // 默认使用第 3 字节

    // 字节 2 和 3 直接使用
    wire [7:0]  byte2 = dat_i[23:16];     // 第 2 字节
    wire [7:0]  byte3 = dat_i[31:24];     // 第 3 字节

    // 组合重排序后的写入数据
    wire [31:0] wdata = {byte3, byte2, byte1, byte0};

    /*
    // 未使用的地址偏移计算逻辑（被注释掉）
    wire [1:0]  waddr = (size==1 && sel_i[0]==1) ? 2'b00 :
                        (size==1 && sel_i[1]==1) ? 2'b01 :
                        (size==1 && sel_i[2]==1) ? 2'b10 :
                        (size==1 && sel_i[3]==1) ? 2'b11 :
                        (size==2 && sel_i[2]==1) ? 2'b10 :
                        2'b00;
    */

    // 读写控制信号生成
    assign mr_rd = ((state==ST_IDLE) & wb_re);   // 在空闲状态遇到读请求时激活读信号
    assign mw_wr = ((state==ST_IDLE) & wb_we);   // 在空闲状态遇到写请求时激活写信号

    // 实例化 PSRAM 读取模块
    PSRAM_READER MR (
        .clk(clk_i),                     // 系统时钟
        .rst_n(~rst_i),                  // 复位信号（低电平有效）
        .addr({adr_i[23:2],2'b0}),       // 对齐到字边界的地址
        .rd(mr_rd),                      // 读请求信号
        //.size(size),                   // 原本的可变大小读取（已注释）
        .size(3'd4),                     // 固定读取 4 字节（一个字）
        .done(mr_done),                  // 读取完成信号
        .line(dat_o),                    // 读取的数据输出到 Wishbone 总线
        .sck(mr_sck),                    // 串行时钟
        .ce_n(mr_ce_n),                  // 片选信号
        .din(mr_din),                    // 数据输入
        .dout(mr_dout),                  // 数据输出
        .douten(mr_doe)                  // 数据输出使能
    );

    // 实例化 PSRAM 写入模块
    PSRAM_WRITER MW (
        .clk(clk_i),                     // 系统时钟
        .rst_n(~rst_i),                  // 复位信号（低电平有效）
        .addr({adr_i[23:0]}),            // 完整地址
        .wr(mw_wr),                      // 写请求信号
        .size(size),                     // 写入大小（1, 2 或 4 字节）
        .done(mw_done),                  // 写入完成信号
        .line(wdata),                    // 要写入的数据
        .sck(mw_sck),                    // 串行时钟
        .ce_n(mw_ce_n),                  // 片选信号
        .din(mw_din),                    // 数据输入
        .dout(mw_dout),                  // 数据输出
        .douten(mw_doe)                  // 数据输出使能
    );

    // 实例化 PSRAM 初始化模块
    PSRAM_INIT INIT(
        .clk    (clk_i),                 // 系统时钟
        .rst_n  (~rst_i),                // 复位信号（低电平有效）
        .start  (init_start),            // 初始化启动信号
        .done   (init_done),             // 初始化完成信号
        .sck    (init_sck),              // 串行时钟
        .ce_n   (init_ce_n),             // 片选信号
        .dout   (init_dout),             // 数据输出
        .douten (init_doe)               // 数据输出使能
    );

    // PSRAM 物理接口多路复用器（基于当前状态和操作类型）
    // 时钟信号多路复用
    assign sck  = (state == ST_INIT) ? init_sck : wb_we ? mw_sck : mr_sck;
    // 片选信号多路复用
    assign ce_n = (state == ST_INIT) ? init_ce_n : wb_we ? mw_ce_n : mr_ce_n;
    // 数据输出多路复用
    assign dout = (state == ST_INIT) ? init_dout : wb_we ? mw_dout : mr_dout;
    // 输出使能信号多路复用（扩展到 4 位）
    assign douten = (state == ST_INIT) ? {4{init_doe}} : wb_we ? {4{mw_doe}} : {4{mr_doe}};

    // 将外部数据输入连接到相应模块
    assign mw_din = din;                 // 连接到写入模块
    assign mr_din = din;                 // 连接到读取模块
    
    // Wishbone 应答信号生成 - 基于当前操作类型和完成信号
    assign ack_o = wb_we ? mw_done : mr_done;
endmodule


// Using EBH Command
module PSRAM_INIT (
    // External Interface to Quad I/O
    input   wire            clk,
    input   wire            rst_n,
    input                   start,
    output  wire            done,   
    output  reg             sck,
    output  reg             ce_n,
    output  wire [3:0]      dout,
    output  wire            douten
);

wire[7:0]   CMD_35H = 8'h35;
    
reg [7:0]   counter;
always @ (posedge clk or negedge rst_n)
    if(!rst_n)
        sck <= 1'b0;
    else if(~ce_n)
        sck <= ~ sck;
    else 
        sck <= 1'b0;

always @ (posedge clk or negedge rst_n)
    if(!rst_n)
        ce_n <= 1'b1;
    else if(start)
        ce_n <= 1'b0;
    else
        ce_n <= 1'b1;

always @ (posedge clk or negedge rst_n)
    if(!rst_n)
        counter <= 8'b0;
    else if(sck & ~done)
        counter <= counter + 1'b1;
    else if(ce_n)
        counter <= 8'b0;

assign dout   =  (counter < 8)   ?   {3'b0, CMD_35H[7 - counter]}: 4'h0;
assign douten =  1'b1;
assign done   = (counter == 8);

endmodule