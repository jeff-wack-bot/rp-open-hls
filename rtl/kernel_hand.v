// Hand-written RTL of the same LIGO biquad cascade (comparison point and
// fallback for the HLS kernel). One section per clock, NSEC+1 cycle latency.
// Same port contract as the Bambu wrapper (kernel_wrap): start pulse, done
// pulse with y valid. Arithmetic identical to hls/biquad.c.
`ifndef KERNEL_NSEC
`define KERNEL_NSEC 2
`endif
module kernel_wrap #(parameter integer NSEC = `KERNEL_NSEC) (
  input  wire         clk, rst, start,
  input  wire [31:0]  x,
  input  wire [319:0] coef,
  input  wire         clear,
  output reg          done,
  output reg  [31:0]  y
);
  function [31:0] mac3(input [31:0] a, input [31:0] p, input [31:0] b,
                       input [31:0] q, input [31:0] c, input [31:0] r);
    reg signed [63:0] s;
    begin
      s = $signed(a) * $signed(p) + $signed(b) * $signed(q) + $signed(c) * $signed(r);
      mac3 = s[59:28];
    end
  endfunction
  reg [31:0] w [0:NSEC-1], u [0:NSEC-1];
  reg [31:0] v;
  reg [3:0]  sec;
  reg        busy;
  wire [31:0] g   = coef[160*sec +   0 +: 32], c0  = coef[160*sec +  32 +: 32],
              c1  = coef[160*sec +  64 +: 32], a10 = coef[160*sec +  96 +: 32],
              a11 = coef[160*sec + 128 +: 32];
  integer i;
  always @(posedge clk) begin
    done <= 1'b0;
    if (rst) begin
      busy <= 1'b0; sec <= 0;
      for (i = 0; i < NSEC; i = i + 1) begin w[i] <= 0; u[i] <= 0; end
    end else if (start) begin
      busy <= 1'b1; sec <= 0; v <= x;
      if (clear) for (i = 0; i < NSEC; i = i + 1) begin w[i] <= 0; u[i] <= 0; end
    end else if (busy) begin
      v      <= mac3(g, v, c0, w[sec], c1, u[sec]);
      w[sec] <= mac3(g, v, a10, w[sec], a11, u[sec]);
      u[sec] <= u[sec] + w[sec];
      if (sec == NSEC - 1) begin
        busy <= 1'b0; done <= 1'b1; y <= mac3(g, v, c0, w[sec], c1, u[sec]);
      end
      sec <= sec + 1;
    end
  end
endmodule
