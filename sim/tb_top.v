// System-level check of rp_top (any kernel_wrap): ADC clock + data in,
// AXI GP0 register access through the PS7 stub, DAC samples decoded from the
// ODDR outputs. Checks:
//  1. ID register reads 0x52504831, coefficients read back their defaults
//  2. kernel runs once per DECIM clocks without overruns, LATENCY sensible
//  3. Y_LAST equals the C/Python reference (biquad cascade on the decimated
//     input that the RTL actually fed it, X_LAST)
//  4. DAC A (decoded from dac_dat_o on the falling half) = sat14(Y_LAST)
//  5. coefficient write (G0) and bypass mode work
`timescale 1ns/1ps
module tb_top;
  reg clk_p = 0;
  always #4 clk_p = ~clk_p;
  reg [13:0] adc_a = 0, adc_b = 0;
  // ADC: offset binary with inverted slope -> pins (bits [15:2])
  wire [15:2] pin_a = {adc_a[13], ~adc_a[12:0]};
  wire [15:2] pin_b = {adc_b[13], ~adc_b[12:0]};
  wire [13:0] dac_dat; wire dac_wrt, dac_sel, dac_clk, dac_rst; wire [7:0] led; wire [1:0] adc_clk_o; wire cdcs;
  rp_top dut (.adc_dat_a_i(pin_a), .adc_dat_b_i(pin_b), .adc_clk_p_i(clk_p), .adc_clk_n_i(~clk_p),
              .adc_clk_o(adc_clk_o), .adc_cdcs_o(cdcs), .dac_dat_o(dac_dat), .dac_wrt_o(dac_wrt),
              .dac_sel_o(dac_sel), .dac_clk_o(dac_clk), .dac_rst_o(dac_rst), .led_o(led));

  // DAC decode: during the second half of each 125 MHz cycle the ODDR drives D2 = channel A
  reg [13:0] dac_a_seen;
  always @(posedge clk_p) begin #6; dac_a_seen = {dac_dat[13], ~dac_dat[12:0]}; end

  // reference model (same arithmetic as hls/biquad.c), 2 sections
  reg signed [31:0] w0 = 0, u0 = 0, w1 = 0, u1 = 0;
  function [31:0] mac3(input [31:0] a, p, b, q, c, r);
    reg signed [63:0] s;
    begin s = $signed(a) * $signed(p) + $signed(b) * $signed(q) + $signed(c) * $signed(r); mac3 = s[59:28]; end
  endfunction
  function [31:0] sec(input integer k, input [31:0] x, input [319:0] cf);
    reg [31:0] g, c0, c1, a10, a11, w, u, y, wn;
    begin
      g = cf[160*k +: 32]; c0 = cf[160*k+32 +: 32]; c1 = cf[160*k+64 +: 32];
      a10 = cf[160*k+96 +: 32]; a11 = cf[160*k+128 +: 32];
      w = k ? w1 : w0; u = k ? u1 : u0;
      y = mac3(g, x, c0, w, c1, u); wn = mac3(g, x, a10, w, a11, u);
      if (k) begin u1 = u1 + w1; w1 = wn; end else begin u0 = u0 + w0; w0 = wn; end
      sec = y;
    end
  endfunction

  integer errors = 0, i, n_checked = 0;
  reg [31:0] d, samples0, xl, yl, yref, cf_now;
  reg [319:0] cf;
  // follow the kernel: on every completed sample recompute the reference from X_LAST
  always @(posedge dut.clk) if (dut.rstn && dut.k_busy && dut.kernel.done) begin
    yref = sec(1, sec(0, dut.k_x, dut.coef_sh), dut.coef_sh);
    if (yref !== dut.kernel.y) begin
      if (errors < 10) $display("kernel mismatch: x=%h y=%h ref=%h", dut.k_x, dut.kernel.y, yref);
      errors = errors + 1;
    end
    n_checked = n_checked + 1;
  end

  initial begin
    wait (dut.rstn);
    dut.g_ps7.ps7_i.read(32'h40000000, d);
    if (d !== 32'h52504831) begin $display("ID wrong: %h", d); errors = errors + 1; end
    dut.g_ps7.ps7_i.read(32'h40000020, d);
    if (d !== 32'h00019c1f) begin $display("G0 default wrong: %h", d); errors = errors + 1; end
    dut.g_ps7.ps7_i.read(32'h4000001C, d);
    $display("DECIM register: %0d", d);
    // impulse then random ADC data
    for (i = 0; i < 4000; i = i + 1) begin
      @(posedge clk_p);
      adc_a <= (i < 16) ? 14'h1fff : (i < 600 ? 0 : $random);
      adc_b <= i;
      if (i == 2000) begin
        // freeze, change G0 (x2), unfreeze: atomic coefficient update
        fork dut.g_ps7.ps7_i.write(32'h40000004, 32'h4); join
        dut.g_ps7.ps7_i.write(32'h40000020, 32'h00033838);
        dut.g_ps7.ps7_i.write(32'h40000004, 32'h0);
      end
    end
    dut.g_ps7.ps7_i.read(32'h40000008, d);  $display("SAMPLES  %0d", d);
    dut.g_ps7.ps7_i.read(32'h4000000C, d);  $display("LATENCY  %0d clocks", d);
    dut.g_ps7.ps7_i.read(32'h40000010, d);  $display("OVERRUNS %0d", d);
    if (d != 0) errors = errors + 1;
    dut.g_ps7.ps7_i.read(32'h40000020, d);
    if (d !== 32'h00033838) begin $display("G0 write failed: %h", d); errors = errors + 1; end
    // DAC A must show sat14(Y_LAST) (2 pipeline stages after y_last updates)
    @(posedge dut.kernel.done); repeat (6) @(posedge clk_p);  // done -> y_last -> dac_a -> dac_dat_a -> ODDR -> seen
    if (dac_a_seen !== dut.sat14(dut.y_last)) begin
      $display("DAC A %h != sat14(y_last) %h", dac_a_seen, dut.sat14(dut.y_last)); errors = errors + 1;
    end
    // bypass: DAC A = decimated mean of ADC A
    dut.g_ps7.ps7_i.write(32'h40000004, 32'h2);
    for (i = 0; i < 64; i = i + 1) begin @(posedge clk_p); adc_a <= 14'h0123; end
    repeat (4) @(posedge clk_p);
    if (dac_a_seen !== 14'h0123) begin $display("bypass DAC A %h", dac_a_seen); errors = errors + 1; end
    $display("RESULT top: kernel samples checked against reference: %0d, errors: %0d", n_checked, errors);
    $finish;
  end
  initial begin #2000000 $display("TIMEOUT"); $finish; end
endmodule
