
`timescale 1ns/1ps

module tb_sparse_and_baseline;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n;

    // ================================================
    // Vector loading interface
    // ================================================

    reg vec_we;
    reg [4:0] vec_waddr;
    reg signed [7:0] vec_wdata;

    // ================================================
    // CSB loading interface
    // ================================================

    reg csb_we;
    reg [3:0] csb_waddr;
    reg signed [7:0] csb_wdata;
    reg [2:0] csb_idata;

    // ================================================
    // Sparse PE control
    // ================================================

    reg sparse_start;

    wire sparse_busy;
    wire sparse_done;

    wire signed [31:0] sparse_result;
    wire sparse_row_done;

    // ================================================
    // Baseline loading and control
    // ================================================

    reg baseline_weight_we;
    reg [4:0] baseline_weight_waddr;
    reg signed [7:0] baseline_weight_wdata;

    reg baseline_start;

    wire baseline_busy;
    wire baseline_done;
    wire signed [31:0] baseline_result;

    // ================================================
    // Python-generated data memories
    // ================================================

    reg [7:0] vector_data [0:31];
    reg [7:0] dense_weight_data [0:31];

    reg [7:0] csb_weight_data [0:15];
    reg [7:0] csb_index_data [0:15];

    // ================================================
    // File and test variables
    // ================================================

    integer expected_file;
    integer expected_result;

    integer i;
    integer timeout_count;

    reg sparse_finished;
    reg baseline_finished;

    // ================================================
    // DUT 1: Sparse PE with internal CSB controller
    // ================================================

    sparse_pe u_sparse_pe (
        .clk(clk),
        .rst_n(rst_n),

        // Vector loading
        .vec_we(vec_we),
        .vec_waddr(vec_waddr),
        .vec_wdata(vec_wdata),

        // CSB loading
        .csb_we(csb_we),
        .csb_waddr(csb_waddr),
        .csb_wdata(csb_wdata),
        .csb_idata(csb_idata),

        // Processing control
        .start(sparse_start),
        .busy(sparse_busy),
        .done(sparse_done),

        // Result
        .result(sparse_result),
        .row_done(sparse_row_done)
    );


    // ================================================
    // DUT 2: Dense 4-lane baseline PE
    // ================================================

    baseline_pe u_baseline_pe (
        .clk(clk),
        .rst_n(rst_n),

        .vec_we(vec_we),
        .vec_waddr(vec_waddr),
        .vec_wdata(vec_wdata),

        .weight_we(baseline_weight_we),
        .weight_waddr(baseline_weight_waddr),
        .weight_wdata(baseline_weight_wdata),

        .start(baseline_start),
        .busy(baseline_busy),
        .done(baseline_done),
        .result(baseline_result)
    );


    // ================================================
    // Main test
    // ================================================

    initial begin

        $dumpfile("lab5_comparison.vcd");
        $dumpvars(0, tb_sparse_and_baseline);

        // --------------------------------------------
        // Initialize inputs
        // --------------------------------------------

        rst_n = 1'b0;

        vec_we = 1'b0;
        vec_waddr = 5'd0;
        vec_wdata = 8'sd0;

        csb_we = 1'b0;
        csb_waddr = 4'd0;
        csb_wdata = 8'sd0;
        csb_idata = 3'd0;

        sparse_start = 1'b0;

        baseline_weight_we = 1'b0;
        baseline_weight_waddr = 5'd0;
        baseline_weight_wdata = 8'sd0;

        baseline_start = 1'b0;

        sparse_finished = 1'b0;
        baseline_finished = 1'b0;

        timeout_count = 0;

        // --------------------------------------------
        // Read Python-generated files
        // --------------------------------------------

        $readmemh("vector.mem", vector_data);
        $readmemh("pruned_weights.mem", dense_weight_data);
        $readmemh("csb_weights.mem", csb_weight_data);
        $readmemh("csb_indices.mem", csb_index_data);

        expected_file = $fopen("expected_result.txt", "r");

        if (expected_file == 0) begin
            $display("ERROR: Could not open expected_result.txt");
            $finish;
        end

        if ($fscanf(expected_file, "%d", expected_result) != 1) begin
            $display("ERROR: Could not read expected result");
            $finish;
        end

        $fclose(expected_file);

        $display("------------------------------------------");
        $display("Starting FSS sparse PE + dense baseline");
        $display("Python expected result = %0d", expected_result);
        $display("------------------------------------------");


        // --------------------------------------------
        // Reset
        // --------------------------------------------

        repeat (3) @(negedge clk);
        rst_n = 1'b1;


        // --------------------------------------------
        // Load vector into both designs
        // --------------------------------------------

        $display("Loading vector...");

        for (i = 0; i < 32; i = i + 1) begin

            @(negedge clk);

            vec_we = 1'b1;
            vec_waddr = i;
            vec_wdata = $signed(vector_data[i]);

        end

        @(negedge clk);
        vec_we = 1'b0;


        // --------------------------------------------
        // Load CSB weights and indices
        // into the internal CSB controller
        // --------------------------------------------

        $display("Loading CSB memories...");

        for (i = 0; i < 16; i = i + 1) begin

            @(negedge clk);

            csb_we = 1'b1;
            csb_waddr = i;

            csb_wdata = $signed(csb_weight_data[i]);
            csb_idata = csb_index_data[i][2:0];

        end

        @(negedge clk);
        csb_we = 1'b0;


        // --------------------------------------------
        // Load pruned weights into baseline
        // --------------------------------------------

        $display("Loading baseline weights...");

        for (i = 0; i < 32; i = i + 1) begin

            @(negedge clk);

            baseline_weight_we = 1'b1;
            baseline_weight_waddr = i;
            baseline_weight_wdata =
                $signed(dense_weight_data[i]);

        end

        @(negedge clk);
        baseline_weight_we = 1'b0;

        $display("All memories loaded.");


        // --------------------------------------------
        // Start both PEs
        // --------------------------------------------

        @(negedge clk);

        sparse_start = 1'b1;
        baseline_start = 1'b1;

        @(negedge clk);

        sparse_start = 1'b0;
        baseline_start = 1'b0;

        $display("Sparse PE started.");
        $display("Baseline PE started.");


        // --------------------------------------------
        // Wait for both PEs to finish
        // --------------------------------------------

        timeout_count = 0;

        while ((!sparse_finished || !baseline_finished) &&
               timeout_count < 50) begin

            @(negedge clk);

            if (sparse_row_done)
                sparse_finished = 1'b1;

            if (baseline_done)
                baseline_finished = 1'b1;

            timeout_count = timeout_count + 1;

        end


        // --------------------------------------------
        // Display results
        // --------------------------------------------

        #1;

        $display("");
        $display("==========================================");
        $display("       FSS PE COMPARISON RESULTS");
        $display("==========================================");

        $display("Python reference = %0d", expected_result);
        $display("Sparse PE result = %0d", sparse_result);
        $display("Baseline result  = %0d", baseline_result);

        $display("------------------------------------------");

        $display("Sparse busy = %0b", sparse_busy);
        $display("Sparse done = %0b", sparse_done);
        $display("Sparse row_done observed = %0b", sparse_finished);

        $display("Baseline busy = %0b", baseline_busy);
        $display("Baseline done observed = %0b", baseline_finished);

        $display("------------------------------------------");

        if (timeout_count >= 50) begin

            $display("TEST FAILED: timeout waiting for completion.");

        end

        else if (!sparse_finished || !baseline_finished) begin

            $display("TEST FAILED: one or both PEs did not complete.");

        end

        else if (($signed(sparse_result) == expected_result) &&
                 ($signed(baseline_result) == expected_result)) begin

            $display("TEST PASSED: both RTL designs match Python.");

        end

        else begin

            $display("TEST FAILED: output mismatch.");

        end

        $display("==========================================");

        $finish;

    end

endmodule
