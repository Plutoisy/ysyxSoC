module psram(
  input sck,        // 串行时钟输入
  input ce_n,       // 片选信号，低电平有效
  inout [3:0] dio   // 4位双向数据线，支持SPI和QPI模式
);
  // 命令定义
  `define RCMD 8'hEB    // 读取命令 (0xEB)
  `define WCMD 8'h38    // 写入命令 (0x38)
  `define QPICMD 8'h35  // 进入QPI模式命令 (0x35)

  // 双向数据线控制信号
  wire [3:0] dout_en;   // 输出使能信号
  wire [3:0] dout;      // 输出数据
  wire [3:0] din;       // 输入数据
  assign din = dio;     // 从双向总线获取输入数据

  // 生成双向IO控制逻辑
  genvar i;
  generate
    for(i=0; i<4; i=i+1) begin
      assign dio[i] = dout_en[i] ? dout[i] : 1'bz; // 三态控制
    end
  endgenerate

  // 工作模式标志
  reg QPI_MODE = 0;     // QPI模式标志，默认为SPI模式

  // 内部寄存器
  reg [7:0] cmd;        // 命令寄存器
  reg [23:0] addr;      // 地址寄存器
  reg [31:0] data;      // 数据寄存器
  wire [31:0] rdata;    // 读取数据寄存器
  reg [7:0] counter;    // 计数器，用于状态控制
  reg [3:0] state;      // 当前状态

  // 状态定义
  typedef enum [3:0] { 
    cmd_t,    // 命令接收状态
    addr_t,   // 地址接收状态
    data_t,   // 数据传输状态
    delay_t,  // 延迟状态（读操作前的延迟）
    err_t     // 错误状态
  } state_t;

  // QPI模式设置逻辑
  always @(posedge ce_n) begin
    if(cmd == `QPICMD) begin
      QPI_MODE <= 1;    // 检测到QPI命令时，设置QPI模式
    end
  end

  // 状态机控制逻辑
  always @(posedge sck or posedge ce_n) begin
    if(ce_n) begin
      // 片选无效时，复位状态
      counter <= 'd0;
      state   <= cmd_t;
    end
    else begin
      case(state)
        cmd_t: begin
          // 命令接收状态
          if(QPI_MODE) begin
            // QPI模式下，2个时钟周期接收完8位命令
            counter <= (counter < 8'd1) ? counter + 8'd1 : 8'd0;
            state <= (counter == 8'd1) ? addr_t : state;
          end
          else begin
            // SPI模式下，8个时钟周期接收完8位命令
            counter <= (counter < 8'd7) ? counter + 8'd1 : 8'd0;
            state <= (counter == 8'd7) ? addr_t : state;
          end
        end
        
        addr_t: begin
          // 地址接收状态 - 接收24位地址（6个QPI周期）
          counter <= (counter < 8'd5) ? counter + 8'd1 : 8'd0;
          // 根据命令类型决定下一个状态
          state  <= (counter == 8'd5) ? 
                    (cmd == `RCMD ? delay_t : (cmd == `WCMD ? data_t : err_t)) : state;
        end
        
        data_t: begin
          // 数据传输状态
          counter <= counter + 8'd1;
          state <= state;  // 保持在数据传输状态
        end
        
        delay_t: begin
          // 读操作的延迟状态
          counter <= (counter < 8'd6) ? counter + 8'd1 : 8'd0;
          state  <= (counter == 8'd6) ? data_t : state;
        end
        
        default: begin
          // 错误状态 - 不支持的命令
          state <= state;
          $fwrite(32'h80000002, "Assertion failed: Unsupported command `%xh`, only support `EBh,38H` read command\n", cmd);
          $fatal;
        end
      endcase
    end
  end

  // 命令接收逻辑
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      cmd <= 8'd0;  // 复位命令寄存器
    end
    else if (state == cmd_t) begin
      if(QPI_MODE) begin
        // QPI模式下，每次接收4位
        cmd <= {cmd[3:0], din[3:0]};
      end
      else begin
        // SPI模式下，每次接收1位
        cmd <= {cmd[6:0], din[0]};
      end
    end 
  end

  // 地址接收逻辑
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      addr <= 24'd0;  // 复位地址寄存器
    end
    else if (state == addr_t && counter < 8'd6) begin
      // 在地址状态下，每个时钟接收4位地址数据
      addr <= {addr[19:0], din[3:0]};
    end
  end

  // 数据字节交换（大小端转换）
  wire [31:0] data_bswap = {rdata[7:0], rdata[15:8], rdata[23:16], rdata[31:24]};
  
  // 数据处理逻辑
  always @(posedge sck or posedge ce_n) begin
    if (ce_n) begin
      data <= 32'd0;  // 复位数据寄存器
    end
    else if (state == data_t && cmd == `RCMD) begin
      // 读操作：移出数据
      data <= {
        {counter == 8'd0 ? data_bswap : data}[27:0], 
        4'b0000
      };
    end
    else if (state == data_t && cmd == `WCMD) begin
      // 写操作：移入数据
      data <= {data[27:0], din[3:0]};
    end
  end
  
  // 输出数据控制
  assign dout = {(state == data_t && counter == 8'd0) ? data_bswap : data}[31:28];
  
  // 输出使能控制 - 只在读操作的数据和延迟阶段启用
  assign dout_en = (state == data_t | state == delay_t) && cmd == `RCMD ? 4'b1111 : 4'd0;

  // DPI-C 外部函数声明，用于与C/C++代码交互
  import "DPI-C" function void psram_read(input int addr, output int data);
  import "DPI-C" function void psram_write(input int addr, input int data, input int mask);

  // 数据字节交换（用于写操作）
  wire [31:0] wdata = {data[7:0], data[15:8], data[23:16], data[31:24]};

  // 读操作处理
  always @(posedge sck) begin
    if((state == delay_t) && (counter == 8'd0) && (cmd == `RCMD)) begin
      // 在延迟状态开始时调用外部读函数
      psram_read({8'd0, addr}, rdata);
    end
  end
  
  // 写操作处理
  always @(posedge ce_n) begin
    if(cmd == `WCMD) begin
      // 在片选结束时执行写操作
      psram_write({8'd0, addr}, wdata, {24'd0, counter});
    end
  end
endmodule
