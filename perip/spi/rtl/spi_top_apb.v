// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

parameter ysyx_24120011_SPITOPAPB_IDLE         = 4'd0;
parameter ysyx_24120011_SPITOPAPB_SPI          = 4'd1;
parameter ysyx_24120011_SPITOPAPB_FLASH_DIV    = 4'd2;
parameter ysyx_24120011_SPITOPAPB_FLASH_TXREG0 = 4'd3;
parameter ysyx_24120011_SPITOPAPB_FLASH_TXREG1 = 4'd4;
parameter ysyx_24120011_SPITOPAPB_FLASH_SS1    = 4'd5;
parameter ysyx_24120011_SPITOPAPB_FLASH_CTRL   = 4'd6;
parameter ysyx_24120011_SPITOPAPB_FLASH_WAIT   = 4'd7;
parameter ysyx_24120011_SPITOPAPB_FLASH_SS0    = 4'd8;
parameter ysyx_24120011_SPITOPAPB_FLASH_RECV   = 4'd9;

reg [3:0] spi_top_apb_state;
reg [3:0] spi_top_apb_nextstate;

//in
reg [31:0] reg_in_paddr;
reg [31:0] reg_in_pwdata;
reg [3:0]  reg_in_pstrb;
reg reg_in_pwrite;
reg reg_in_psel;
reg reg_in_penable;
//out
reg [31:0] reg_in_prdata;
reg reg_in_pready;
reg reg_in_pslverr;
reg reg_spi_irq_out;

assign in_pslverr = reg_in_pslverr;
assign spi_irq_out = reg_spi_irq_out;
assign in_pready = (spi_top_apb_state == ysyx_24120011_SPITOPAPB_SPI || spi_top_apb_state == ysyx_24120011_SPITOPAPB_FLASH_RECV) ? reg_in_pready : 'd0;
assign in_prdata = (spi_top_apb_state == ysyx_24120011_SPITOPAPB_SPI) ? reg_in_prdata : (spi_top_apb_state == ysyx_24120011_SPITOPAPB_FLASH_RECV) ? {reg_in_prdata[7:0],reg_in_prdata[15:8],reg_in_prdata[23:16],reg_in_prdata[31:24]}:'d0;

always@(*) begin
  case(spi_top_apb_state)
    ysyx_24120011_SPITOPAPB_IDLE  : begin
      if(in_psel & (in_paddr[31:28] == 4'h1))begin
        reg_in_paddr   = 'd0;
        reg_in_pwdata  = 'd0;
        reg_in_pstrb   = 'd0;
        reg_in_pwrite  = 'd0;
        reg_in_psel    = 'd0;
        reg_in_penable = 'd0;
				spi_top_apb_nextstate	= ysyx_24120011_SPITOPAPB_SPI;
			end
			else if(in_psel & (in_paddr[31:28] == 4'h3))begin
        reg_in_paddr   = 'd0;
        reg_in_pwdata  = 'd0;
        reg_in_pstrb   = 'd0;
        reg_in_pwrite  = 'd0;
        reg_in_psel    = 'd0;
        reg_in_penable = 'd0;
				spi_top_apb_nextstate	= ysyx_24120011_SPITOPAPB_FLASH_DIV;
			end
      else begin
        reg_in_paddr   = 'd0;
        reg_in_pwdata  = 'd0;
        reg_in_pstrb   = 'd0;
        reg_in_pwrite  = 'd0;
        reg_in_psel    = 'd0;
        reg_in_penable = 'd0;
        spi_top_apb_nextstate	= ysyx_24120011_SPITOPAPB_IDLE;
      end
    end
    ysyx_24120011_SPITOPAPB_SPI   : begin
      if(reg_in_pready) begin
        reg_in_paddr   = in_paddr   ;
        reg_in_pwdata  = in_pwdata  ;
        reg_in_pstrb   = in_pstrb   ;
        reg_in_pwrite  = in_pwrite  ;
        reg_in_psel    = in_psel    ;
        reg_in_penable = in_penable ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_IDLE;
      end
      else begin
        reg_in_paddr   = in_paddr   ;
        reg_in_pwdata  = in_pwdata  ;
        reg_in_pstrb   = in_pstrb   ;
        reg_in_pwrite  = in_pwrite  ;
        reg_in_psel    = in_psel    ;
        reg_in_penable = in_penable ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_SPI;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_DIV : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000014   ;
        reg_in_pwdata  =  32'h0000000f   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_TXREG0;
      end
      else begin
        reg_in_paddr   =  32'h00000014   ;
        reg_in_pwdata  =  32'h0000000f   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_DIV;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_TXREG0 : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000000   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_TXREG1;
      end
      else begin
        reg_in_paddr   =  32'h00000000   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_TXREG0;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_TXREG1 : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000004   ;
        reg_in_pwdata  =  {8'h03,in_paddr[23:0]};
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_SS1;
      end
      else begin
        reg_in_paddr   =  32'h00000004   ;
        reg_in_pwdata  =  {8'h03,in_paddr[23:0]};
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_TXREG1;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_SS1 : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000018   ;
        reg_in_pwdata  =  32'h00000001   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_CTRL;
      end
      else begin
        reg_in_paddr   =  32'h00000018   ;
        reg_in_pwdata  =  32'h00000001   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_SS1;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_CTRL : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000010   ;
        reg_in_pwdata  =  32'h00001140   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_WAIT;
      end
      else begin
        reg_in_paddr   =  32'h00000010   ;
        reg_in_pwdata  =  32'h00001140   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_CTRL;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_WAIT : begin
      if(reg_spi_irq_out) begin
        reg_in_paddr   = 'd0             ;
        reg_in_pwdata  = 'd0             ;
        reg_in_pstrb   = 'd0             ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_SS0;
      end
      else begin
        reg_in_paddr   = 'd0             ;
        reg_in_pwdata  = 'd0             ;
        reg_in_pstrb   = 'd0             ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_WAIT;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_SS0 : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000018   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_RECV;
      end
      else begin
        reg_in_paddr   =  32'h00000018   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd1             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_SS0;
      end
    end
    ysyx_24120011_SPITOPAPB_FLASH_RECV : begin
      if(reg_in_pready) begin
        reg_in_paddr   =  32'h00000000   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd0             ;
        reg_in_penable = 'd0             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_IDLE;
      end
      else begin
        reg_in_paddr   =  32'h00000000   ;
        reg_in_pwdata  =  32'h00000000   ;
        reg_in_pstrb   =  4'hf           ;
        reg_in_pwrite  = 'd0             ;
        reg_in_psel    = 'd1             ;
        reg_in_penable = 'd1             ;
        spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_FLASH_RECV;
      end
    end
    default: begin
      reg_in_paddr   = 'd0;
      reg_in_pwdata  = 'd0;
      reg_in_pstrb   = 'd0;
      reg_in_pwrite  = 'd0;
      reg_in_psel    = 'd0;
      reg_in_penable = 'd0;
      spi_top_apb_nextstate = ysyx_24120011_SPITOPAPB_IDLE;
    end
  endcase
end



always@(posedge clock) begin
  if(reset) begin
    spi_top_apb_state <= ysyx_24120011_SPITOPAPB_IDLE;
  end
  else begin
    spi_top_apb_state <= spi_top_apb_nextstate;
  end
end

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(reg_in_paddr[4:0]),
  .wb_dat_i(reg_in_pwdata),
  .wb_dat_o(reg_in_prdata),
  .wb_sel_i(reg_in_pstrb),
  .wb_we_i (reg_in_pwrite),
  .wb_stb_i(reg_in_psel),
  .wb_cyc_i(reg_in_penable),
  .wb_ack_o(reg_in_pready),
  .wb_err_o(reg_in_pslverr),
  .wb_int_o(reg_spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
