## ============================================================
## sparse_pe.xdc  --  Nexys4 DDR (xc7a100tcsg324-1)
## Every port is mapped to a pin that is safe to drive:
##   switches / buttons / PMOD headers for inputs,
##   LEDs / PMOD headers for outputs.
## Nothing lands on DDR, Ethernet, USB or other shared nets.
## ============================================================

## ---------- Configuration ----------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ---------- Clock: on-board 100 MHz oscillator ----------
## The oscillator is fixed at 100 MHz, so the period must be 10 ns.
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -name clk -period 13.000 [get_ports clk]

## ---------- Control inputs: buttons ----------
## CPU_RESETN is active-low, matching rst_n.
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports rst_n]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports start]  ;# BTNC
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports csb_we] ;# BTNU
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports vec_we] ;# BTND

## ---------- vec_wdata[7:0]: switches SW0-SW7 ----------
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[0]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[1]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[2]}]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[3]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[4]}]
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[5]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[6]}]
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports {vec_wdata[7]}]

## ---------- csb_wdata[7:0]: switches SW8-SW15 ----------
## SW8 and SW9 sit in a 1.8 V bank, hence LVCMOS18.
set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS18 } [get_ports {csb_wdata[0]}]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS18 } [get_ports {csb_wdata[1]}]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[2]}]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[3]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[4]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[5]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[6]}]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {csb_wdata[7]}]

## ---------- Addresses / indices: PMOD JA + JB (inputs) ----------
## Pulled down so unconnected header pins read 0 instead of floating.
## JA -> csb_waddr[3:0], csb_idata[2:0], vec_waddr[0]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_waddr[0]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_waddr[1]}]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_waddr[2]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_waddr[3]}]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_idata[0]}]
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_idata[1]}]
set_property -dict { PACKAGE_PIN F18 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {csb_idata[2]}]
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {vec_waddr[0]}]
## JB -> vec_waddr[4:1]
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {vec_waddr[1]}]
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {vec_waddr[2]}]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {vec_waddr[3]}]
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {vec_waddr[4]}]

## ---------- Status outputs: RGB LED16 ----------
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports busy]     ;# LED16_R
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports done]     ;# LED16_G
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports row_done] ;# LED16_B

## ---------- result[15:0]: LEDs LD0-LD15 ----------
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {result[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {result[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {result[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {result[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {result[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {result[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {result[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {result[7]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {result[8]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {result[9]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {result[10]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {result[11]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {result[12]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {result[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {result[14]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {result[15]}]

## ---------- result[31:16]: PMOD JC + JD (outputs) ----------
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports {result[16]}]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports {result[17]}]
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports {result[18]}]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports {result[19]}]
set_property -dict { PACKAGE_PIN E7  IOSTANDARD LVCMOS33 } [get_ports {result[20]}]
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports {result[21]}]
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports {result[22]}]
set_property -dict { PACKAGE_PIN E6  IOSTANDARD LVCMOS33 } [get_ports {result[23]}]
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports {result[24]}]
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports {result[25]}]
set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports {result[26]}]
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports {result[27]}]
set_property -dict { PACKAGE_PIN H2  IOSTANDARD LVCMOS33 } [get_ports {result[28]}]
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports {result[29]}]
set_property -dict { PACKAGE_PIN G2  IOSTANDARD LVCMOS33 } [get_ports {result[30]}]
set_property -dict { PACKAGE_PIN F3  IOSTANDARD LVCMOS33 } [get_ports {result[31]}]

## ---------- I/O timing ----------
## Switches, buttons and LEDs are asynchronous to clk, so I/O paths are
## not timed; only the internal datapath is checked against 10 ns.
set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_false_path -to   [get_ports -filter {DIRECTION == OUT}]
