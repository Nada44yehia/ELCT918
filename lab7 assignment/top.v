
`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name: top
// Description:
//   Full 128 MiB DDR2 memory test on Nexys 4 DDR.
//
//   Writes a selected pattern to all 2^26 16-bit words,
//   reads them back, and counts mismatches.
//
// LED status:
//   0001       Waiting for DDR calibration
//   0002       Memory test running
//   FFFF       PASS: no mismatches
//   1xxxx      FAIL: mismatch count (lower 15 bits)
//
// Press CPU_RESET to restart the test.
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter [25:0] A_START     = 26'd0,
    parameter [25:0] A_END       = 26'd67108863,
    parameter [1:0]  PATTERN_SEL = 2'b10
)(
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output reg  [15:0] LED,

    // DDR2 pins
    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    output wire        ddr2_ras_n,
    output wire        ddr2_cas_n,
    output wire        ddr2_we_n,
    output wire [0:0]  ddr2_ck_p,
    output wire [0:0]  ddr2_ck_n,
    output wire [0:0]  ddr2_cke,
    output wire [0:0]  ddr2_cs_n,
    output wire [1:0]  ddr2_dm,
    output wire [0:0]  ddr2_odt,
    inout  wire [15:0] ddr2_dq,
    inout  wire [1:0]  ddr2_dqs_p,
    inout  wire [1:0]  ddr2_dqs_n
);

    // -------------------------------------------------------------------------
    // Clock generation
    //
    // Configure Clocking Wizard:
    //   clk_out1 = 300 MHz (MIG system clock)
    //   clk_out2 = 100 MHz (DDR controller clock)
    //
    // This assumes MIG Input Clock Period = 3333 ps.
    // -------------------------------------------------------------------------

    wire clk300;
    wire clk100;
    wire locked;
 (* MARK_DEBUG = "TRUE" *) wire [63:0] write_cycles;
 (* MARK_DEBUG = "TRUE" *) wire [63:0] read_cycles;
    clk_wiz_0 u_clk (
        .clk_in1  (CLK100MHZ),
        .reset    (1'b0),
        .clk_out1 (clk300),
        .clk_out2 (clk100),
        .locked   (locked)
    );

    // -------------------------------------------------------------------------
    // Reset synchronizer for controller clock domain
    // -------------------------------------------------------------------------

    reg [1:0] rst_sync = 2'b11;

    always @(posedge clk100 or negedge locked) begin
        if (!locked)
            rst_sync <= 2'b11;
        else if (!CPU_RESETN)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end

    wire rst = rst_sync[1];

    // -------------------------------------------------------------------------
    // SRAM-style interface between controller and DDR2 wrapper
    // -------------------------------------------------------------------------

    wire [26:0] ram_a;
    wire [15:0] ram_dq_i;
    wire [15:0] ram_dq_o;

    wire ram_cen;
    wire ram_oen;
    wire ram_wen;

    wire calib;
    wire ram_ack;

    // -------------------------------------------------------------------------
    // MIG / DDR2 wrapper
    //
    // NOTE:
    // The VHDL wrapper port is currently named clk_200MHz_i.
    // It must receive the actual MIG system clock (300 MHz here).
    // -------------------------------------------------------------------------

    ram2ddr u_ram (
        .clk_200MHz_i  (clk300),
        .rst_i         (~locked),
        .device_temp_i (12'd0),

        .ram_a         (ram_a),
        .ram_dq_i      (ram_dq_i),
        .ram_dq_o      (ram_dq_o),
        .ram_cen       (ram_cen),
        .ram_oen       (ram_oen),
        .ram_wen       (ram_wen),

        // Both bytes enabled: full 16-bit accesses
        .ram_ub        (1'b0),
        .ram_lb        (1'b0),

        .calib_o       (calib),
        .ram_ack_o     (ram_ack),

        .ddr2_addr     (ddr2_addr),
        .ddr2_ba       (ddr2_ba),
        .ddr2_ras_n    (ddr2_ras_n),
        .ddr2_cas_n    (ddr2_cas_n),
        .ddr2_we_n     (ddr2_we_n),
        .ddr2_ck_p     (ddr2_ck_p),
        .ddr2_ck_n     (ddr2_ck_n),
        .ddr2_cke      (ddr2_cke),
        .ddr2_cs_n     (ddr2_cs_n),
        .ddr2_dm       (ddr2_dm),
        .ddr2_odt      (ddr2_odt),
        .ddr2_dq       (ddr2_dq),
        .ddr2_dqs_p    (ddr2_dqs_p),
        .ddr2_dqs_n    (ddr2_dqs_n)
    );

    // -------------------------------------------------------------------------
    // DDR traffic controller
    //
    // Tests word addresses:
    //   0 through 67,108,863
    //
    // start is tied high. The controller starts after calibration
    // and remains in DONE until reset.
    // -------------------------------------------------------------------------

   (* MARK_DEBUG = "TRUE" *) wire        test_busy;
   (* MARK_DEBUG = "TRUE" *) wire        test_done;
   (* MARK_DEBUG = "TRUE" *) wire [31:0] mismatch_count;

    ddr_ctrl #(
        .A_START (A_START),
        .A_END   (A_END)
    ) u_ddr_ctrl (
        .clk            (clk100),
        .rst            (rst),
        .write_cycles (write_cycles),
        .read_cycles  (read_cycles),
        .start          (1'b1),
        .pattern_sel    (PATTERN_SEL),

        .calib_i        (calib),
        .ram_ack_i      (ram_ack),
        .ram_dq_o       (ram_dq_o),

        .ram_a          (ram_a),
        .ram_dq_i       (ram_dq_i),
        .ram_cen        (ram_cen),
        .ram_oen        (ram_oen),
        .ram_wen        (ram_wen),

        .busy           (test_busy),
        .done           (test_done),
        .mismatch_count (mismatch_count)
    );

    // -------------------------------------------------------------------------
    // Calibration synchronizer for LED indication
    // -------------------------------------------------------------------------

    reg [1:0] calib_led_sync = 2'b00;

    always @(posedge clk100) begin
        if (rst)
            calib_led_sync <= 2'b00;
        else
            calib_led_sync <= {calib_led_sync[0], calib};
    end

    wire calib_led = calib_led_sync[1];

    // -------------------------------------------------------------------------
    // LED status
    // -------------------------------------------------------------------------

    always @(posedge clk100) begin
        if (rst) begin
            LED <= 16'h0000;
        end
        else if (!calib_led) begin
            LED <= 16'h0001;
        end
        else if (test_busy) begin
            LED <= 16'h0002;
        end
        else if (test_done) begin
            if (mismatch_count == 0)
                LED <= 16'hFFFF;
            else
                LED <= {1'b1, mismatch_count[14:0]};
        end
        else begin
            LED <= 16'h0000;
        end
    end

endmodule
