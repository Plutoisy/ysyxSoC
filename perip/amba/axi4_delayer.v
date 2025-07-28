module axi4_delayer(
  input         clock,
  input         reset,

  // 上游接口 (CPU侧)
  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
  
  input         in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  // 下游接口 (设备侧)
  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
  
  output        out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);

// 延迟参数 (可配置)
parameter R = 3;

//--------------------------------------------------------------------------
// AR通道 (直接透传)
//--------------------------------------------------------------------------
assign out_arvalid = in_arvalid;
assign out_arid    = in_arid;
assign out_araddr  = in_araddr;
assign out_arlen   = in_arlen;
assign out_arsize  = in_arsize;
assign out_arburst = in_arburst;
assign in_arready  = out_arready;

//--------------------------------------------------------------------------
// AW通道 (直接透传)
//--------------------------------------------------------------------------
assign out_awvalid = in_awvalid;
assign out_awid    = in_awid;
assign out_awaddr  = in_awaddr;
assign out_awlen   = in_awlen;
assign out_awsize  = in_awsize;
assign out_awburst = in_awburst;
assign in_awready  = out_awready;

//--------------------------------------------------------------------------
// W通道 (直接透传)
//--------------------------------------------------------------------------
assign out_wvalid = in_wvalid;
assign out_wdata  = in_wdata;
assign out_wstrb  = in_wstrb;
assign out_wlast  = in_wlast;
assign in_wready  = out_wready;

//--------------------------------------------------------------------------
// R通道延迟逻辑 (3级流水线)
//--------------------------------------------------------------------------
reg [2:0]  r_stage_valid;
reg [2:0][3:0]  r_stage_id;
reg [2:0][31:0] r_stage_data;
reg [2:0][1:0]  r_stage_resp;
reg [2:0]       r_stage_last;

// 流水线控制信号
wire r_shift = in_rready || !r_stage_valid[2];

always @(posedge clock) begin
  if (reset) begin
    r_stage_valid <= 3'b0;
  end else begin
    if (r_shift) begin
      // 数据在流水线中移动
      r_stage_valid <= {r_stage_valid[1:0], out_rvalid && out_rready};
      r_stage_id    <= {r_stage_id[1:0],    out_rid};
      r_stage_data  <= {r_stage_data[1:0],  out_rdata};
      r_stage_resp  <= {r_stage_resp[1:0],  out_rresp};
      r_stage_last  <= {r_stage_last[1:0],  out_rlast};
    end
  end
end

// 输出到上游
assign in_rvalid = r_stage_valid[2];
assign in_rid    = r_stage_id[2];
assign in_rdata  = r_stage_data[2];
assign in_rresp  = r_stage_resp[2];
assign in_rlast  = r_stage_last[2];

// 输出到下游
assign out_rready = !r_stage_valid[0] || r_shift;

//--------------------------------------------------------------------------
// B通道延迟逻辑 (3级流水线)
//--------------------------------------------------------------------------
reg [2:0]       b_stage_valid;
reg [2:0][3:0]  b_stage_id;
reg [2:0][1:0]  b_stage_resp;

// 流水线控制信号
wire b_shift = in_bready || !b_stage_valid[2];

always @(posedge clock) begin
  if (reset) begin
    b_stage_valid <= 3'b0;
  end else begin
    if (b_shift) begin
      // 数据在流水线中移动
      b_stage_valid <= {b_stage_valid[1:0], out_bvalid && out_bready};
      b_stage_id    <= {b_stage_id[1:0],    out_bid};
      b_stage_resp  <= {b_stage_resp[1:0],  out_bresp};
    end
  end
end

// 输出到上游
assign in_bvalid = b_stage_valid[2];
assign in_bid    = b_stage_id[2];
assign in_bresp  = b_stage_resp[2];

// 输出到下游
assign out_bready = !b_stage_valid[0] || b_shift;




  // assign in_arready = out_arready;
  // assign out_arvalid = in_arvalid;
  // assign out_arid = in_arid;
  // assign out_araddr = in_araddr;
  // assign out_arlen = in_arlen;
  // assign out_arsize = in_arsize;
  // assign out_arburst = in_arburst;
  // assign out_rready = in_rready;
  // assign in_rvalid = out_rvalid;
  // assign in_rid = out_rid;
  // assign in_rdata = out_rdata;
  // assign in_rresp = out_rresp;
  // assign in_rlast = out_rlast;
  // assign in_awready = out_awready;
  // assign out_awvalid = in_awvalid;
  // assign out_awid = in_awid;
  // assign out_awaddr = in_awaddr;
  // assign out_awlen = in_awlen;
  // assign out_awsize = in_awsize;
  // assign out_awburst = in_awburst;
  // assign in_wready = out_wready;
  // assign out_wvalid = in_wvalid;
  // assign out_wdata = in_wdata;
  // assign out_wstrb = in_wstrb;
  // assign out_wlast = in_wlast;
  // assign out_bready = in_bready;
  // assign in_bvalid = out_bvalid;
  // assign in_bid = out_bid;
  // assign in_bresp = out_bresp;

endmodule