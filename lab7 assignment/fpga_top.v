// ============================================================
// fpga_top.v  --  Nexys4 DDR wrapper for sparse_pe, UART version
//
// Data now comes LIVE from Python over the USB-UART (115200 8N1)
// instead of .mem files baked into the bitstream.
//
// Python -> FPGA packet (69 bytes):
//   byte 0        : 0xA5                 (header)
//   bytes 1..32   : vector[0..31]        (signed INT8)
//   bytes 33..48  : CSB weights[0..15]   (signed INT8, [group][bank] order)
//   bytes 49..64  : CSB indices[0..15]   (3-bit local index in each byte)
//   bytes 65..68  : expected result      (signed 32-bit, little-endian)
//
// FPGA -> Python reply (6 bytes):
//   byte 0        : 0x5A                 (header)
//   bytes 1..4    : result               (signed 32-bit, little-endian)
//   byte 5        : latency in cycles    (start edge -> row_done edge)
//
// Board I/O:
//   7-seg      : result in DECIMAL (e.g. "271"), "--------" = waiting
//   SW0 up     : 7-seg shows latency in cycles instead
//   LD15..LD0  : result[15:0]
//   LED16      : green = PASS (result == expected sent by Python), red = FAIL
//   LED17 blue : a result is available
//   BTNC       : run the last received data again
//   CPU_RESET  : reset everything
// ============================================================

`timescale 1ns/1ps

module fpga_top #(
    // 76.923 MHz / 115200 baud = 667.7 -> 668 (0.04 % error)
    parameter integer CLKS_PER_BIT = 668
)(
    input  wire        clk100,      // 100 MHz oscillator
    input  wire        cpu_resetn,  // active-low reset button
    input  wire        btnc,        // run again
    input  wire        sw0,         // display select

    input  wire        uart_rx,     // PC -> FPGA
    output wire        uart_tx,     // FPGA -> PC

    output wire [15:0] led,
    output wire        led_pass,
    output wire        led_fail,
    output wire        led_done,

    output reg  [6:0]  seg,         // {CG,CF,CE,CD,CC,CB,CA}, active-low
    output wire        dp,
    output wire [7:0]  an           // active-low digit enables
);

    // ========================================================
    // 1. Clock: 100 MHz -> 76.923 MHz (13 ns period)
    // ========================================================
    wire clkfb, clk_unbuf, locked, clk;

    MMCME2_BASE #(
        .CLKIN1_PERIOD    (10.0),
        .CLKFBOUT_MULT_F  (10.0),   // VCO = 1000 MHz
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (13.0)    // 1000 / 13 = 76.923 MHz
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
    // 2. Reset: held until button released AND MMCM locked
    // ========================================================
    wire arst_n = cpu_resetn & locked;
    reg  [1:0] rst_sync;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    end

    wire rst_n = rst_sync[1];

    // ========================================================
    // 3. UART receiver and transmitter
    // ========================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_receiver #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (rx_data),
        .valid (rx_valid)
    );

    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    uart_transmitter #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (tx_data),
        .start (tx_start),
        .tx    (uart_tx),
        .busy  (tx_busy)
    );

    // ========================================================
    // 4. BTNC: synchronise and detect the rising edge
    // ========================================================
    reg [2:0] btn_s;
    always @(posedge clk) btn_s <= {btn_s[1:0], btnc};
    wire btn_rise = btn_s[1] & ~btn_s[2];

    // ========================================================
    // 5. Receive buffer (68 payload bytes)
    //    0..31 vector, 32..47 CSB weights, 48..63 CSB indices,
    //    64..67 expected result (little-endian)
    // ========================================================
    reg [7:0] rxbuf [0:67];

    // ========================================================
    // 6. Main FSM: receive -> load -> run -> reply
    // ========================================================
    localparam WAIT_HDR = 4'd0,
               RX_BYTES = 4'd1,
               LOAD_VEC = 4'd2,
               LOAD_CSB = 4'd3,
               START    = 4'd4,
               RUN      = 4'd5,
               TX_SEND  = 4'd6,
               TX_WAIT1 = 4'd7,
               TX_WAIT2 = 4'd8;

    // ~13.6 ms without a byte while receiving -> give up and resync
    localparam [19:0] TIMEOUT_MAX = 20'hFFFFF;

    reg [3:0]  st;
    reg [6:0]  idx;
    reg [19:0] timeout;
    reg [2:0]  tx_idx;

    reg        vec_we;
    reg [4:0]  vec_waddr;
    reg [7:0]  vec_wdata;

    reg        csb_we;
    reg [3:0]  csb_waddr;
    reg [7:0]  csb_wdata;
    reg [2:0]  csb_idata;

    reg        start;

    reg [31:0] result_q;
    reg [31:0] expected_q;
    reg [15:0] cycles, cycles_q;
    reg        have_data;
    reg        have_result;
    reg        bcd_start;

    wire signed [31:0] pe_result;
    wire               pe_row_done;

    // Buffer write (no reset, so it can map to LUTRAM)
    always @(posedge clk) begin
        if (st == RX_BYTES && rx_valid)
            rxbuf[idx] <= rx_data;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            st          <= WAIT_HDR;
            idx         <= 7'd0;
            timeout     <= 20'd0;
            tx_idx      <= 3'd0;
            vec_we      <= 1'b0;  vec_waddr <= 5'd0;  vec_wdata <= 8'd0;
            csb_we      <= 1'b0;  csb_waddr <= 4'd0;  csb_wdata <= 8'd0;
            csb_idata   <= 3'd0;
            start       <= 1'b0;
            tx_start    <= 1'b0;
            tx_data     <= 8'd0;
            result_q    <= 32'd0;
            expected_q  <= 32'd0;
            cycles      <= 16'd0;
            cycles_q    <= 16'd0;
            have_data   <= 1'b0;
            have_result <= 1'b0;
            bcd_start   <= 1'b0;
        end else begin
            // one-cycle defaults
            vec_we    <= 1'b0;
            csb_we    <= 1'b0;
            start     <= 1'b0;
            tx_start  <= 1'b0;
            bcd_start <= 1'b0;

            case (st)
                // Wait for 0xA5 from Python (or BTNC to re-run)
                WAIT_HDR: begin
                    idx     <= 7'd0;
                    timeout <= 20'd0;
                    if (rx_valid && rx_data == 8'hA5)
                        st <= RX_BYTES;
                    else if (btn_rise && have_data)
                        st <= START;
                end

                // Collect the 68 payload bytes
                RX_BYTES: begin
                    if (rx_valid) begin
                        timeout <= 20'd0;
                        if (idx == 7'd67) begin
                            idx <= 7'd0;
                            st  <= LOAD_VEC;
                        end else begin
                            idx <= idx + 7'd1;
                        end
                    end else if (timeout == TIMEOUT_MAX) begin
                        st <= WAIT_HDR;          // packet broken: resync
                    end else begin
                        timeout <= timeout + 20'd1;
                    end
                end

                // Same as TB loop: write vector[0..31]
                LOAD_VEC: begin
                    vec_we    <= 1'b1;
                    vec_waddr <= idx[4:0];
                    vec_wdata <= rxbuf[idx[4:0]];
                    if (idx == 7'd31) begin idx <= 7'd0; st <= LOAD_CSB; end
                    else               idx <= idx + 7'd1;
                end

                // Same as TB loop: write CSB weight[i] + index[i]
                LOAD_CSB: begin
                    csb_we    <= 1'b1;
                    csb_waddr <= idx[3:0];
                    csb_wdata <= rxbuf[{3'b010, idx[3:0]}];       // 32 + i
                    csb_idata <= rxbuf[{3'b011, idx[3:0]}][2:0];  // 48 + i
                    if (idx == 7'd15) begin
                        idx       <= 7'd0;
                        have_data <= 1'b1;
                        st        <= START;
                    end else begin
                        idx <= idx + 7'd1;
                    end
                end

                // One-cycle start pulse
                START: begin
                    start      <= 1'b1;
                    cycles     <= 16'd0;
                    expected_q <= {rxbuf[67], rxbuf[66], rxbuf[65], rxbuf[64]};
                    st         <= RUN;
                end

                // Count cycles until row_done, latch the result
                RUN: begin
                    cycles <= cycles + 16'd1;
                    if (pe_row_done) begin
                        result_q    <= pe_result;
                        cycles_q    <= cycles - 16'd1;   // same as TB measurement
                        have_result <= 1'b1;
                        bcd_start   <= 1'b1;             // update decimal display
                        tx_idx      <= 3'd0;
                        st          <= TX_SEND;
                    end
                end

                // Send 6-byte reply: 5A, result (LE), latency
                TX_SEND: begin
                    case (tx_idx)
                        3'd0:    tx_data <= 8'h5A;
                        3'd1:    tx_data <= result_q[7:0];
                        3'd2:    tx_data <= result_q[15:8];
                        3'd3:    tx_data <= result_q[23:16];
                        3'd4:    tx_data <= result_q[31:24];
                        default: tx_data <= cycles_q[7:0];
                    endcase
                    tx_start <= 1'b1;
                    st       <= TX_WAIT1;
                end

                TX_WAIT1: st <= TX_WAIT2;   // transmitter becomes busy

                TX_WAIT2: begin
                    if (!tx_busy) begin
                        if (tx_idx == 3'd5) begin
                            st <= WAIT_HDR;
                        end else begin
                            tx_idx <= tx_idx + 3'd1;
                            st     <= TX_SEND;
                        end
                    end
                end

                default: st <= WAIT_HDR;
            endcase
        end
    end

    // ========================================================
    // 7. The design under test (unchanged)
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
    // 8. LEDs
    // ========================================================
    assign led      = result_q[15:0];
    assign led_done = have_result;
    assign led_pass = have_result & (result_q == expected_q);
    assign led_fail = have_result & (result_q != expected_q);

    // ========================================================
    // 9. Binary -> decimal (BCD) for the 7-segment display
    // ========================================================
    wire [31:0] res_mag = result_q[31] ? (~result_q + 32'd1) : result_q;
    wire [39:0] res_bcd, lat_bcd;

    bin2bcd u_bcd_res (.clk(clk), .start(bcd_start), .bin(res_mag),            .bcd(res_bcd));
    bin2bcd u_bcd_lat (.clk(clk), .start(bcd_start), .bin({16'd0, cycles_q}), .bcd(lat_bcd));

    // ========================================================
    // 10. 8-digit 7-segment display (decimal), multiplexed
    //     digit switches every 2^14 cycles (~213 us)
    // ========================================================
    reg [16:0] refresh;
    always @(posedge clk) refresh <= refresh + 17'd1;

    wire [2:0]  dig  = refresh[16:14];
    wire [39:0] dbcd = sw0 ? lat_bcd : res_bcd;
    wire        dneg = ~sw0 & result_q[31];

    wire [3:0]  nib       = dbcd[dig*4 +: 4];
    // digit is part of the number (not a leading zero)
    wire        dig_used  = (dig == 3'd0) || ((dbcd >> (4*dig)) != 40'd0);
    // minus sign goes just left of the most significant digit
    wire        minus_here = dneg && !dig_used &&
                             ((dbcd >> (4*(dig-1))) != 40'd0);

    always @* begin
        if (!have_result)     seg = 7'b0111111;   // '-' : waiting for data
        else if (minus_here)  seg = 7'b0111111;   // '-'
        else if (!dig_used)   seg = 7'b1111111;   // blank leading zero
        else begin
            case (nib)          // gfedcba, active-low
                4'd0:    seg = 7'b1000000;
                4'd1:    seg = 7'b1111001;
                4'd2:    seg = 7'b0100100;
                4'd3:    seg = 7'b0110000;
                4'd4:    seg = 7'b0011001;
                4'd5:    seg = 7'b0010010;
                4'd6:    seg = 7'b0000010;
                4'd7:    seg = 7'b1111000;
                4'd8:    seg = 7'b0000000;
                4'd9:    seg = 7'b0010000;
                default: seg = 7'b1111111;
            endcase
        end
    end

    assign dp = 1'b1;               // off
    assign an = ~(8'b1 << dig);

endmodule


// ============================================================
// UART receiver, 8N1, samples each bit in its middle
// ============================================================
module uart_receiver #(
    parameter integer CLKS_PER_BIT = 668
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    // Synchronise the asynchronous RX line (idle = 1)
    reg [1:0] sync = 2'b11;
    always @(posedge clk) sync <= {sync[0], rx};
    wire rxs = sync[1];

    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  st;
    reg [15:0] cnt;
    reg [2:0]  bitn;
    reg [7:0]  sh;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= IDLE; cnt <= 16'd0; bitn <= 3'd0;
            sh <= 8'd0; data <= 8'd0; valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (st)
                IDLE: begin
                    cnt  <= 16'd0;
                    bitn <= 3'd0;
                    if (!rxs) st <= START;              // falling edge = start bit
                end
                START: begin                             // go to middle of start bit
                    if (cnt == CLKS_PER_BIT/2 - 1) begin
                        cnt <= 16'd0;
                        st  <= rxs ? IDLE : DATA;        // glitch -> back to idle
                    end else cnt <= cnt + 16'd1;
                end
                DATA: begin                              // sample 8 bits, LSB first
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 16'd0;
                        sh  <= {rxs, sh[7:1]};
                        if (bitn == 3'd7) st <= STOP;
                        else              bitn <= bitn + 3'd1;
                    end else cnt <= cnt + 16'd1;
                end
                STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 16'd0;
                        st  <= IDLE;
                        if (rxs) begin                   // valid stop bit
                            data  <= sh;
                            valid <= 1'b1;
                        end
                    end else cnt <= cnt + 16'd1;
                end
            endcase
        end
    end
endmodule


// ============================================================
// UART transmitter, 8N1
// ============================================================
module uart_transmitter #(
    parameter integer CLKS_PER_BIT = 668
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output wire       busy
);
    reg [9:0]  frame;     // {stop, data[7:0], start}
    reg [3:0]  bitn;
    reg [15:0] cnt;
    reg        active;

    assign busy = active;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx <= 1'b1; active <= 1'b0; cnt <= 16'd0;
            bitn <= 4'd0; frame <= 10'h3FF;
        end else if (!active) begin
            tx <= 1'b1;
            if (start) begin
                frame  <= {1'b1, data, 1'b0};
                active <= 1'b1;
                cnt    <= 16'd0;
                bitn   <= 4'd0;
                tx     <= 1'b0;                  // start bit
            end
        end else begin
            if (cnt == CLKS_PER_BIT - 1) begin
                cnt <= 16'd0;
                if (bitn == 4'd9) begin          // stop bit finished
                    active <= 1'b0;
                    tx     <= 1'b1;
                end else begin
                    bitn <= bitn + 4'd1;
                    tx   <= frame[bitn + 4'd1];
                end
            end else cnt <= cnt + 16'd1;
        end
    end
endmodule


// ============================================================
// Sequential binary -> BCD (double dabble), 32 cycles
// 32-bit input -> 10 decimal digits
// ============================================================
module bin2bcd (
    input  wire        clk,
    input  wire        start,
    input  wire [31:0] bin,
    output reg  [39:0] bcd
);
    reg [31:0] sh;
    reg [39:0] acc;
    reg [5:0]  n;
    reg        busy;
    reg [39:0] adj;
    integer    k;

    initial begin
        bcd = 40'd0; sh = 32'd0; acc = 40'd0; n = 6'd0; busy = 1'b0;
    end

    // add 3 to every digit >= 5 before shifting
    always @* begin
        adj = acc;
        for (k = 0; k < 10; k = k + 1)
            if (adj[4*k +: 4] >= 4'd5)
                adj[4*k +: 4] = adj[4*k +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (start) begin
            sh   <= bin;
            acc  <= 40'd0;
            n    <= 6'd0;
            busy <= 1'b1;
        end else if (busy) begin
            acc <= {adj[38:0], sh[31]};
            sh  <= {sh[30:0], 1'b0};
            n   <= n + 6'd1;
            if (n == 6'd31) begin
                busy <= 1'b0;
                bcd  <= {adj[38:0], sh[31]};
            end
        end
    end
endmodule