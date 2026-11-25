
`timescale 1ns / 1ps

module top (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    output reg  [15:0] LED
);

    // BRAM configuration
    localparam DEPTH = 4096;
    localparam ADDR_W = $clog2(DEPTH);

    // Select test pattern
    localparam [1:0] PATTERN_SEL = 2'b10;
    // Controller status
    (* mark_debug = "true" *) wire test_busy;
    (* mark_debug = "true" *) wire test_done;
    (* mark_debug = "true" *) wire [31:0] mismatch_count;

    // Performance counters
    (* mark_debug = "true" *) wire [63:0] write_cycles;
    (* mark_debug = "true" *) wire [63:0] read_cycles;

    // Useful signals for debugging the BRAM operation
    (* mark_debug = "true" *) wire bram_en;
    (* mark_debug = "true" *) wire bram_w_en;
    (* mark_debug = "true" *) wire [11:0] bram_addr;
    // BRAM interface signals
 
    wire [31:0] bram_data_in;
    wire [31:0] bram_data_out;


  
    // Active-high reset for controller
    wire rst;
    assign rst = ~CPU_RESETN;

    // ------------------------------------------------
    // BRAM instance
    // ------------------------------------------------

    BRAM_top #(
        .DATA_W(32),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W)
    ) u_bram (
        .clk(CLK100MHZ),
        .en(bram_en),
        .w_en(bram_w_en),
        .addr(bram_addr),
        .data_in(bram_data_in),
        .data_out(bram_data_out)
    );

    // ------------------------------------------------
    // BRAM controller instance
    // ------------------------------------------------

    bram_ctrl #(
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W)
    ) u_bram_ctrl (
        .clk(CLK100MHZ),
        .rst(rst),
        .start(1'b1),
        .pattern_sel(PATTERN_SEL),

        .bram_en(bram_en),
        .bram_w_en(bram_w_en),
        .bram_addr(bram_addr),
        .bram_data_in(bram_data_in),
        .bram_data_out(bram_data_out),

        .busy(test_busy),
        .done(test_done),
        .mismatch_count(mismatch_count),

        .write_cycles(write_cycles),
        .read_cycles(read_cycles)
    );

    // ------------------------------------------------
    // LED status
    // ------------------------------------------------

    always @(*) begin

        if (rst)
            LED = 16'h0000;

        else if (test_busy)
            LED = 16'h0002;

        else if (test_done && mismatch_count == 0)
            LED = 16'hFFFF;

        else if (test_done)
            LED = {1'b1, mismatch_count[14:0]};

        else
            LED = 16'h0001;

    end

endmodule
