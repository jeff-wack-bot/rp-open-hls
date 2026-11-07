// Minimal behavioural models of the Xilinx primitives used by rp_top, for
// iverilog (the yosys/Vivado unisims are not needed for this level of check).
`timescale 1ns/1ps
module IBUFDS (input I, input IB, output O); assign O = I; endmodule
module BUFG (input I, output O); assign O = I; endmodule

// PLLE2_ADV model: CLKOUT0 follows CLKIN1 (x1); CLKOUT2/CLKOUT3 are a free
// 2x clock aligned to CLKIN1 rising edges (CLKOUT3 shifted by -45 deg).
module PLLE2_ADV #(parameter BANDWIDTH = "", COMPENSATION = "", parameter integer DIVCLK_DIVIDE = 1,
  CLKFBOUT_MULT = 1, CLKOUT0_DIVIDE = 1, CLKOUT2_DIVIDE = 1, CLKOUT3_DIVIDE = 1,
  parameter real CLKFBOUT_PHASE = 0, CLKOUT0_PHASE = 0, CLKOUT2_PHASE = 0, CLKOUT3_PHASE = 0,
  CLKOUT0_DUTY_CYCLE = 0.5, CLKOUT2_DUTY_CYCLE = 0.5, CLKOUT3_DUTY_CYCLE = 0.5,
  CLKIN1_PERIOD = 8.0, REF_JITTER1 = 0.0)
 (output CLKFBOUT, input CLKFBIN, output CLKOUT0, CLKOUT1, output reg CLKOUT2 = 0, output reg CLKOUT3 = 0,
  output CLKOUT4, CLKOUT5, input CLKIN1, CLKIN2, CLKINSEL, input [6:0] DADDR, input DCLK, DEN,
  input [15:0] DI, output [15:0] DO, output DRDY, input DWE, output reg LOCKED = 0, input PWRDWN, RST);
  assign CLKOUT0 = CLKIN1; assign CLKFBOUT = CLKIN1;
  always @(posedge CLKIN1) begin
    CLKOUT2 <= 1; #2 CLKOUT2 <= 0; #2 CLKOUT2 <= 1; #2 CLKOUT2 <= 0;
  end
  always @(posedge CLKIN1) begin
    #1.75 CLKOUT3 <= 1; #2 CLKOUT3 <= 0; #2 CLKOUT3 <= 1; #2 CLKOUT3 <= 0;
  end
  initial #200 LOCKED = 1;
endmodule

// ODDR, OPPOSITE_EDGE (default): D1 sampled on rising, D2 on falling edge
module ODDR (output reg Q = 0, input C, CE, D1, D2, R, S);
  reg d2r;
  always @(posedge C) if (R) begin Q <= 0; d2r <= 0; end else if (CE) begin Q <= D1; d2r <= D2; end
  always @(negedge C) if (!R && CE) Q <= d2r;
endmodule

// PS7 stub: the AXI GP0 master is driven by the testbench through tasks.
module PS7 (
  input MAXIGP0ACLK,
  output reg [11:0] MAXIGP0AWID = 0, output reg [31:0] MAXIGP0AWADDR = 0, output reg [3:0] MAXIGP0AWLEN = 0,
  output reg [1:0] MAXIGP0AWSIZE = 2, output reg MAXIGP0AWVALID = 0, input MAXIGP0AWREADY,
  output [1:0] MAXIGP0AWBURST, MAXIGP0AWLOCK, output [3:0] MAXIGP0AWCACHE, output [2:0] MAXIGP0AWPROT,
  output [3:0] MAXIGP0AWQOS,
  output reg [11:0] MAXIGP0WID = 0, output reg [31:0] MAXIGP0WDATA = 0, output reg [3:0] MAXIGP0WSTRB = 4'hf,
  output reg MAXIGP0WLAST = 1, output reg MAXIGP0WVALID = 0, input MAXIGP0WREADY,
  input [11:0] MAXIGP0BID, input [1:0] MAXIGP0BRESP, input MAXIGP0BVALID, output reg MAXIGP0BREADY = 1,
  output reg [11:0] MAXIGP0ARID = 0, output reg [31:0] MAXIGP0ARADDR = 0, output reg [3:0] MAXIGP0ARLEN = 0,
  output reg [1:0] MAXIGP0ARSIZE = 2, output reg MAXIGP0ARVALID = 0, input MAXIGP0ARREADY,
  output [1:0] MAXIGP0ARBURST, MAXIGP0ARLOCK, output [3:0] MAXIGP0ARCACHE, output [2:0] MAXIGP0ARPROT,
  output [3:0] MAXIGP0ARQOS,
  input [11:0] MAXIGP0RID, input [31:0] MAXIGP0RDATA, input [1:0] MAXIGP0RRESP, input MAXIGP0RLAST,
  input MAXIGP0RVALID, output reg MAXIGP0RREADY = 1,
  output MAXIGP0ARESETN, output reg [3:0] FCLKRESETN = 0, output [3:0] FCLKCLK);
  // note: the real PS7 AxSIZE ports are 2 bits wide (yosys warns when rp_top
  // connects 3 bits); size 2'b10 = 4 bytes.
  initial #100 FCLKRESETN = 4'hf;
  task write(input [31:0] a, input [31:0] d);
    begin
      @(posedge MAXIGP0ACLK); MAXIGP0AWADDR <= a; MAXIGP0AWVALID <= 1; MAXIGP0WDATA <= d; MAXIGP0WVALID <= 1;
      fork
        begin @(posedge MAXIGP0ACLK); while (!MAXIGP0AWREADY) @(posedge MAXIGP0ACLK); MAXIGP0AWVALID <= 0; end
        begin @(posedge MAXIGP0ACLK); while (!MAXIGP0WREADY) @(posedge MAXIGP0ACLK); MAXIGP0WVALID <= 0; end
      join
      while (!MAXIGP0BVALID) @(posedge MAXIGP0ACLK);
      if (MAXIGP0BRESP != 0) $display("AXI write %h: BRESP %b", a, MAXIGP0BRESP);
    end
  endtask
  task read(input [31:0] a, output [31:0] d);
    begin
      @(posedge MAXIGP0ACLK); MAXIGP0ARADDR <= a; MAXIGP0ARVALID <= 1;
      @(posedge MAXIGP0ACLK); while (!MAXIGP0ARREADY) @(posedge MAXIGP0ACLK); MAXIGP0ARVALID <= 0;
      while (!MAXIGP0RVALID) @(posedge MAXIGP0ACLK);
      d = MAXIGP0RDATA;
    end
  endtask
endmodule
