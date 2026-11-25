module pe_array #(
    parameter integer N_PE = 1,
    parameter integer SCRATCH = 0
)(
    input wire clk100,
    input wire cpu_resetn,
    output reg [15:0] led
);
    reg [1:0] reset_sync = 0;
    always @(posedge clk100) reset_sync <= {reset_sync[0], cpu_resetn};
    wire rst_n = reset_sync[1];

    // 32 vector loads, 16 CSB loads, start, then time for the PE to finish.
    reg [5:0] phase;
    always @(posedge clk100)
        if (!rst_n) phase <= 0;
        else phase <= phase + 1'b1;

    wire [31:0] results [0:N_PE-1];
    wire [N_PE-1:0] row_done;
    genvar g;
    generate for (g=0; g<N_PE; g=g+1) begin : gen_pe
        // Different nonzero seeds give independent, changing data streams.
        localparam [31:0] SEED = 32'h1 + g;
        (* keep = "true" *) reg [31:0] lfsr;
        always @(posedge clk100)
            if (!rst_n) lfsr <= SEED;
            else lfsr <= {lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

        wire [15:0] feed;
        if (SCRATCH != 0) begin : gen_scratch
            // Private 1024 x 16 memory; all addresses written/read in turn.
            (* ram_style = "block" *) reg [15:0] mem [0:1023];
            reg [10:0] ptr;
            reg [15:0] q;
            always @(posedge clk100) begin
                if (!rst_n) ptr <= 0;
                else ptr <= ptr + 1'b1;
                if (rst_n && !ptr[10])
                    mem[ptr[9:0]] <= lfsr[15:0];
                q <= mem[ptr[9:0]];
            end
            // Read data actually feeds the PE; not an unused dummy RAM.
            assign feed = ptr[10] ? q : lfsr[15:0];
        end else begin : gen_no_scratch
            assign feed = lfsr[15:0];
        end

        (* keep_hierarchy = "yes", dont_touch = "yes" *)
        sparse_pe u_pe (
            .clk(clk100), .rst_n(rst_n),
            .vec_we(rst_n && phase < 32),
            .vec_waddr(phase[4:0]), .vec_wdata(feed[7:0]),
            .csb_we(rst_n && phase >= 32 && phase < 48),
            .csb_waddr(phase[3:0]), .csb_wdata(feed[15:8]),
            .csb_idata(lfsr[23:21]), .start(rst_n && phase == 48),
            .busy(), .done(), .result(results[g]), .row_done(row_done[g])
        );
    end endgenerate

    // Balanced reduction inferred from a vector XOR for each LED.
    wire [15:0] folded;
    genvar b, j;
    generate for (b=0; b<16; b=b+1) begin : gen_led
        wire [2*N_PE-1:0] bits_to_reduce;
        for (j=0; j<N_PE; j=j+1) begin : gen_bit
            assign bits_to_reduce[2*j] = results[j][b];
            assign bits_to_reduce[2*j+1] = results[j][b+16];
        end
        assign folded[b] = ^bits_to_reduce;
    end endgenerate
    always @(posedge clk100)
        if (!rst_n) led <= 0;
        else led <= folded ^ {15'b0, ^row_done};
endmodule
