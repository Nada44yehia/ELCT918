// Dense 4-lane baseline PE for one 32-element row.
// Loads the same PRUNED dense row used by the sparse PE.
// Processes 4 consecutive positions per cycle: 32 / 4 = 8 cycles.
module baseline_pe (
    input  wire clk,
    input  wire rst_n,

    input  wire vec_we,
    input  wire [4:0] vec_waddr,
    input  wire signed [7:0] vec_wdata,

    input  wire weight_we,
    input  wire [4:0] weight_waddr,
    input  wire signed [7:0] weight_wdata,

    input  wire start,
    output reg  busy,
    output reg  done,
    output reg signed [31:0] result
);

    reg signed [7:0] vector_mem [0:31];
    reg signed [7:0] weight_mem [0:31];

    reg [2:0] group_count; // 0..7, four elements per group
    reg signed [31:0] accumulator;

    wire signed [15:0] product0 =
        weight_mem[{group_count, 2'b00}] *
        vector_mem[{group_count, 2'b00}];
    wire signed [15:0] product1 =
        weight_mem[{group_count, 2'b01}] *
        vector_mem[{group_count, 2'b01}];
    wire signed [15:0] product2 =
        weight_mem[{group_count, 2'b10}] *
        vector_mem[{group_count, 2'b10}];
    wire signed [15:0] product3 =
        weight_mem[{group_count, 2'b11}] *
        vector_mem[{group_count, 2'b11}];

    wire signed [17:0] sum01 =
        {{2{product0[15]}}, product0} +
        {{2{product1[15]}}, product1};
    wire signed [17:0] sum23 =
        {{2{product2[15]}}, product2} +
        {{2{product3[15]}}, product3};
    wire signed [17:0] group_sum = sum01 + sum23;

    wire signed [31:0] group_sum_ext =
        {{14{group_sum[17]}}, group_sum};

    always @(posedge clk ) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            result       <= 32'sd0;
            accumulator  <= 32'sd0;
            group_count  <= 3'd0;
        end else begin
            done <= 1'b0;

            // Memory loading can happen while the PE is idle.
            if (vec_we)
                vector_mem[vec_waddr] <= vec_wdata;

            if (weight_we)
                weight_mem[weight_waddr] <= weight_wdata;

            if (start && !busy) begin
                busy        <= 1'b1;
                group_count <= 3'd0;
                accumulator <= 32'sd0;
            end else if (busy) begin
                if (group_count == 3'd7) begin
                    result      <= accumulator + group_sum_ext;
                    accumulator <= 32'sd0;
                    busy        <= 1'b0;
                    done        <= 1'b1;
                end else begin
                    accumulator <= accumulator + group_sum_ext;
                    group_count <= group_count + 1'b1;
                end
            end
        end
    end

endmodule
