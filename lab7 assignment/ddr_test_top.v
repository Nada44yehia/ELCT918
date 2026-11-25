`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// ddr_test_top.v  --  Nexys 4 DDR / Nexys A7 : DDR2 test through ram2ddr
//
// Uses ram2ddr_fixed.vhd (entity "ram2ddr", SRAM-style interface) with its
// ram_ack_o handshake -- no fixed wait times.
//
// Test: writes N_WORDS 16-bit words, reads them back, counts wrong words.
//
//   LED = 0001      waiting for MIG calibration
//   LED = 0002      writing
//   LED = 0004      reading back
//   LED = FFFF      PASS
//   LED = 10xx..x   FAIL (LED[15]=1, LED[14]=0, LED[13:0] = number of bad words)
//   LED = F00F      TIMEOUT: an access never got ram_ack_o (wrapper hung)
//   CPU_RESET       reruns the test (clocks and DDR keep running)
//
// Access protocol (4-phase handshake), all in the 100 MHz domain:
//   1. drive ram_a / ram_dq_i with CEN, OEN, WEN high; wait >= GAP cycles
//      and until ack is low
//   2. pull CEN low together with WEN (write) or OEN (read)
//   3. wait until ack goes high; for a read, sample ram_dq_o now
//   4. release CEN/WEN/OEN (back to step 1 for the next access)
//
// Requirements:
//   * clk_wiz_0: clk_out1 = 200 MHz, clk_out2 = 100 MHz, 'locked' enabled
//   * MIG IP "ddr" (3333 ps, 2:1, input 5000 ps, No Buffer, Use System Clock,
//     reset ACTIVE LOW, XADC Instantiation DISABLED for this ram2ddr variant)
//   * ram2ddr_fixed.vhd in the project (NOT the original ram2ddr.vhd)
//   * XDC false paths for the crossings (see bottom of this file)
// -----------------------------------------------------------------------------
module ddr_test_top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output reg  [15:0] LED,

    // DDR2 pins -- constrained by the MIG IP, not by your XDC
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

    // ------------------------------------------------------------------ params
    localparam integer N_WORDS = 8192;     // 16 KB
    localparam integer GAP     = 4;        // 40 ns address/data setup before CEN
    localparam [15:0]  TIMEOUT = 16'hFFFF; // ~655 us per access before giving up

    // ------------------------------------------------------------------ clocks
    wire clk200, clk100, locked;

    clk_wiz_0 u_clk (
        .clk_in1  (CLK100MHZ),
        .reset    (1'b0),        // never stop the clocks (keeps the ILA alive)
        .clk_out1 (clk200),      // 200 MHz -> ram2ddr / MIG
        .clk_out2 (clk100),      // 100 MHz -> this test logic
        .locked   (locked)
    );

    // reset for the 100 MHz domain: until locked, or while CPU_RESET pressed
    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk100 or negedge locked)
        if (!locked)          rst_sync <= 2'b11;
        else if (!CPU_RESETN) rst_sync <= 2'b11;
        else                  rst_sync <= {rst_sync[0], 1'b0};
    wire rst = rst_sync[1];

    // ------------------------------------------------------------------ ram2ddr
    (* mark_debug = "true" *) reg  [26:0] ram_a;
                              reg  [15:0] ram_dq_i;
    (* mark_debug = "true" *) wire [15:0] ram_dq_o;
    (* mark_debug = "true" *) reg         ram_cen, ram_oen, ram_wen;
    wire calib, ram_ack;

    ram2ddr u_ram (
        .clk_200MHz_i  (clk200),
        .rst_i         (~locked),      // active high
        .device_temp_i (12'd0),        // no temperature compensation (bench use)

        .ram_a         (ram_a),
        .ram_dq_i      (ram_dq_i),
        .ram_dq_o      (ram_dq_o),
        .ram_cen       (ram_cen),
        .ram_oen       (ram_oen),
        .ram_wen       (ram_wen),
        .ram_ub        (1'b0),         // 16-bit accesses
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

    // bring ack and calib into the 100 MHz domain (2-flop synchronizers)
    reg [1:0] ack_sync   = 2'b00;
    reg [1:0] calib_sync = 2'b00;
    always @(posedge clk100) begin
        ack_sync   <= {ack_sync[0],   ram_ack};
        calib_sync <= {calib_sync[0], calib};
    end
    (* mark_debug = "true" *) wire ack   = ack_sync[1];
    (* mark_debug = "true" *) wire cal_s = calib_sync[1];

    // ------------------------------------------------------------------ test pattern
    function [15:0] pattern(input [15:0] w);
        pattern = {w[7:0], ~w[7:0]} ^ {w[15:8], w[15:8]} ^ 16'h5A3C;
    endfunction

    // ------------------------------------------------------------------ FSM
    localparam S_CALIB    = 3'd0,
               S_W_SETUP  = 3'd1,
               S_W_ACCESS = 3'd2,
               S_R_SETUP  = 3'd3,
               S_R_ACCESS = 3'd4,
               S_DONE     = 3'd5,
               S_TIMEOUT  = 3'd6;

    (* mark_debug = "true" *) reg [2:0]  state;
    (* mark_debug = "true" *) reg [15:0] idx;
    (* mark_debug = "true" *) reg [15:0] errors;
                              reg [15:0] cnt;

    // byte address, stepping 2 bytes per 16-bit word
    wire [26:0] addr = {10'd0, idx, 1'b0};

    always @(posedge clk100) begin
        if (rst) begin
            state    <= S_CALIB;
            idx      <= 0;
            errors   <= 0;
            cnt      <= 0;
            ram_a    <= 0;
            ram_dq_i <= 0;
            ram_cen  <= 1'b1;
            ram_oen  <= 1'b1;
            ram_wen  <= 1'b1;
        end else begin
            case (state)

            // wait for the MIG to finish calibrating
            S_CALIB: begin
                if (cal_s) begin
                    idx   <= 0;
                    cnt   <= 0;
                    state <= S_W_SETUP;
                end
            end

            // ---------------- write
            S_W_SETUP: begin                    // address + data, enables high
                ram_a    <= addr;
                ram_dq_i <= pattern(idx);
                ram_cen  <= 1'b1;
                ram_wen  <= 1'b1;
                ram_oen  <= 1'b1;
                if (cnt >= GAP && !ack) begin   // setup time met, wrapper idle
                    cnt     <= 0;
                    ram_cen <= 1'b0;
                    ram_wen <= 1'b0;
                    state   <= S_W_ACCESS;
                end else if (cnt != TIMEOUT)
                    cnt <= cnt + 1'b1;
                else
                    state <= S_TIMEOUT;
            end

            S_W_ACCESS: begin                   // hold until the wrapper acks
                if (ack) begin
                    cnt     <= 0;
                    ram_cen <= 1'b1;
                    ram_wen <= 1'b1;
                    if (idx == N_WORDS-1) begin
                        idx   <= 0;
                        state <= S_R_SETUP;
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_W_SETUP;
                    end
                end else if (cnt != TIMEOUT)
                    cnt <= cnt + 1'b1;
                else
                    state <= S_TIMEOUT;
            end

            // ---------------- read
            S_R_SETUP: begin
                ram_a   <= addr;
                ram_cen <= 1'b1;
                ram_wen <= 1'b1;
                ram_oen <= 1'b1;
                if (cnt >= GAP && !ack) begin
                    cnt     <= 0;
                    ram_cen <= 1'b0;
                    ram_oen <= 1'b0;
                    state   <= S_R_ACCESS;
                end else if (cnt != TIMEOUT)
                    cnt <= cnt + 1'b1;
                else
                    state <= S_TIMEOUT;
            end

            S_R_ACCESS: begin
                if (ack) begin                  // ram_dq_o is valid now
                    cnt     <= 0;
                    ram_cen <= 1'b1;
                    ram_oen <= 1'b1;
                    if (ram_dq_o != pattern(idx))
                        errors <= errors + 1'b1;
                    if (idx == N_WORDS-1)
                        state <= S_DONE;
                    else begin
                        idx   <= idx + 1'b1;
                        state <= S_R_SETUP;
                    end
                end else if (cnt != TIMEOUT)
                    cnt <= cnt + 1'b1;
                else
                    state <= S_TIMEOUT;
            end

            S_DONE:    ;                        // stay until CPU_RESET
            S_TIMEOUT: begin                    // release the bus and stay
                ram_cen <= 1'b1;
                ram_oen <= 1'b1;
                ram_wen <= 1'b1;
            end

            default: state <= S_CALIB;
            endcase
        end
    end

    // ------------------------------------------------------------------ LEDs
    always @(posedge clk100) begin
        case (state)
            S_CALIB:                 LED <= 16'h0001;
            S_W_SETUP, S_W_ACCESS:   LED <= 16'h0002;
            S_R_SETUP, S_R_ACCESS:   LED <= 16'h0004;
            S_DONE:                  LED <= (errors == 0) ? 16'hFFFF
                                                          : {2'b10, errors[13:0]};
            S_TIMEOUT:               LED <= 16'hF00F;
            default:                 LED <= 16'h0000;
        endcase
    end

endmodule

// -----------------------------------------------------------------------------
// XDC lines needed for the clock-domain crossings into / out of the wrapper:
//
//   set_false_path -to   [get_cells u_ram/in_s1_reg[*]]
//   set_false_path -to   [get_cells u_ram/rst_s1_reg]
//   set_false_path -from [get_cells u_ram/ram_dq_o_reg[*]]
//   set_false_path -from [get_cells u_ram/ack_r_reg]
//   set_false_path -to   [get_cells calib_sync_reg[0]]
// -----------------------------------------------------------------------------
