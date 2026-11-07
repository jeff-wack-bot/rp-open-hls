// Pin-limited bench around cds_io2 (rp-frontend-bot/fpga/rtl, unmodified) so it
// can be placed and routed stand-alone: every input bit comes from a shift
// chain fed by an LFSR (no constant propagation), every output is XOR-reduced
// onto one LED. Overhead: one FF per input bit (~310 FF) + XOR tree.
module cds_io2_bench (input wire clk_i, input wire pps_i, output wire led_o);
  localparam integer NODES = 15, DACS = 2;
  localparam integer NIN = 32 + 32 + 1 + 1 + 14*NODES + 1 + 1 + 14*DACS + 1 + 1;
  reg [31:0]    lfsr = 32'h1;
  reg [NIN-1:0] sh;
  always @(posedge clk_i) begin
    lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    sh   <= {sh[NIN-2:0], lfsr[31]};
  end
  wire [31:0] sys_rdata, m_addr, m_wdata;
  wire        sys_err, sys_ack, m_req, strobe_out;
  wire [14*DACS-1:0] dac_out;
  cds_io2 #(.TAPS(2), .DAC_CHANNELS(DACS), .NODES(NODES)) dut (
    .clk(clk_i), .rst_n(sh[0]),
    .sys_addr(sh[32:1]), .sys_wdata(sh[64:33]), .sys_wen(sh[65]), .sys_ren(sh[66]),
    .sys_rdata(sys_rdata), .sys_err(sys_err), .sys_ack(sys_ack),
    .nodes(sh[67 +: 14*NODES]), .trig_dsp(sh[67+14*NODES]), .trig_scope(sh[68+14*NODES]),
    .pps(pps_i),
    .dac_stock(sh[69+14*NODES +: 14*DACS]), .dac_out(dac_out),
    .m_req(m_req), .m_addr(m_addr), .m_wdata(m_wdata), .m_done(sh[69+14*NODES+14*DACS]),
    .strobe_out(strobe_out)
  );
  reg led;
  always @(posedge clk_i) led <= ^{sys_rdata, sys_err, sys_ack, dac_out, m_req, m_addr, m_wdata, strobe_out};
  assign led_o = led;
endmodule
