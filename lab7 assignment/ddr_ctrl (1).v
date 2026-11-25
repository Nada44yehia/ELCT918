
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// ddr_ctrl.v
// Traffic controller for ram2ddr_fixed.vhd (16-bit SRAM-style interface).
//
// A_START and A_END are inclusive 16-bit WORD addresses, not byte addresses.
// ram2ddr expects byte addresses, so ram_a = word_address * 2.
//
// pattern_sel:
//   2'b00 : 16'h0000
//   2'b01 : 16'hFFFF
//   2'b10 : word_address[15:0] XOR 16'hA5A5
//   2'b11 : alternating 16'hAAAA / 16'h5555 by word-address bit 0
//
// Four-phase ram_ack_o handshake for EACH access:
//   1) assert CEN plus WEN/OEN; wait for synchronized ack to go high
//   2) release CEN/WEN/OEN; wait for synchronized ack to return low
//
// Bandwidth measurement:
//   write_cycles: counts all controller clock cycles in the write pass.
//   read_cycles : counts all controller clock cycles in the read pass.
//
//   Both counters include PREP states and ACK handshake waiting cycles.
//   Calibration and the transition between passes are excluded.
//
// 64-bit counters are used to avoid overflow for large memory tests.
// -----------------------------------------------------------------------------

module ddr_ctrl #(
    parameter [25:0] A_START = 26'd0,
    parameter [25:0] A_END   = 26'd1023
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [1:0]  pattern_sel,

    input  wire        calib_i,
    input  wire        ram_ack_i,
    input  wire [15:0] ram_dq_o,

    output reg  [26:0] ram_a,
    output reg  [15:0] ram_dq_i,
    output reg         ram_cen,
    output reg         ram_oen,
    output reg         ram_wen,

    output reg         busy,
    output reg         done,
    output reg  [31:0] mismatch_count,

    // Bandwidth measurement counters
    output reg  [63:0] write_cycles,
    output reg  [63:0] read_cycles
);

    // -------------------------------------------------------------------------
    // Synchronize status signals from MIG clock domain
    // -------------------------------------------------------------------------

    reg [1:0] ack_sync;
    reg [1:0] calib_sync;

    wire ack   = ack_sync[1];
    wire calib = calib_sync[1];

    always @(posedge clk) begin
        if (rst) begin
            ack_sync   <= 2'b00;
            calib_sync <= 2'b00;
        end else begin
            ack_sync   <= {ack_sync[0], ram_ack_i};
            calib_sync <= {calib_sync[0], calib_i};
        end
    end

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------

    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_W_PREP1    = 4'd1,
        ST_W_PREP2    = 4'd2,
        ST_W_ACK_HI   = 4'd3,
        ST_W_ACK_LO   = 4'd4,
        ST_R_PREP1    = 4'd5,
        ST_R_PREP2    = 4'd6,
        ST_R_ACK_HI   = 4'd7,
        ST_R_ACK_LO   = 4'd8,
        ST_DONE       = 4'd9;

    reg [3:0] state;

    reg [25:0] address_word;
    reg [1:0] pattern_sel_latched;

    // -------------------------------------------------------------------------
    // Pattern generator
    // -------------------------------------------------------------------------

    function [15:0] make_pattern;
        input [1:0]  sel;
        input [25:0] word_addr;
        begin
            case (sel)
                2'b00: make_pattern = 16'h0000;
                2'b01: make_pattern = 16'hFFFF;
                2'b10: make_pattern = word_addr[15:0] ^ 16'hA5A5;
                default:
                    make_pattern = word_addr[0] ?
                                   16'h5555 : 16'hAAAA;
            endcase
        end
    endfunction

    wire [15:0] expected_data =
        make_pattern(pattern_sel_latched, address_word);

    // -------------------------------------------------------------------------
    // SRAM-style interface control
    // -------------------------------------------------------------------------

    always @* begin
        ram_a    = {address_word, 1'b0};
        ram_dq_i = expected_data;

        ram_cen = 1'b1;
        ram_oen = 1'b1;
        ram_wen = 1'b1;

        case (state)

            ST_W_ACK_HI: begin
                ram_cen = 1'b0;
                ram_wen = 1'b0;
            end

            ST_R_ACK_HI: begin
                ram_cen = 1'b0;
                ram_oen = 1'b0;
            end

            default: begin
                // Interface deselected
            end

        endcase
    end

    // -------------------------------------------------------------------------
    // Main FSM and bandwidth counters
    // -------------------------------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            state               <= ST_IDLE;
            address_word        <= A_START;
            pattern_sel_latched <= 2'b00;

            busy                <= 1'b0;
            done                <= 1'b0;

            mismatch_count      <= 32'd0;

            write_cycles        <= 64'd0;
            read_cycles         <= 64'd0;

        end else begin

            // -------------------------------------------------------------
            // Count elapsed cycles in each pass.
            //
            // The current state determines which counter increments.
            // Nonblocking assignments preserve the final count when the
            // FSM changes state at this clock edge.
            // -------------------------------------------------------------

            case (state)

                ST_W_PREP1,
                ST_W_PREP2,
                ST_W_ACK_HI,
                ST_W_ACK_LO:
                    write_cycles <= write_cycles + 1'b1;

                ST_R_PREP1,
                ST_R_PREP2,
                ST_R_ACK_HI,
                ST_R_ACK_LO:
                    read_cycles <= read_cycles + 1'b1;

                default: begin
                    // Counters hold their values outside the passes.
                end

            endcase

            // -------------------------------------------------------------
            // Main FSM
            // -------------------------------------------------------------

            case (state)

                // ---------------------------------------------------------
                // IDLE: wait for calibration and start
                // ---------------------------------------------------------

                ST_IDLE: begin

                    busy <= 1'b0;
                    done <= 1'b0;

                    if (start && calib && (A_END >= A_START)) begin

                        address_word        <= A_START;
                        pattern_sel_latched <= pattern_sel;

                        mismatch_count <= 32'd0;

                        write_cycles <= 64'd0;
                        read_cycles  <= 64'd0;

                        busy  <= 1'b1;
                        state <= ST_W_PREP1;

                    end
                end

                // ---------------------------------------------------------
                // WRITE PASS
                // ---------------------------------------------------------

                ST_W_PREP1: begin
                    state <= ST_W_PREP2;
                end

                ST_W_PREP2: begin
                    if (!ack)
                        state <= ST_W_ACK_HI;
                end

                // Assert write request until acknowledgement
                ST_W_ACK_HI: begin
                    if (ack)
                        state <= ST_W_ACK_LO;
                end

                // Wait for acknowledgement to return low
                ST_W_ACK_LO: begin

                    if (!ack) begin

                        if (address_word == A_END) begin

                            // All words have been written.
                            // Begin reading from the first address.
                            address_word <= A_START;
                            state <= ST_R_PREP1;

                        end else begin

                            address_word <= address_word + 1'b1;
                            state <= ST_W_PREP1;

                        end
                    end
                end

                // ---------------------------------------------------------
                // READ PASS
                // ---------------------------------------------------------

                ST_R_PREP1: begin
                    state <= ST_R_PREP2;
                end

                ST_R_PREP2: begin
                    if (!ack)
                        state <= ST_R_ACK_HI;
                end

                // Read data is valid when acknowledgement goes high
                ST_R_ACK_HI: begin

                    if (ack) begin

                        if (ram_dq_o != expected_data)
                            mismatch_count <= mismatch_count + 1'b1;

                        state <= ST_R_ACK_LO;

                    end
                end

                // Wait for acknowledgement to return low
                ST_R_ACK_LO: begin

                    if (!ack) begin

                        if (address_word == A_END) begin

                            // Entire read pass completed.
                            state <= ST_DONE;

                        end else begin

                            address_word <= address_word + 1'b1;
                            state <= ST_R_PREP1;

                        end
                    end
                end

                // ---------------------------------------------------------
                // DONE: retain counters and mismatch count
                // ---------------------------------------------------------

                ST_DONE: begin

                    busy <= 1'b0;
                    done <= 1'b1;

                    // Require start to be released before another run.
                    if (!start)
                        state <= ST_IDLE;

                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule
