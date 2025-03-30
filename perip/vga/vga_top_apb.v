module vga_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  wire [9:0] h_addr;
  wire [10:0] v_addr;
  wire [23:0] vga_data;
  reg  [23:0] vga_mem [2**21-1:0];

  assign vga_data = vga_mem[{h_addr, v_addr}];
  assign in_pready = in_psel & in_penable;
  
  always@(posedge clock) begin
    if(reset) begin
      //$readmemh("/home/plutoisy/ysyx-workbench/nvboard/example/resource/picture.hex", vga_mem);
    end
    else begin
      if(in_pready & in_pwrite) begin//写
        vga_mem[in_paddr[22:2]][7:0]    <= in_pstrb[0] ? in_pwdata[7:0]   : 'b0;
        vga_mem[in_paddr[22:2]][15:8]   <= in_pstrb[1] ? in_pwdata[15:8]  : 'b0;
        vga_mem[in_paddr[22:2]][23:16]  <= in_pstrb[2] ? in_pwdata[23:16] : 'b0;
      end
    end
  end

  vga_ctrl my_vga_ctrl(
      .pclk(clock),
      .reset(reset),
      .vga_data(vga_data),
      .h_addr(h_addr),
      .v_addr(v_addr),
      .hsync(vga_hsync),
      .vsync(vga_vsync),
      .valid(vga_valid),
      .vga_r(vga_r),
      .vga_g(vga_g),
      .vga_b(vga_b)
  );


endmodule

module vga_ctrl (
    input pclk,
    input reset,
    input [23:0] vga_data,
    output [9:0] h_addr,
    output [10:0] v_addr,
    output hsync,
    output vsync,
    output valid,
    output [7:0] vga_r,
    output [7:0] vga_g,
    output [7:0] vga_b
);

parameter h_frontporch = 96/2;
parameter h_active = 144/2;
parameter h_backporch = 784/2;
parameter h_total = 800/2;

parameter v_frontporch = 2;
parameter v_active = 35;
parameter v_backporch = 515;
parameter v_total = 525;

reg [9:0] x_cnt;
reg [10:0] y_cnt;
wire h_valid;
wire v_valid;

always @(posedge pclk) begin
    if(reset == 1'b1) begin
        x_cnt <= 1;
        y_cnt <= 1;
    end
    else begin
        if(x_cnt == h_total)begin
            x_cnt <= 1;
            if(y_cnt == v_total) y_cnt <= 1;
            else y_cnt <= y_cnt + 1;
        end
        else x_cnt <= x_cnt + 1;
    end
end

//生成同步信号    
assign hsync = (x_cnt > h_frontporch);
assign vsync = (y_cnt > v_frontporch);
//生成消隐信号
assign h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
assign v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
assign valid = h_valid & v_valid;
//计算当前有效像素坐标
assign h_addr = h_valid ? (x_cnt - 10'd73) : 10'd0;
assign v_addr = v_valid ? (y_cnt - 11'd36) : 11'd0;
//设置输出的颜色值
assign {vga_r, vga_g, vga_b} = vga_data;

endmodule