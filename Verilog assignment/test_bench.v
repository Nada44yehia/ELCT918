
`timescale 1ns/1ps

module tb;

    reg clk = 0;
    reg rst_n = 0;
    reg en = 0;
    reg [3:0] din = 0;

    wire [7:0] dout;
    wire flag;

    // Instantiate the black box
    mystery bb (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .din   (din),
        .dout  (dout),
        .flag  (flag)
    );

    // 10 ns clock
    always #5 clk = ~clk;


    // --------------------------------------------------------
    // Apply one input for one clock cycle
    // --------------------------------------------------------
    task step;
        input e;
        input [3:0] d;

        begin
            @(negedge clk);
            en  = e;
            din = d;

            @(posedge clk);
            #1;

            $display(
                "t=%0t  en=%b  din=%h  -> dout=%h  flag=%b",
                $time, e, d, dout, flag
            );
        end
    endtask


    // --------------------------------------------------------
    // Main experiment
    // --------------------------------------------------------
    initial begin

        $dumpfile("dump.vcd");
        $dumpvars(0, tb);

        // ====================================================
        // RESET
        // ====================================================

        rst_n = 0;
        en    = 0;
        din   = 0;

        repeat (2) @(posedge clk);
        #1;

        $display("");
        $display("========== AFTER RESET ==========");
        $display("dout=%h flag=%b", dout, flag);

        rst_n = 1;
        // ====================================================
        // EXPERIMENT 1
        // What happens when en = 0?
        // ====================================================

        $display("");
        $display("========== EXPERIMENT 1: en=0 ==========");

        step(0, 4'h5);
        step(0, 4'h9);
        step(0, 4'hA);
        step(0, 4'hF);


        // ====================================================
        // EXPERIMENT 2
        // Same plaintext repeatedly
        // ====================================================

        $display("");
        $display("========== EXPERIMENT 2: SAME INPUT ==========");

        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);
        step(1, 4'h5);


        // ====================================================
        // EXPERIMENT 3
        // Different inputs
        // ====================================================

        $display("");
        $display("========== EXPERIMENT 3: DIFFERENT INPUTS ==========");

        step(1, 4'h0);
        step(1, 4'h1);
        step(1, 4'h2);
        step(1, 4'h3);
        step(1, 4'h4);
        step(1, 4'h5);
        step(1, 4'h6);
        step(1, 4'h7);
        step(1, 4'h8);
        step(1, 4'h9);
        step(1, 4'hA);
        step(1, 4'hB);
        step(1, 4'hC);
        step(1, 4'hD);
        step(1, 4'hE);
        step(1, 4'hF);


        // ====================================================
        // EXPERIMENT 4
        // Does disabling en preserve the state?
        // ====================================================

        $display("");
        $display("========== EXPERIMENT 4: PAUSE ==========");

        step(1, 4'h3);
        step(1, 4'h7);

        step(0, 4'hA);
        step(0, 4'hB);
        step(0, 4'hC);

        step(1, 4'h3);
        step(1, 4'h7);
      

// EXPERIMENT 5: RESET BEFORE EVERY INPUT

      $display("\n========== EXPERIMENT 5: RESET EACH INPUT ==========");

for (int i = 0; i < 16; i++) begin

    // Apply reset
    @(negedge clk);
    rst_n = 1'b0;       
    en  = 1'b0;
    din = 4'h0;

    repeat (2) @(negedge clk);

    // Release reset and apply a new input
    rst_n = 1'b1;
    en  = 1'b1;
    din = i;

    // Allow the circuit to process the input
    @(posedge clk);
    #1;

    $display(
        "din=%h -> dout=%h | upper=%h | lower=%h",
        din, dout, dout[7:4], dout[3:0]
    );
end

// Finish with reset asserted
@(negedge clk);
en  = 1'b0;
rst_n = 1'b0;
      

// ============================================================
// EXPERIMENT 6: DISCOVER LOWER NIBBLE BEHAVIOR
// ============================================================

      $display("\n========== EXPERIMENT 6: LOWER NIBBLE ANALYSIS ==========");

// Test several input values independently
for (int i = 0; i < 16; i++) begin

    // Apply active-low reset
    @(negedge clk);
    rst_n = 1'b0;
    en    = 1'b0;
    din   = 4'h0;

    repeat (2) @(negedge clk);

    // Release reset and apply input
    rst_n = 1'b1;
    en    = 1'b1;
    din   = i;

    $display("\n--- din = %h ---", i);

    // Observe the first 8 enabled clock cycles
    repeat (8) begin
        @(posedge clk);
        #1;

        $display(
            "din=%h dout=%h | upper=%h lower=%h",
            din, dout, dout[7:4], dout[3:0]
        );
    end
end

// Finish with reset asserted
@(negedge clk);
en    = 1'b0;
rst_n = 1'b0;



        // ====================================================
        // FINISH
        // ====================================================

        $display("");
        $display("========== END ==========");

        $finish;

    end

endmodule