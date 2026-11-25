
`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_BRAM_top
//
// Description:
//   Self-checking testbench for parameterized BRAM_top.
//
//   BRAM configuration:
//     DATA_W = 32
//     DEPTH  = 4096
//
// Tests:
//   1. Check initial contents of all 4096 addresses from init.mem.
//   2. Write and read back several addresses.
//   3. Verify read-first behavior during a write.
//   4. Verify neighboring addresses are not corrupted.
//
// Expected initialization:
//   Address 0 = 32'h0000BEEF
//   Address 1 = 32'h0000CAFE
//   Other addresses = their address value.
//
// Result:
//   PASS if errors = 0
//   FAIL otherwise
//////////////////////////////////////////////////////////////////////////////////

module tb_BRAM_top;

    // -------------------------------------------------------------------------
    // BRAM parameters
    // -------------------------------------------------------------------------

    localparam DATA_W = 32;
    localparam DEPTH  = 4096;
    localparam ADDR_W = 12;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------

    reg clk = 0;
    reg en = 0;
    reg w_en = 0;

    reg [ADDR_W-1:0] addr = 0;
    reg [DATA_W-1:0] data_in = 0;

    wire [DATA_W-1:0] data_out;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------

    BRAM_top #(
        .DATA_W    (DATA_W),
        .DEPTH     (DEPTH),
        .ADDR_W    (ADDR_W)
    ) dut (
        .clk      (clk),
        .en       (en),
        .w_en     (w_en),
        .addr     (addr),
        .data_in  (data_in),
        .data_out (data_out)
    );

    // -------------------------------------------------------------------------
    // 100 MHz clock
    // -------------------------------------------------------------------------

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Error counter
    // -------------------------------------------------------------------------

    integer errors = 0;
    integer i;

    // -------------------------------------------------------------------------
    // Expected initial memory contents
    // -------------------------------------------------------------------------

    function [31:0] init_val;

        input [ADDR_W-1:0] a;

        begin

            if (a == 0)
                init_val = 32'h0000BEEF;

            else if (a == 1)
                init_val = 32'h0000CAFE;

            else
                init_val = {20'd0, a};

        end

    endfunction

    // -------------------------------------------------------------------------
    // Read and check task
    //
    // BRAM has a registered read.
    // Present address before rising edge.
    // Check data_out after the rising edge.
    // -------------------------------------------------------------------------

    task read_check;

        input [ADDR_W-1:0] a;
        input [31:0] expected;

        begin

            @(negedge clk);

            en    = 1'b1;
            w_en  = 1'b0;
            addr  = a;

            @(posedge clk);
            #1;

            if (data_out !== expected) begin

                errors = errors + 1;

                if (errors <= 10)
                    $display(
                        "ERROR @%0t: addr=%0d, read=%h, expected=%h",
                        $time, a, data_out, expected
                    );

            end

        end

    endtask

    // -------------------------------------------------------------------------
    // Write task
    // -------------------------------------------------------------------------

    task write;

        input [ADDR_W-1:0] a;
        input [31:0] d;

        begin

            @(negedge clk);

            en      = 1'b1;
            w_en    = 1'b1;
            addr    = a;
            data_in = d;

            @(posedge clk);
            #1;

            @(negedge clk);

            en   = 1'b0;
            w_en = 1'b0;

        end

    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------

    initial begin

        $display("======================================");
        $display("       32-bit BRAM TESTBENCH");
        $display("======================================");

        repeat (3) @(posedge clk);

        // ================================================================
        // TEST 1: Initial memory contents
        // ================================================================

        $display("");
        $display("TEST 1: Checking all 4096 initialized addresses...");

        for (i = 0; i < DEPTH; i = i + 1) begin

            read_check(i[ADDR_W-1:0],
                       init_val(i[ADDR_W-1:0]));

        end

        if (errors == 0)
            $display("TEST 1 PASSED: All initial contents are correct.");
        else
            $display("TEST 1 FAILED: Errors so far = %0d", errors);


        // ================================================================
        // TEST 2: Write then read back
        // ================================================================

        $display("");
        $display("TEST 2: Write then read back...");

        write(12'd5,    32'h12345678);
        write(12'd100,  32'hA5A5A5A5);
        write(12'd4095, 32'hFFFFFFFF);
        write(12'd2000, 32'hDEADBEEF);

        read_check(12'd5,    32'h12345678);
        read_check(12'd100,  32'hA5A5A5A5);
        read_check(12'd4095, 32'hFFFFFFFF);
        read_check(12'd2000, 32'hDEADBEEF);


        // ================================================================
        // TEST 3: Read-first behavior
        //
        // Before writing address 10, its original value is 10.
        // During the write clock edge, data_out must still show
        // the OLD value.
        // ================================================================

        $display("");
        $display("TEST 3: Checking read-first behavior...");

        @(negedge clk);

        en      = 1'b1;
        w_en    = 1'b1;
        addr    = 12'd10;
        data_in = 32'hCAFEBABE;

        @(posedge clk);
        #1;

        if (data_out !== init_val(12'd10)) begin

            errors = errors + 1;

            $display(
                "ERROR: Read-first failed. Read=%h, expected old=%h",
                data_out, init_val(12'd10)
            );

        end

        else begin

            $display("Read-first behavior PASSED.");

        end

        // Disable writing
        @(negedge clk);

        en   = 1'b0;
        w_en = 1'b0;

        // Check that the new value was stored
        read_check(12'd10, 32'hCAFEBABE);


        // ================================================================
        // TEST 4: Neighboring addresses unchanged
        // ================================================================

        $display("");
        $display("TEST 4: Checking neighboring addresses...");

        read_check(12'd4,  init_val(12'd4));
        read_check(12'd6,  init_val(12'd6));

        read_check(12'd9,  init_val(12'd9));
        read_check(12'd11, init_val(12'd11));


        // ================================================================
        // FINAL RESULT
        // ================================================================

        $display("");
        $display("======================================");

        if (errors == 0)
            $display("PASS: ALL BRAM TESTS PASSED.");
        else
            $display("FAIL: %0d ERRORS DETECTED.", errors);

        $display("======================================");

        $finish;

    end

endmodule
