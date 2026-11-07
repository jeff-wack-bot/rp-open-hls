// Bit-exact test of the Bambu decim_biquad2 (FIFO-mode ADC port).
// The FIFO model always has data (one new ADC sample per clock would be the
// real source); counts clocks per call to see whether one call per 16 ADC
// samples keeps up with 125 MS/s.
`timescale 1ns/1ps
module tb_decim;
  reg clk = 0, rst = 1, start = 0; always #4 clk = ~clk;
  wire done, rd; wire [31:0] y; reg [15:0] fifo [0:15]; reg [3:0] rp; reg [31:0] yexp;
  localparam [319:0] CF = {32'hff992b45, 32'h0eb75cd1, 32'hfffd4119, 32'h00d1f5ff, 32'h10705e4b,
                           32'hfff98f83, 32'h0f171788, 32'h3ff98f83, 32'h3f171788, 32'h00019c1f};
  decim_biquad2 dut (.clock(clk), .reset(rst), .start_port(start), .adc_dout(fifo[rp]), .adc_empty_n(1'b1),
    .adc_read(rd), .g0(CF[0+:32]), .c00(CF[32+:32]), .c01(CF[64+:32]), .a010(CF[96+:32]), .a011(CF[128+:32]),
    .g1(CF[160+:32]), .c10(CF[192+:32]), .c11(CF[224+:32]), .a110(CF[256+:32]), .a111(CF[288+:32]),
    .clear(32'd0), .done_port(done), .idle_port(), .return_port(y));
  always @(posedge clk) if (rd) rp <= rp + 1;
  integer fd, k, r, n = 0, bad = 0, cyc, pops, maxc = 0;
  initial begin
    fd = $fopen("../vec/vectors_decim.txt", "r");
    repeat (3) @(posedge clk); rst <= 0;
    while (!$feof(fd)) begin
      r = 0; for (k = 0; k < 16; k = k + 1) r = r + $fscanf(fd, "%h", fifo[k]);
      r = r + $fscanf(fd, "%h", yexp);
      if (r == 17) begin
        rp = 0; start <= 1; @(posedge clk); start <= 0; cyc = 1;
        while (!done) begin @(posedge clk); cyc = cyc + 1; end
        if (rp !== 0) $display("call %0d popped %0d mod 16", n, rp);
        if (y !== yexp) begin if (bad < 5) $display("MISMATCH %0d got %h want %h", n, y, yexp); bad = bad + 1; end
        if (cyc > maxc) maxc = cyc; n = n + 1; @(posedge clk);
      end
    end
    $display("RESULT decim: calls=%0d mismatches=%0d clocks/call=%0d (budget 16 at 125 MS/s in)", n, bad, maxc);
    $finish;
  end
endmodule
