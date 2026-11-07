# ADC clock P pin used single-ended (bench only), 1PPS on E1 DIO0_P (exp_p_io[0]), LED0
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS18} [get_ports clk_i]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports pps_i]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports led_o]
create_clock -period 8.000 [get_ports clk_i]
