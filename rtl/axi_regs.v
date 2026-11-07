// Minimal AXI3 slave (Zynq M_AXI_GP0, 32-bit data, single-beat transfers)
// with the kernel register file. Bursts are answered with SLVERR (one beat
// accepted per address; the PS only issues single beats for /dev/mem 32-bit
// accesses). Everything runs in one clock domain (the 125 MHz ADC clock also
// drives MAXIGP0ACLK), so no CDC is needed between registers and the kernel.
//
// Register map (byte offsets from the GP0 base 0x4000_0000):
//   0x00 RO  ID           0x52504831 ("RPH1")
//   0x04 RW  CTRL         [0] clear kernel state (level)
//                         [1] bypass: DAC A = decimated ADC A
//                         [2] freeze: hold coefficient shadow (atomic update)
//                         [7:3] -> LEDs[7:3]
//   0x08 RO  SAMPLES      kernel sample counter
//   0x0C RO  LATENCY      kernel latency in clocks (start -> done), last sample
//   0x10 RO  OVERRUNS     samples dropped because the kernel was still busy
//   0x14 RO  X_LAST       last kernel input (Q16.16)
//   0x18 RO  Y_LAST       last kernel output (Q16.16)
//   0x1C RO  DECIM        decimation factor (kernel rate = 125 MHz / DECIM)
//   0x20..0x30 RW  section 0: G C0 C1 A10 A11 (Q4.28)
//   0x34..0x44 RW  section 1: G C0 C1 A10 A11 (Q4.28)
module axi_regs #(
  parameter [32*10-1:0] COEF_INIT = 320'h0,
  parameter integer     DECIM     = 16
)(
  input  wire        clk,
  input  wire        rstn,
  // AXI3 slave
  input  wire [11:0] awid,   input wire [31:0] awaddr, input wire [3:0] awlen,
  input  wire [1:0]  awsize, input wire        awvalid, output wire       awready,
  input  wire [11:0] wid,    input wire [31:0] wdata,  input wire [3:0] wstrb,
  input  wire        wlast,  input wire        wvalid, output wire        wready,
  output reg  [11:0] bid,    output reg  [1:0] bresp,  output reg         bvalid,
  input  wire        bready,
  input  wire [11:0] arid,   input wire [31:0] araddr, input wire [3:0] arlen,
  input  wire [1:0]  arsize, input wire        arvalid, output wire       arready,
  output reg  [11:0] rid,    output reg  [31:0] rdata, output reg  [1:0] rresp,
  output reg         rlast,  output reg         rvalid, input wire        rready,
  // register file <-> design
  output reg  [31:0]   ctrl,
  output wire [32*10-1:0] coef,     // {sec1 A11..G, sec0 A11..G}, G of sec0 in [31:0]
  input  wire [31:0]   samples, input wire [31:0] latency, input wire [31:0] overruns,
  input  wire [31:0]   x_last,  input wire [31:0] y_last
);
  reg [31:0] coef_r [0:9];
  genvar gi;
  generate for (gi = 0; gi < 10; gi = gi + 1) begin : g_coef
    assign coef[32*gi +: 32] = coef_r[gi];
  end endgenerate

  // ---------------- write channel ----------------
  reg        aw_have, w_have;
  reg [31:0] aw_addr, w_data;
  reg [3:0]  w_strb;
  reg        aw_err;
  assign awready = !aw_have && !bvalid;
  assign wready  = !w_have  && !bvalid;

  wire do_write = aw_have && w_have && !bvalid;
  integer i;
  always @(posedge clk) begin
    if (!rstn) begin
      aw_have <= 1'b0; w_have <= 1'b0; bvalid <= 1'b0; bresp <= 2'b00; bid <= 12'd0;
      ctrl <= 32'd0;
      for (i = 0; i < 10; i = i + 1) coef_r[i] <= COEF_INIT[32*i +: 32];
    end else begin
      if (awvalid && awready) begin
        aw_have <= 1'b1; aw_addr <= awaddr; bid <= awid;
        aw_err  <= (awlen != 4'd0) || (awsize != 2'b10);
      end
      if (wvalid && wready) begin
        w_have <= 1'b1; w_data <= wdata; w_strb <= wstrb;
      end
      if (do_write) begin
        aw_have <= 1'b0; w_have <= 1'b0; bvalid <= 1'b1;
        bresp   <= aw_err ? 2'b10 : 2'b00;
        if (!aw_err && (&w_strb)) begin
          case (aw_addr[7:2])
            6'h01: ctrl <= w_data;
            default:
              if (aw_addr[7:2] >= 6'h08 && aw_addr[7:2] < 6'h12)
                coef_r[aw_addr[7:2] - 6'h08] <= w_data;
          endcase
        end
      end else if (bvalid && bready) begin
        bvalid <= 1'b0;
      end
    end
  end

  // ---------------- read channel ----------------
  assign arready = !rvalid;
  reg [31:0] rd_mux;
  always @(*) begin
    case (araddr[7:2])
      6'h00: rd_mux = 32'h52504831;
      6'h01: rd_mux = ctrl;
      6'h02: rd_mux = samples;
      6'h03: rd_mux = latency;
      6'h04: rd_mux = overruns;
      6'h05: rd_mux = x_last;
      6'h06: rd_mux = y_last;
      6'h07: rd_mux = DECIM;
      default:
        if (araddr[7:2] >= 6'h08 && araddr[7:2] < 6'h12) rd_mux = coef_r[araddr[7:2] - 6'h08];
        else rd_mux = 32'hDEADBEEF;
    endcase
  end
  always @(posedge clk) begin
    if (!rstn) begin
      rvalid <= 1'b0; rlast <= 1'b0; rresp <= 2'b00; rid <= 12'd0; rdata <= 32'd0;
    end else if (arvalid && arready) begin
      rvalid <= 1'b1; rlast <= 1'b1; rid <= arid; rdata <= rd_mux;
      rresp  <= ((arlen != 4'd0) || (arsize != 2'b10)) ? 2'b10 : 2'b00;
    end else if (rvalid && rready) begin
      rvalid <= 1'b0; rlast <= 1'b0;
    end
  end
endmodule
