## =============================================================================
## nexys4ddr_ddr_test.xdc
## Constraints for ddr_test_top.v + ram2ddr_fixed.vhd
## Board: Digilent Nexys 4 DDR / Nexys A7-100T  (xc7a100tcsg324-1)
##
## NOTE: The DDR2 pins (ddr2_*) are NOT constrained here. The MIG IP ("ddr")
##       carries its own pin/IO-standard constraints. Do not add them again.
## NOTE: If you run "Set Up Debug" for the ILA, Vivado appends its debug-core
##       constraints at the end of this file. That is expected.
## =============================================================================

## -----------------------------------------------------------------------------
## Clock: 100 MHz board oscillator
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports CLK100MHZ]

## -----------------------------------------------------------------------------
## Reset: CPU_RESET push-button (active low)
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

## -----------------------------------------------------------------------------
## LEDs
## -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]

## -----------------------------------------------------------------------------
## Clock-domain crossings between the test logic (100 MHz, clk_out2) and the
## ram2ddr wrapper / MIG (ui_clk). All of these are synchronized or held
## stable by the handshake, so they must not be timed as single-cycle paths.
## -----------------------------------------------------------------------------
# user inputs -> wrapper's first synchronizer stage
set_false_path -to [get_cells {u_ram/in_s1_reg[*]}]
set_false_path -to [get_cells u_ram/rst_s1_reg]
# wrapper read data -> test logic (stable before ack is raised)
set_false_path -from [get_cells {u_ram/ram_dq_o_reg[*]}]
# wrapper ack -> test logic's 2-flop synchronizer
set_false_path -from [get_cells u_ram/ack_r_reg]
# MIG calibration flag -> test logic's 2-flop synchronizer
set_false_path -to [get_cells {u_ddr_ctrl/calib_sync_reg[0]}]

## -----------------------------------------------------------------------------
## Configuration / bitstream
## -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

## -----------------------------------------------------------------------------
## Slide switches SW[15:0] (uncomment the ones your top level uses)
## NOTE: SW[8] and SW[9] sit in a 1.8 V bank -> LVCMOS18
## -----------------------------------------------------------------------------
#set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { SW[0]  }]
#set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { SW[1]  }]
#set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports { SW[2]  }]
#set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports { SW[3]  }]
#set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports { SW[4]  }]
#set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports { SW[5]  }]
#set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { SW[6]  }]
#set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports { SW[7]  }]
#set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS18 } [get_ports { SW[8]  }]
#set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS18 } [get_ports { SW[9]  }]
#set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { SW[10] }]
#set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { SW[11] }]
#set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports { SW[12] }]
#set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { SW[13] }]
#set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports { SW[14] }]
#set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports { SW[15] }]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list u_clk/inst/clk_out2]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 64 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {read_cycles[0]} {read_cycles[1]} {read_cycles[2]} {read_cycles[3]} {read_cycles[4]} {read_cycles[5]} {read_cycles[6]} {read_cycles[7]} {read_cycles[8]} {read_cycles[9]} {read_cycles[10]} {read_cycles[11]} {read_cycles[12]} {read_cycles[13]} {read_cycles[14]} {read_cycles[15]} {read_cycles[16]} {read_cycles[17]} {read_cycles[18]} {read_cycles[19]} {read_cycles[20]} {read_cycles[21]} {read_cycles[22]} {read_cycles[23]} {read_cycles[24]} {read_cycles[25]} {read_cycles[26]} {read_cycles[27]} {read_cycles[28]} {read_cycles[29]} {read_cycles[30]} {read_cycles[31]} {read_cycles[32]} {read_cycles[33]} {read_cycles[34]} {read_cycles[35]} {read_cycles[36]} {read_cycles[37]} {read_cycles[38]} {read_cycles[39]} {read_cycles[40]} {read_cycles[41]} {read_cycles[42]} {read_cycles[43]} {read_cycles[44]} {read_cycles[45]} {read_cycles[46]} {read_cycles[47]} {read_cycles[48]} {read_cycles[49]} {read_cycles[50]} {read_cycles[51]} {read_cycles[52]} {read_cycles[53]} {read_cycles[54]} {read_cycles[55]} {read_cycles[56]} {read_cycles[57]} {read_cycles[58]} {read_cycles[59]} {read_cycles[60]} {read_cycles[61]} {read_cycles[62]} {read_cycles[63]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 64 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {write_cycles[0]} {write_cycles[1]} {write_cycles[2]} {write_cycles[3]} {write_cycles[4]} {write_cycles[5]} {write_cycles[6]} {write_cycles[7]} {write_cycles[8]} {write_cycles[9]} {write_cycles[10]} {write_cycles[11]} {write_cycles[12]} {write_cycles[13]} {write_cycles[14]} {write_cycles[15]} {write_cycles[16]} {write_cycles[17]} {write_cycles[18]} {write_cycles[19]} {write_cycles[20]} {write_cycles[21]} {write_cycles[22]} {write_cycles[23]} {write_cycles[24]} {write_cycles[25]} {write_cycles[26]} {write_cycles[27]} {write_cycles[28]} {write_cycles[29]} {write_cycles[30]} {write_cycles[31]} {write_cycles[32]} {write_cycles[33]} {write_cycles[34]} {write_cycles[35]} {write_cycles[36]} {write_cycles[37]} {write_cycles[38]} {write_cycles[39]} {write_cycles[40]} {write_cycles[41]} {write_cycles[42]} {write_cycles[43]} {write_cycles[44]} {write_cycles[45]} {write_cycles[46]} {write_cycles[47]} {write_cycles[48]} {write_cycles[49]} {write_cycles[50]} {write_cycles[51]} {write_cycles[52]} {write_cycles[53]} {write_cycles[54]} {write_cycles[55]} {write_cycles[56]} {write_cycles[57]} {write_cycles[58]} {write_cycles[59]} {write_cycles[60]} {write_cycles[61]} {write_cycles[62]} {write_cycles[63]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {mismatch_count[0]} {mismatch_count[1]} {mismatch_count[2]} {mismatch_count[3]} {mismatch_count[4]} {mismatch_count[5]} {mismatch_count[6]} {mismatch_count[7]} {mismatch_count[8]} {mismatch_count[9]} {mismatch_count[10]} {mismatch_count[11]} {mismatch_count[12]} {mismatch_count[13]} {mismatch_count[14]} {mismatch_count[15]} {mismatch_count[16]} {mismatch_count[17]} {mismatch_count[18]} {mismatch_count[19]} {mismatch_count[20]} {mismatch_count[21]} {mismatch_count[22]} {mismatch_count[23]} {mismatch_count[24]} {mismatch_count[25]} {mismatch_count[26]} {mismatch_count[27]} {mismatch_count[28]} {mismatch_count[29]} {mismatch_count[30]} {mismatch_count[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list test_busy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list test_done]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk100]
