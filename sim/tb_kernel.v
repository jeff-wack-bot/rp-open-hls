// Bit-exact testbench for kernel_wrap (any implementation: Bambu or hand RTL).
// Reads ref/biquad_ref.py vectors: clear x coef[5*NSEC] y_expected (hex).
// +VEC=<file>  +GAP=<idle cycles between samples, default 0>
`timescale 1ns/1ps
module tb_kernel;
  parameter integer NSEC = 1;
  localparam integer NCOL = 3 + 5 * NSEC;
  reg clk = 0, rst = 1, start = 0, clear = 0;
  reg [31:0] x;
  reg [319:0] coef = 0;
  wire done; wire [31:0] y;
  always #4 clk = ~clk;

  kernel_wrap dut (.clk(clk), .rst(rst), .start(start), .x(x), .coef(coef),
                   .clear(clear), .done(done), .y(y));

  integer fd, k, r, n = 0, bad = 0, gap = 0, cyc, maxlat = 0, minlat = 1 << 30;
  reg [31:0] v [0:12];
  reg [8*256-1:0] vec;
  initial begin
    if (!$value$plusargs("VEC=%s", vec)) vec = "vectors.txt";
    if (!$value$plusargs("GAP=%d", gap)) gap = 0;
    fd = $fopen(vec, "r");
    if (fd == 0) begin $display("cannot open %0s", vec); $finish; end
    repeat (5) @(posedge clk);
    rst <= 0;
    repeat (2) @(posedge clk);
    while (!$feof(fd)) begin
      r = 0;
      for (k = 0; k < NCOL; k = k + 1) r = r + $fscanf(fd, "%h", v[k]);
      if (r == NCOL) begin
        clear <= v[0][0]; x <= v[1];
        for (k = 0; k < 5 * NSEC; k = k + 1) coef[32*k +: 32] <= v[2 + k];
        start <= 1;
        @(posedge clk); start <= 0; cyc = 1;
        while (!done) begin @(posedge clk); cyc = cyc + 1; end
        // done is sampled in the cycle it is asserted; y valid with done
        if (y !== v[NCOL-1]) begin
          if (bad < 10) $display("MISMATCH #%0d: x=%h got %h want %h", n, v[1], y, v[NCOL-1]);
          bad = bad + 1;
        end
        if (cyc > maxlat) maxlat = cyc;
        if (cyc < minlat) minlat = cyc;
        n = n + 1;
        @(posedge clk);
        repeat (gap) @(posedge clk);
      end
    end
    $display("RESULT nsec=%0d vectors=%0d mismatches=%0d latency=%0d..%0d cycles",
             NSEC, n, bad, minlat, maxlat);
    $finish;
  end
endmodule
