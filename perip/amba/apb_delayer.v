module apb_delayer(
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

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);
  parameter ysyx_24120011_APB_DELAYER_IDLE  = 3'b000;
  parameter ysyx_24120011_APB_DELAYER_WAIT_READY = 3'b001;
  parameter ysyx_24120011_APB_DELAYER_DELAY = 3'b010;

  reg [31:0] cnt;
  reg [2:0] state;
  reg [2:0] next_state;
  reg saved_pready;
  reg [31:0] saved_prdata;
  reg saved_pslverr;
  reg reg_pready;
  reg [31:0] reg_prdata;
  reg reg_pslverr;

  always @(posedge clock) begin
    if(reset) begin
      cnt <= 32'b0;
    end
    else begin
      if(state == ysyx_24120011_APB_DELAYER_WAIT_READY) begin
        cnt <= cnt + 32'd3;
      end
      else if(state == ysyx_24120011_APB_DELAYER_DELAY) begin
        cnt <= cnt - 32'd1;
      end
      else begin
        cnt <= 32'd0;
      end
    end
  end

  always @(posedge clock) begin
    if(reset) begin
      saved_pready  <= 'd0;
      saved_prdata  <= 'd0;
      saved_pslverr <= 'd0;
    end
    else begin
      if(state == ysyx_24120011_APB_DELAYER_WAIT_READY && next_state == ysyx_24120011_APB_DELAYER_DELAY) begin
        saved_pready  <= out_pready;
        saved_prdata  <= out_prdata;
        saved_pslverr <= out_pslverr;
      end
    end
  end

  always @(*) begin
    case(state)
      ysyx_24120011_APB_DELAYER_IDLE: next_state = (in_psel && !in_pready) ? ysyx_24120011_APB_DELAYER_WAIT_READY : ysyx_24120011_APB_DELAYER_IDLE;
      ysyx_24120011_APB_DELAYER_WAIT_READY: next_state = out_pready ? ysyx_24120011_APB_DELAYER_DELAY: ysyx_24120011_APB_DELAYER_WAIT_READY;
      ysyx_24120011_APB_DELAYER_DELAY: next_state = (cnt == 32'b0) ? ysyx_24120011_APB_DELAYER_IDLE :ysyx_24120011_APB_DELAYER_DELAY;
      default: next_state = ysyx_24120011_APB_DELAYER_IDLE;
    endcase
  end

  always @(posedge clock) begin
    if(reset) begin
      state <= ysyx_24120011_APB_DELAYER_IDLE;
    end
    else begin
      state <= next_state;
    end
  end

  always @(posedge clock) begin
    if(reset) begin
      reg_pready  <= 'd0;
      reg_prdata  <= 'd0;
      reg_pslverr <= 'd0;
    end
    else begin
      if(state == ysyx_24120011_APB_DELAYER_DELAY && next_state == ysyx_24120011_APB_DELAYER_IDLE) begin
        reg_pready  <= saved_pready;
        reg_prdata  <= saved_prdata;
        reg_pslverr <= saved_pslverr;
      end
      else begin
        reg_pready  <= 'd0;
        reg_prdata  <= 'd0;
        reg_pslverr <= 'd0;
      end
    end
  end

  assign out_paddr   = in_paddr;
  assign out_psel    = in_psel;
  assign out_penable = in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  assign in_pready   = reg_pready ;
  assign in_prdata   = reg_prdata ;
  assign in_pslverr  = reg_pslverr;
  // assign in_pready   = out_pready ;
  // assign in_prdata   = out_prdata ;
  // assign in_pslverr  = out_pslverr;

endmodule
