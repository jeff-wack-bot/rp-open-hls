set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS18} [get_ports clk]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports led]
create_clock -period 3.333 [get_ports clk]
