// ============================================================
// fpga_top.v  --  Nexys4 DDR wrapper for sparse_pe
//
// What it does on the board:
//   1. Makes a 13 ns (76.923 MHz) clock from the 100 MHz oscillator.
//   2. After reset, automatically loads the SAME Python data the
//      testbench uses (vector.mem, csb_weights.mem, csb_indices.mem)
//      into sparse_pe, exactly like the TB loading loops.
//   3. Pulses start, waits for row_done, latches result.
//   4. Shows the result and a PASS/FAIL check on the board.
//
// Board I/O:
//   CPU_RESET  : reset + reload + run
//   BTNC       : run again
//   SW0        : 7-seg shows result (0) or latency in cycles (1)
//   LD15..LD0  : result[15:0]
//   LED16 green: PASS (result == EXPECTED), LED16 red: FAIL
//   LED17 blue : run finished
//   7-seg      : 32-bit value in hex
// ============================================================

module fpga_top #(
    // Paste the number from expected_result.txt here (decimal).
    parameter signed [31:0] EXPECTED = 32'sd0
)(
    input  wire        clk100,      // 100 MHz oscillator
    input  wire        cpu_resetn,  // active-low reset button
    input  wire        btnc,        // run again
    input  wire        sw0,         // display select

    output wire [15:0] led,
    output wire        led_pass,
    output wire        led_fail,
    output wire        led_done,

    output wire [6:0]  seg,         // {CG,CF,CE,CD,CC,CB,CA}, active-low
    output wire        dp,
    output wire [7:0]  an           // active-low digit enables
);

    // ========================================================
    // 1. Clock: 100 MHz -> 76.923 MHz (13 ns period)
    //    VCO = 100 MHz x 10 = 1000 MHz, CLKOUT0 = 1000 / 13
    // ========================================================
    wire clkfb, clk_unbuf, locked, clk;

    MMCME2_BASE #(
        .CLKIN1_PERIOD    (10.0),
        .CLKFBOUT_MULT_F  (10.0),
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (13.0)
    ) u_mmcm (
        .CLKIN1   (clk100),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk_unbuf),
        .LOCKED   (locked),
        .RST      (1'b0),
        .PWRDWN   (1'b0)
    );

    BUFG u_bufg (.I(clk_unbuf), .O(clk));

    // ========================================================
    // 2. Reset: held until the button is released AND the MMCM
    //    is locked; released synchronously to clk.
    // ========================================================
    wire arst_n = cpu_resetn & locked;
    reg  [1:0] rst_sync;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    end

    wire rst_n = rst_sync[1];

    // ========================================================
    // 3. Python data as on-chip ROMs (same files as the TB)
    // ========================================================
    reg [7:0] vec_rom  [0:31];
    reg [7:0] csbw_rom [0:15];
    reg [7:0] csbi_rom [0:15];

    initial begin
        $readmemh("vector.mem",      vec_rom);
        $readmemh("csb_weights.mem", csbw_rom);
        $readmemh("csb_indices.mem", csbi_rom);
    end

    // ========================================================
    // 4. BTNC: synchronise and detect the rising edge
    // ========================================================
    reg [2:0] btn_s;
    always @(posedge clk) btn_s <= {btn_s[1:0], btnc};
    wire btn_rise = btn_s[1] & ~btn_s[2];

    // ========================================================
    // 5. Loader / run FSM (replaces the TB main initial block)
    // ========================================================
    localparam LOAD_VEC = 3'd0,
               LOAD_CSB = 3'd1,
               START    = 3'd2,
               RUN      = 3'd3,
               DONE     = 3'd4;

    reg [2:0]  st;
    reg [5:0]  idx;

    reg        vec_we;
    reg [4:0]  vec_waddr;
    reg [7:0]  vec_wdata;

    reg        csb_we;
    reg [3:0]  csb_waddr;
    reg [7:0]  csb_wdata;
    reg [2:0]  csb_idata;

    reg        start;

    reg [31:0] result_q;
    reg [15:0] cycles, cycles_q;
    reg        done_q;

    wire signed [31:0] pe_result;
    wire               pe_row_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            st       <= LOAD_VEC;
            idx      <= 6'd0;
            vec_we   <= 1'b0;  vec_waddr <= 5'd0;  vec_wdata <= 8'd0;
            csb_we   <= 1'b0;  csb_waddr <= 4'd0;  csb_wdata <= 8'd0;
            csb_idata<= 3'd0;
            start    <= 1'b0;
            result_q <= 32'd0;
            cycles   <= 16'd0;
            cycles_q <= 16'd0;
            done_q   <= 1'b0;
        end else begin
            // one-cycle defaults
            vec_we <= 1'b0;
            csb_we <= 1'b0;
            start  <= 1'b0;

            case (st)
                // Same as TB loop: for i = 0..31 write vector[i]
                LOAD_VEC: begin
                    vec_we    <= 1'b1;
                    vec_waddr <= idx[4:0];
                    vec_wdata <= vec_rom[idx[4:0]];
                    if (idx == 6'd31) begin idx <= 6'd0; st <= LOAD_CSB; end
                    else               idx <= idx + 6'd1;
                end

                // Same as TB loop: for i = 0..15 write CSB weight + index
                LOAD_CSB: begin
                    csb_we    <= 1'b1;
                    csb_waddr <= idx[3:0];
                    csb_wdata <= csbw_rom[idx[3:0]];
                    csb_idata <= csbi_rom[idx[3:0]][2:0];
                    if (idx == 6'd15) begin idx <= 6'd0; st <= START; end
                    else               idx <= idx + 6'd1;
                end

                // One-cycle start pulse
                START: begin
                    start  <= 1'b1;
                    cycles <= 16'd0;
                    st     <= RUN;
                end

                // Count cycles until row_done, then latch the result
                RUN: begin
                    cycles <= cycles + 16'd1;
                    if (pe_row_done) begin
                        result_q <= pe_result;
                        // measured like the TB: start edge -> row_done edge
                        cycles_q <= cycles - 16'd1;
                        done_q   <= 1'b1;
                        st       <= DONE;
                    end
                end

                // Hold the result; BTNC runs it again
                DONE: begin
                    if (btn_rise) begin
                        done_q <= 1'b0;
                        st     <= START;
                    end
                end

                default: st <= LOAD_VEC;
            endcase
        end
    end

    // ========================================================
    // 6. The design under test (unchanged)
    // ========================================================
    sparse_pe u_sparse_pe (
        .clk       (clk),
        .rst_n     (rst_n),

        .vec_we    (vec_we),
        .vec_waddr (vec_waddr),
        .vec_wdata (vec_wdata),

        .csb_we    (csb_we),
        .csb_waddr (csb_waddr),
        .csb_wdata (csb_wdata),
        .csb_idata (csb_idata),

        .start     (start),
        .busy      (),
        .done      (),

        .result    (pe_result),
        .row_done  (pe_row_done)
    );

    // ========================================================
    // 7. LEDs
    // ========================================================
    assign led      = result_q[15:0];
    assign led_done = done_q;
    assign led_pass = done_q & ($signed(result_q) == EXPECTED);
    assign led_fail = done_q & ($signed(result_q) != EXPECTED);

    // ========================================================
    // 8. 8-digit 7-segment display (hex), multiplexed
    //    digit switches every 2^14 cycles (~213 us)
    // ========================================================
    wire [31:0] disp = sw0 ? {16'd0, cycles_q} : result_q;

    reg [16:0] refresh;
    always @(posedge clk) refresh <= refresh + 17'd1;

    wire [2:0] dig = refresh[16:14];
    wire [3:0] nib = disp[dig*4 +: 4];

    reg [6:0] seg_r;
    always @* begin
        case (nib)           // gfedcba, active-low
            4'h0: seg_r = 7'b1000000;
            4'h1: seg_r = 7'b1111001;
            4'h2: seg_r = 7'b0100100;
            4'h3: seg_r = 7'b0110000;
            4'h4: seg_r = 7'b0011001;
            4'h5: seg_r = 7'b0010010;
            4'h6: seg_r = 7'b0000010;
            4'h7: seg_r = 7'b1111000;
            4'h8: seg_r = 7'b0000000;
            4'h9: seg_r = 7'b0010000;
            4'hA: seg_r = 7'b0001000;
            4'hB: seg_r = 7'b0000011;
            4'hC: seg_r = 7'b1000110;
            4'hD: seg_r = 7'b0100001;
            4'hE: seg_r = 7'b0000110;
            default: seg_r = 7'b0001110; // F
        endcase
    end

    assign seg = seg_r;
    assign dp  = 1'b1;               // off
    assign an  = ~(8'b1 << dig);

endmodule
