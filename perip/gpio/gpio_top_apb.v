module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);
  reg [15:0] reg_gpio_out;
  reg [31:0] reg_in_prdata;
  reg [3:0]  reg_gpio_seg_hex_0;
  reg [3:0]  reg_gpio_seg_hex_1;
  reg [3:0]  reg_gpio_seg_hex_2;
  reg [3:0]  reg_gpio_seg_hex_3;
  reg [3:0]  reg_gpio_seg_hex_4;
  reg [3:0]  reg_gpio_seg_hex_5;
  reg [3:0]  reg_gpio_seg_hex_6;
  reg [3:0]  reg_gpio_seg_hex_7;

  assign in_pready = in_psel & in_penable;
  assign gpio_out  = reg_gpio_out;
  assign in_prdata = reg_in_prdata;

  bcd7seg u_bcd7seg0(
      .b  ( reg_gpio_seg_hex_0  ),
      .h  ( gpio_seg_0          )
  );
  bcd7seg u_bcd7seg1(
      .b  ( reg_gpio_seg_hex_1  ),
      .h  ( gpio_seg_1          )
  );
  bcd7seg u_bcd7seg2(
      .b  ( reg_gpio_seg_hex_2  ),
      .h  ( gpio_seg_2          )
  );
  bcd7seg u_bcd7seg3(
      .b  ( reg_gpio_seg_hex_3  ),
      .h  ( gpio_seg_3          )
  );
  bcd7seg u_bcd7seg4(
      .b  ( reg_gpio_seg_hex_4  ),
      .h  ( gpio_seg_4          )
  );
  bcd7seg u_bcd7seg5(
      .b  ( reg_gpio_seg_hex_5  ),
      .h  ( gpio_seg_5          )
  );
  bcd7seg u_bcd7seg6(
      .b  ( reg_gpio_seg_hex_6  ),
      .h  ( gpio_seg_6          )
  );
  bcd7seg u_bcd7seg7(
      .b  ( reg_gpio_seg_hex_7  ),
      .h  ( gpio_seg_7          )
  );

  always@(posedge clock) begin
    if(reset) begin
      reg_gpio_out       <= 'b0;
      reg_in_prdata      <= 'b0;
      reg_gpio_seg_hex_0 <= 'b0;
      reg_gpio_seg_hex_1 <= 'b0;
      reg_gpio_seg_hex_2 <= 'b0;
      reg_gpio_seg_hex_3 <= 'b0;
      reg_gpio_seg_hex_4 <= 'b0;
      reg_gpio_seg_hex_5 <= 'b0;
      reg_gpio_seg_hex_6 <= 'b0;
      reg_gpio_seg_hex_7 <= 'b0;
    end
    else begin
      if(in_pready & in_pwrite) begin//写
        if(in_paddr[3:2] == 2'b00) begin
          reg_gpio_out[7:0]  <= in_pstrb[0] ? in_pwdata[7:0]  : 'b0;
          reg_gpio_out[15:8] <= in_pstrb[1] ? in_pwdata[15:8] : 'b0;
        end
        else if(in_paddr[3:2] == 2'b10) begin
          reg_gpio_seg_hex_0  <= in_pstrb[0] ? in_pwdata[3:0]    : 'b0;
          reg_gpio_seg_hex_1  <= in_pstrb[0] ? in_pwdata[7:4]    : 'b0;
          reg_gpio_seg_hex_2  <= in_pstrb[1] ? in_pwdata[11:8]   : 'b0;
          reg_gpio_seg_hex_3  <= in_pstrb[1] ? in_pwdata[15:12]  : 'b0;
          reg_gpio_seg_hex_4  <= in_pstrb[2] ? in_pwdata[19:16]  : 'b0;
          reg_gpio_seg_hex_5  <= in_pstrb[2] ? in_pwdata[23:20]  : 'b0;
          reg_gpio_seg_hex_6  <= in_pstrb[3] ? in_pwdata[27:24]  : 'b0;
          reg_gpio_seg_hex_7  <= in_pstrb[3] ? in_pwdata[31:28]  : 'b0;
        end
      end
      else if(in_pready & !in_pwrite) begin//读
        if(in_paddr[3:2] == 2'b01) begin
          reg_in_prdata <= {16'b0, gpio_in};
        end
      end
    end
  end
endmodule

module bcd7seg(
  input  [3:0] b,
  output reg [7:0] h
);
always@(*) begin
  case(b)
    4'b0000: h = 8'b00000011;//0
    4'b0001: h = 8'b10011111;//1
    4'b0010: h = 8'b00100101;//2
    4'b0011: h = 8'b00001101;//3
    4'b0100: h = 8'b10011001;//4
    4'b0101: h = 8'b01001001;//5
    4'b0110: h = 8'b01000001;//6
    4'b0111: h = 8'b00011111;//7
    4'b1000: h = 8'b00000001;//8
    4'b1001: h = 8'b00001001;//9
    4'b1010: h = 8'b00010001;//a
    4'b1011: h = 8'b11000001;//b
    4'b1100: h = 8'b01100011;//c
    4'b1101: h = 8'b10000101;//d
    4'b1110: h = 8'b01100001;//e
    4'b1111: h = 8'b01110001;//f
  endcase
end

endmodule