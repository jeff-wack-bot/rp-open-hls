// kernel_wrap around the Bambu-generated kernels (build/hls_biquad{1,2}/).
// Bambu MINIMAL interface: clock, reset (sync, active high), start_port,
// done_port, one port per C argument, return_port. Inputs are not registered
// by Bambu, so the caller (rp_top / tb_kernel) holds x/coef/clear stable
// from start until done.
// Define KERNEL_NSEC1 for the single-section kernel (default: 2 sections).
module kernel_wrap (
  input  wire         clk, rst, start,
  input  wire [31:0]  x,
  input  wire [319:0] coef,
  input  wire         clear,
  output wire         done,
  output wire [31:0]  y
);
`define C(i) coef[32*(i) +: 32]
`ifdef KERNEL_NSEC1
  biquad1 k (.clock(clk), .reset(rst), .start_port(start), .done_port(done), .idle_port(),
             .x(x), .g(`C(0)), .c0(`C(1)), .c1(`C(2)), .a10(`C(3)), .a11(`C(4)),
             .clear({31'd0, clear}), .return_port(y));
`else
  biquad2 k (.clock(clk), .reset(rst), .start_port(start), .done_port(done), .idle_port(),
             .x(x),
             .g0(`C(0)), .c00(`C(1)), .c01(`C(2)), .a010(`C(3)), .a011(`C(4)),
             .g1(`C(5)), .c10(`C(6)), .c11(`C(7)), .a110(`C(8)), .a111(`C(9)),
             .clear({31'd0, clear}), .return_port(y));
`endif
`undef C
endmodule
