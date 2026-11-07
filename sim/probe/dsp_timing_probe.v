// Probe: is the DSP48E1 datapath timed by nextpnr? Chained 32x32 multiplies
// between registers (several cascaded DSP48 + LUT adders) cannot close at
// 300 MHz; if nextpnr reports PASS, DSP arcs are missing from its timing model.
module dsp_timing_probe(input clk, output led);
  reg [31:0] ra, rb, rc, y;   // no init values: yosys 0.66 xilinx_dsp.cc:400 asserts on them
  always @(posedge clk) begin
    ra <= {ra[30:0], ~(ra[31] ^ ra[21] ^ ra[1] ^ ra[0])};
    rb <= rb + 32'h9e3779b9;
    rc <= {rc[0], rc[31:1]} ^ ra;
    y  <= (ra * rb) * rc;
  end
  assign led = ^y;
endmodule
