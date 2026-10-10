
// Code your testbench here
// or browse Examples

`timescale 1ns/1ps

module tb;

    reg clk;
    reg rst_n;
    reg en;
    reg [3:0] din;

    wire [7:0] ref_dout;
    wire ref_flag;
    wire [7:0] sol_dout;
    wire sol_flag;

    integer cycle;
    integer mismatch_count;
    integer seed;
    integer random_value;
    integer test_num;

    // ============================================================
    // Save the last 4 enabled inputs and outputs
    // ============================================================

    reg [3:0] din_history [0:3];
    reg [7:0] dout_history [0:3];

    integer i;

    // Reference design
    mystery bb (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .din(din),
        .dout(ref_dout),
        .flag(ref_flag)
    );

    // Your readable RTL solution
    solution dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .din(din),
        .dout(sol_dout),
        .flag(sol_flag)
    );

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin

        $dumpfile("dump.vcd");
        $dumpvars(0, tb);

        rst_n = 0;
        en = 0;
        din = 0;
        cycle = 0;
        mismatch_count = 0;

        // Initialize history
        for (i = 0; i < 4; i = i + 1) begin
            din_history[i]  = 4'h0;
            dout_history[i] = 8'h00;
        end

        $display("Starting 5 randomized tests...");
        $display("Total cycles: 50000");

        // ========================================================
        // RANDOMIZED TESTS
        // ========================================================

        for (test_num = 1;
             test_num <= 5;
             test_num = test_num + 1) begin

            seed = 12345 + test_num * 9876;

            $display("");
            $display("========== TEST %0d, SEED=%0d ==========",
                     test_num, seed);

            // Reset before each test
            @(negedge clk);
            rst_n = 0;
            en = 0;
            din = 0;

            repeat (2) @(negedge clk);
            rst_n = 1;

            // Clear history after reset
            for (i = 0; i < 4; i = i + 1) begin
                din_history[i]  = 4'h0;
                dout_history[i] = 8'h00;
            end

            for (cycle = 1; cycle <= 10000;
                 cycle = cycle + 1) begin

                @(negedge clk);

                // Random data
                random_value = $random(seed);
                din = random_value & 4'hF;

                // Random enable
                random_value = $random(seed);
                en = random_value & 1;

                // Vary reset patterns
                random_value = $random(seed);

                case (test_num)
                    1: rst_n = ((random_value % 20) != 0);
                    2: rst_n = ((random_value % 10) != 0);
                    3: rst_n = ((random_value % 50) != 0);
                    4: rst_n = ((cycle % 97) != 0);
                    5: rst_n = ((random_value % 7) != 0);
                endcase

                @(posedge clk);
                #1;

                // =================================================
                // Compare reference and solution
                // =================================================

                if ((ref_dout !== sol_dout) ||
                    (ref_flag !== sol_flag)) begin

                    mismatch_count = mismatch_count + 1;

                    $display(
                        "MISMATCH test=%0d cycle=%0d rst_n=%b en=%b din=%h | REF=%h flag=%b | SOL=%h flag=%b",
                        test_num, cycle, rst_n, en, din,
                        ref_dout, ref_flag,
                        sol_dout, sol_flag
                    );
                end

                // =================================================
                // Save history on enabled cycles
                // =================================================

                if (en && rst_n) begin

                    // Shift old values
                    din_history[0]  = din_history[1];
                    din_history[1]  = din_history[2];
                    din_history[2]  = din_history[3];
                    din_history[3]  = din;

                    dout_history[0] = dout_history[1];
                    dout_history[1] = dout_history[2];
                    dout_history[2] = dout_history[3];
                    dout_history[3] = ref_dout;

                end

                // =================================================
                // If flag goes high, print the last 4
                // =================================================

                if (ref_flag === 1'b1) begin

                    $display("");
                    $display("****************************************");
                    $display("FLAG HIGH!");
                    $display("Test  = %0d", test_num);
                    $display("Cycle = %0d", cycle);

                    $display(
                        "Last 4 inputs : %h %h %h %h",
                        din_history[0],
                        din_history[1],
                        din_history[2],
                        din_history[3]
                    );

                    $display(
                        "Last 4 outputs: %h %h %h %h",
                        dout_history[0][3:0],
                        dout_history[1][3:0],
                        dout_history[2][3:0],
                        dout_history[3][3:0]
                    );

                    $display(
                        "Full outputs  : %h %h %h %h",
                        dout_history[0],
                        dout_history[1],
                        dout_history[2],
                        dout_history[3]
                    );

                    $display("****************************************");
                    $display("");
                end

            end
        end

        // ========================================================
        // FINAL SUMMARY
        // ========================================================

        $display("");
        $display("========== FINAL SUMMARY ==========");
        $display("Total cycles: 50000");
        $display("Total mismatches: %0d", mismatch_count);

        if (mismatch_count == 0)
            $display("PASS: No mismatches detected.");
        else
            $display("FAIL: Mismatches detected.");

 
        // ==========================================
        // DIRECTED TEST: Find the CAFE sequence
        // ==========================================

        $display("");
        $display("========== CAFE PASSWORD TEST ==========");

        // Reset the reference and solution
        rst_n = 0;
        en = 0;
        din = 0;

        repeat (2) @(negedge clk);

        // Apply first input immediately after reset
        rst_n = 1;
        en = 1;
        din = 4'h6;

        // Cycle 1
        @(posedge clk);
        #1;
        $display("Cycle 1: din=%h dout=%h flag=%b",
                 din, ref_dout, ref_flag);

        // Cycle 2
        @(negedge clk);
        din = 4'h3;
        @(posedge clk);
        #1;
        $display("Cycle 2: din=%h dout=%h flag=%b",
                 din, ref_dout, ref_flag);

        // Cycle 3
        @(negedge clk);
        din = 4'hB;
        @(posedge clk);
        #1;
        $display("Cycle 3: din=%h dout=%h flag=%b",
                 din, ref_dout, ref_flag);

        // Cycle 4
        @(negedge clk);
        din = 4'h9;
        @(posedge clk);
        #1;
        $display("Cycle 4: din=%h dout=%h flag=%b",
                 din, ref_dout, ref_flag);

        if (ref_flag === 1'b1)
            $display("PASS: CAFE password detected!");
        else
            $display("FAIL: Expected flag to be high.");

        // Reset before starting randomized tests
        @(negedge clk);
        rst_n = 0;
        en = 0;
        din = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;

    end

endmodule

