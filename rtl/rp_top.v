// Red Pitaya STEMlab 125-14 top level for the open toolchain.
//
//   ADC (125 MSPS, 14 bit, CH A) -> boxcar decimator /DECIM -> HLS kernel
//   (LIGO biquad cascade, Bambu-generated, start/done handshake)
//   -> sample-and-hold -> DAC CH A.   DAC CH B = ADC CH B passthrough.
//   PS7 M_AXI_GP0 -> axi_regs (coefficients, control, status), clocked by the
//   ADC clock so the whole PL is one clock domain at 125 MHz plus the 250 MHz
//   DAC ODDR clocks.
//
// Clocking follows the vendor design (red_pitaya_top.v / red_pitaya_pll.sv):
// IBUFDS on the ADC clock, PLLE2_ADV VCO = 1 GHz, CLKOUT0 125 MHz (ADC +
// DAC 1x), CLKOUT2 250 MHz (DAC WRT), CLKOUT3 250 MHz -45 deg (DAC CLK).
// The vendor uses separate 125 MHz BUFGs for adc_clk and dac_clk_1x with the
// same frequency/phase; here they are merged into one net so nextpnr can time
// the ADC->kernel->DAC path as a single domain.
module rp_top #(
  parameter integer DECIM = 16,          // kernel rate = 125 MHz / DECIM
  parameter integer USE_PS7 = 1,
  // Vendor design: "ZHOLD". nextpnr (openXC7 cf5f7a21, fasm.cc) asserts on
  // anything but "INTERNAL", so the ADC capture phase differs from the vendor
  // bitstream by the clock-tree insertion delay (see README, risks).
  parameter PLL_COMPENSATION = "INTERNAL"
)(
  // ADC
  input  wire [15:2] adc_dat_a_i, adc_dat_b_i,  // 14-bit ADC on bits [15:2]
  input  wire        adc_clk_p_i, adc_clk_n_i,
  output wire [1:0]  adc_clk_o,
  output wire        adc_cdcs_o,
  // DAC
  output wire [13:0] dac_dat_o,
  output wire        dac_wrt_o, dac_sel_o, dac_clk_o, dac_rst_o,
  // LEDs
  output wire [7:0]  led_o
);
  // ---------------------------------------------------------------- clocks
  wire adc_clk_in, clk_fb, pll_clk_125, pll_clk_250, pll_clk_250p, pll_locked;
  wire clk, dac_clk_2x, dac_clk_2p;

  IBUFDS i_clk (.I(adc_clk_p_i), .IB(adc_clk_n_i), .O(adc_clk_in));

  PLLE2_ADV #(
    .BANDWIDTH("OPTIMIZED"), .COMPENSATION(PLL_COMPENSATION),
    .DIVCLK_DIVIDE(1), .CLKFBOUT_MULT(8), .CLKFBOUT_PHASE(0.0),
    .CLKOUT0_DIVIDE(8), .CLKOUT0_PHASE(0.0),   .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT2_DIVIDE(4), .CLKOUT2_PHASE(0.0),   .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT3_DIVIDE(4), .CLKOUT3_PHASE(-45.0), .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKIN1_PERIOD(8.0), .REF_JITTER1(0.010)
  ) pll (
    .CLKFBOUT(clk_fb), .CLKFBIN(clk_fb),
    .CLKOUT0(pll_clk_125), .CLKOUT1(), .CLKOUT2(pll_clk_250), .CLKOUT3(pll_clk_250p),
    .CLKOUT4(), .CLKOUT5(),
    .CLKIN1(adc_clk_in), .CLKIN2(1'b0), .CLKINSEL(1'b1),
    .DADDR(7'h0), .DCLK(1'b0), .DEN(1'b0), .DI(16'h0), .DO(), .DRDY(), .DWE(1'b0),
    .LOCKED(pll_locked), .PWRDWN(1'b0), .RST(1'b0)
  );
  BUFG bufg_clk   (.I(pll_clk_125),  .O(clk));
  BUFG bufg_dac2x (.I(pll_clk_250),  .O(dac_clk_2x));
  BUFG bufg_dac2p (.I(pll_clk_250p), .O(dac_clk_2p));

  // ---------------------------------------------------------------- PS7
  wire        fclk_rstn;
  wire [11:0] awid, wid, arid, bid, rid;
  wire [31:0] awaddr, wdata, araddr, rdata;
  wire [3:0]  awlen, arlen, wstrb;
  wire [2:0]  awsize, arsize;
  wire        awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  wire        arvalid, arready, rvalid, rready, rlast;
  wire [1:0]  bresp, rresp;

  generate if (USE_PS7) begin : g_ps7
    wire [3:0] fclk_resetn;
    PS7 ps7_i (
      .MAXIGP0ACLK(clk),
      .MAXIGP0AWID(awid), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWLEN(awlen),
      .MAXIGP0AWSIZE(awsize), .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready),
      .MAXIGP0AWBURST(), .MAXIGP0AWLOCK(), .MAXIGP0AWCACHE(), .MAXIGP0AWPROT(), .MAXIGP0AWQOS(),
      .MAXIGP0WID(wid), .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb), .MAXIGP0WLAST(wlast),
      .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
      .MAXIGP0BID(bid), .MAXIGP0BRESP(bresp), .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready),
      .MAXIGP0ARID(arid), .MAXIGP0ARADDR(araddr), .MAXIGP0ARLEN(arlen),
      .MAXIGP0ARSIZE(arsize), .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready),
      .MAXIGP0ARBURST(), .MAXIGP0ARLOCK(), .MAXIGP0ARCACHE(), .MAXIGP0ARPROT(), .MAXIGP0ARQOS(),
      .MAXIGP0RID(rid), .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(rresp), .MAXIGP0RLAST(rlast),
      .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready),
      .MAXIGP0ARESETN(),
      .FCLKRESETN(fclk_resetn), .FCLKCLK()
    );
    assign fclk_rstn = fclk_resetn[0];
  end else begin : g_nops7
    assign fclk_rstn = 1'b1;
    assign awvalid = 1'b0; assign wvalid = 1'b0; assign arvalid = 1'b0;
    assign bready = 1'b1;  assign rready = 1'b1;
    assign awid = 0; assign wid = 0; assign arid = 0; assign awaddr = 0; assign araddr = 0;
    assign wdata = 0; assign awlen = 0; assign arlen = 0; assign wstrb = 0;
    assign awsize = 3'b010; assign arsize = 3'b010; assign wlast = 1'b1;
  end endgenerate

  // reset: PS fabric reset AND PLL lock, synchronised into clk
  reg [3:0] rst_sync = 4'h0;
  always @(posedge clk) rst_sync <= {rst_sync[2:0], fclk_rstn & pll_locked};
  wire rstn = rst_sync[3];

  // ---------------------------------------------------------------- registers
  wire [31:0]  ctrl;
  wire [319:0] coef;
  reg  [31:0]  samples, latency, overruns, x_last, y_last;
  axi_regs #(
    // default coefficients = ref/biquad_ref.py SEC0 (50 kHz LP) / SEC1 (200 kHz peak)
    .COEF_INIT({32'hff992b45, 32'h0eb75cd1, 32'hfffd4119, 32'h00d1f5ff, 32'h10705e4b,
                32'hfff98f83, 32'h0f171788, 32'h3ff98f83, 32'h3f171788, 32'h00019c1f}),
    .DECIM(DECIM)
  ) regs (
    .clk(clk), .rstn(rstn),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awvalid(awvalid), .awready(awready),
    .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
    .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .arvalid(arvalid), .arready(arready),
    .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
    .ctrl(ctrl), .coef(coef),
    .samples(samples), .latency(latency), .overruns(overruns), .x_last(x_last), .y_last(y_last)
  );

  // ---------------------------------------------------------------- ADC
  // IOB registers; 14-bit data on bits [15:2]; offset-binary with inverted
  // slope -> two's complement as in the vendor design.
  (* IOB = "TRUE" *) reg [15:2] adc_a_ff, adc_b_ff;
  reg  [13:0] adc_a, adc_b;
  always @(posedge clk) begin
    adc_a_ff <= adc_dat_a_i;
    adc_b_ff <= adc_dat_b_i;
    adc_a    <= {adc_a_ff[15], ~adc_a_ff[14:2]};
    adc_b    <= {adc_b_ff[15], ~adc_b_ff[14:2]};
  end

  // ---------------------------------------------------------------- multi-rate glue
  // Boxcar decimator: sum DECIM samples, emit one kernel input per DECIM
  // clocks. With DECIM = 2^k the mean in Q16.16 is sum << (16 - k).
  localparam integer K = $clog2(DECIM);
  reg [K-1:0]      phase;
  reg signed [13+K:0] acc;
  reg signed [31:0] x_in;
  reg              strobe;
  always @(posedge clk) begin
    if (!rstn) begin
      phase <= 0; acc <= 0; strobe <= 1'b0; x_in <= 0;
    end else begin
      phase  <= phase + 1'b1;
      strobe <= (phase == {K{1'b1}});
      if (phase == {K{1'b1}}) begin
        x_in <= ($signed(acc) + $signed(adc_a)) <<< (16 - K);
        acc  <= 0;
      end else
        acc  <= acc + $signed(adc_a);
    end
  end

  // Coefficient shadow: copied at each sample unless CTRL.freeze is set, so the
  // kernel sees a consistent set for the whole computation.
  reg [319:0] coef_sh;
  always @(posedge clk) if (strobe && !ctrl[2]) coef_sh <= coef;

  // ---------------------------------------------------------------- HLS kernel
  wire        k_done;
  wire [31:0] k_y;
  reg         k_busy, k_start;
  reg [31:0]  k_x, lat_cnt;
  kernel_wrap kernel (
    .clk(clk), .rst(!rstn), .start(k_start), .x(k_x), .coef(coef_sh),
    .clear(ctrl[0]), .done(k_done), .y(k_y)
  );
  always @(posedge clk) begin
    if (!rstn) begin
      k_busy <= 1'b0; k_start <= 1'b0; samples <= 0; overruns <= 0; latency <= 0;
      lat_cnt <= 0; y_last <= 0; x_last <= 0; k_x <= 0;
    end else begin
      k_start <= 1'b0;
      if (k_busy) lat_cnt <= lat_cnt + 1;
      if (strobe) begin
        if (k_busy) overruns <= overruns + 1;
        else begin
          k_start <= 1'b1; k_busy <= 1'b1; k_x <= x_in; x_last <= x_in; lat_cnt <= 1;
        end
      end
      if (k_busy && k_done) begin
        k_busy <= 1'b0; y_last <= k_y; latency <= lat_cnt; samples <= samples + 1;
      end
    end
  end

  // ---------------------------------------------------------------- DAC
  // Q16.16 -> 14-bit with saturation; sample-and-hold at the kernel rate.
  function [13:0] sat14(input [31:0] q);
    reg signed [15:0] ip;
    begin
      ip = q[31:16];
      if (q[31] && (q[31:29] != 3'b111)) sat14 = 14'h2000;
      else if (!q[31] && (q[31:29] != 3'b000)) sat14 = 14'h1fff;
      else sat14 = q[29:16];
    end
  endfunction
  wire [13:0] mean_a = x_last[29:16];
  reg  [13:0] dac_a, dac_b, dac_dat_a, dac_dat_b;
  reg         dac_rst;
  always @(posedge clk) begin
    dac_a     <= ctrl[1] ? mean_a : sat14(y_last);
    dac_b     <= adc_b;
    dac_dat_a <= {dac_a[13], ~dac_a[12:0]};
    dac_dat_b <= {dac_b[13], ~dac_b[12:0]};
    dac_rst   <= !rstn;
  end
  // ODDR interleaving as in the vendor design (A on falling half, B on rising)
  ODDR oddr_dac_clk (.Q(dac_clk_o), .D1(1'b0), .D2(1'b1), .C(dac_clk_2p), .CE(1'b1), .R(1'b0), .S(1'b0));
  ODDR oddr_dac_wrt (.Q(dac_wrt_o), .D1(1'b0), .D2(1'b1), .C(dac_clk_2x), .CE(1'b1), .R(1'b0), .S(1'b0));
  // Workaround: nextpnr (openXC7 cf5f7a21) fails an internal check for ODDR
  // with a non-constant R ("user port SR connected to incorrect net"), so the
  // synchronous reset of the vendor design is folded into the D inputs.
  ODDR oddr_dac_sel (.Q(dac_sel_o), .D1(~dac_rst), .D2(1'b0), .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));
  ODDR oddr_dac_rst (.Q(dac_rst_o), .D1(dac_rst), .D2(dac_rst), .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));
  genvar gd;
  generate for (gd = 0; gd < 14; gd = gd + 1) begin : g_dac
    ODDR oddr_dac_dat (.Q(dac_dat_o[gd]), .D1(dac_dat_b[gd] & ~dac_rst), .D2(dac_dat_a[gd] & ~dac_rst),
                       .C(clk), .CE(1'b1), .R(1'b0), .S(1'b0));
  end endgenerate

  // ---------------------------------------------------------------- misc IO
  assign adc_clk_o  = 2'b10;   // ADC clock generation disabled (as vendor)
  assign adc_cdcs_o = 1'b1;    // ADC duty-cycle stabiliser on
  reg [26:0] hb;
  always @(posedge clk) hb <= hb + 1;
  assign led_o = {ctrl[7:3], (overruns != 0), pll_locked, hb[26]};
endmodule
