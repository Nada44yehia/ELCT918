// ============================================================
// 1. VECTOR BUFFER
// Reference: Paper Fig. 7(c) and Fig. 8
// Four independent banks, each storing 8 signed INT8 elements.
// One element is read from each bank in parallel.
// ============================================================

module vector_buffer (
    input  wire              clk,
    input  wire            rst_n,

    // Vector loading interface
    input  wire              vec_we,
    input  wire [4:0]        vec_waddr,
    input  wire signed [7:0] vec_wdata,

    // One read address for each bank
    input  wire [2:0]        rd_addr0,
    input  wire [2:0]        rd_addr1,
    input  wire [2:0]        rd_addr2,
    input  wire [2:0]        rd_addr3,

    // Registered read data
    output reg signed [7:0]  rd_data0,
    output reg signed [7:0]  rd_data1,
    output reg signed [7:0]  rd_data2,
    output reg signed [7:0]  rd_data3
);

    // Four banks, eight signed INT8 elements per bank
    reg signed [7:0] bank0 [0:7];
    reg signed [7:0] bank1 [0:7];
    reg signed [7:0] bank2 [0:7];
    reg signed [7:0] bank3 [0:7];

    // Bank selection uses the two MSBs; local address uses three LSBs.
   always @(posedge clk) begin
    if (!rst_n) begin
        rd_data0 <= 8'sd0;
    end
    else begin
        if (vec_we && vec_waddr[4:3] == 2'd0)
            bank0[vec_waddr[2:0]] <= vec_wdata;

        rd_data0 <= bank0[rd_addr0];
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        rd_data1 <= 8'sd0;
    end
    else begin
        if (vec_we && vec_waddr[4:3] == 2'd1)
            bank1[vec_waddr[2:0]] <= vec_wdata;

        rd_data1 <= bank1[rd_addr1];
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        rd_data2 <= 8'sd0;
    end
    else begin
        if (vec_we && vec_waddr[4:3] == 2'd2)
            bank2[vec_waddr[2:0]] <= vec_wdata;

        rd_data2 <= bank2[rd_addr2];
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        rd_data3 <= 8'sd0;
    end
    else begin
        if (vec_we && vec_waddr[4:3] == 2'd3)
            bank3[vec_waddr[2:0]] <= vec_wdata;

        rd_data3 <= bank3[rd_addr3];
    end
end
endmodule


// ============================================================
// 2. WEIGHT REGISTERS
// Reference: Paper Fig. 8
// Register the four CSB weights to align them with the
// corresponding registered vector-buffer outputs.
// ============================================================

module weight_registers (
    input  wire clk,
    input  wire rst_n,

    input  wire signed [7:0] weight0,
    input  wire signed [7:0] weight1,
    input  wire signed [7:0] weight2,
    input  wire signed [7:0] weight3,

    output reg signed [7:0] weight_d0,
    output reg signed [7:0] weight_d1,
    output reg signed [7:0] weight_d2,
    output reg signed [7:0] weight_d3
);

    always @(posedge clk ) begin
        if (!rst_n) begin
            weight_d0 <= 8'sd0;
            weight_d1 <= 8'sd0;
            weight_d2 <= 8'sd0;
            weight_d3 <= 8'sd0;
        end
        else begin
            weight_d0 <= weight0;
            weight_d1 <= weight1;
            weight_d2 <= weight2;
            weight_d3 <= weight3;
        end
    end

endmodule


// ============================================================
// 3. MAC TREE
// Reference: Paper Fig. 8
// Four banks perform four pairwise multiplications in parallel.
// Their products are combined using a two-level adder tree.
// ============================================================

module mac_tree (
    input wire signed [7:0] weight0,
    input wire signed [7:0] weight1,
    input wire signed [7:0] weight2,
    input wire signed [7:0] weight3,

    input wire signed [7:0] vector0,
    input wire signed [7:0] vector1,
    input wire signed [7:0] vector2,
    input wire signed [7:0] vector3,

    output wire signed [17:0] partial_sum
);

    // Four signed INT8 x INT8 multipliers produce INT16 products.
    wire signed [15:0] product0;
    wire signed [15:0] product1;
    wire signed [15:0] product2;
    wire signed [15:0] product3;

    assign product0 = weight0 * vector0;
    assign product1 = weight1 * vector1;
    assign product2 = weight2 * vector2;
    assign product3 = weight3 * vector3;

    // Implementation choice: sign-extend products to 18 bits
    // to safely represent the sum of four signed INT16 products.
    wire signed [17:0] product0_ext;
    wire signed [17:0] product1_ext;
    wire signed [17:0] product2_ext;
    wire signed [17:0] product3_ext;

    assign product0_ext = {{2{product0[15]}}, product0};
    assign product1_ext = {{2{product1[15]}}, product1};
    assign product2_ext = {{2{product2[15]}}, product2};
    assign product3_ext = {{2{product3[15]}}, product3};

    // First adder-tree level: combine products in pairs.
    wire signed [17:0] sum01;
    wire signed [17:0] sum23;

    assign sum01 = product0_ext + product1_ext;
    assign sum23 = product2_ext + product3_ext;

    // Second adder-tree level: generate one partial sum.
    assign partial_sum = sum01 + sum23;

endmodule


// ============================================================
// 4. ACCUMULATOR
// Reference: Paper Fig. 8 (sequential accumulation of dot products)
// Implementation choice: 32-bit accumulator and sign extension.
// Accumulates the partial sums of one row.
// (Unchanged: it already accepts one partial sum per cycle.)
// ============================================================

module accumulator (
    input wire clk,
    input wire rst_n,

    input wire group_valid,
    input wire last_group,

    input wire signed [17:0] partial_sum,

    output reg signed [31:0] result,
    output reg row_done
);

    // Implementation choice: 32-bit register stores accumulated sums.
    reg signed [31:0] acc;

    // Delay control signals to align with the registered datapath.
    reg group_valid_d;
    reg last_group_d;

    // Sign-extend the 18-bit partial sum to 32 bits.
    wire signed [31:0] partial_sum_ext;

    assign partial_sum_ext =
        {{14{partial_sum[17]}}, partial_sum};

    // Add the current partial sum to the previous accumulated value.
    wire signed [31:0] acc_sum;

    assign acc_sum = acc + partial_sum_ext;

    always @(posedge clk) begin

        if (!rst_n) begin
            acc           <= 32'sd0;
            result        <= 32'sd0;
            row_done      <= 1'b0;

            group_valid_d <= 1'b0;
            last_group_d  <= 1'b0;
        end

        else begin

            // Pipeline the control signals by one clock cycle.
            group_valid_d <= group_valid;
            last_group_d  <= last_group;

            // Default: row_done is a one-cycle completion pulse.
            row_done <= 1'b0;

            if (group_valid_d) begin

                if (last_group_d) begin

                    // Final group: store the complete row result.
                    result <= acc_sum;

                    // Clear the accumulator for the next row.
                    acc <= 32'sd0;

                    row_done <= 1'b1;

                end

                else begin

                    // Non-final group: accumulate its partial sum.
                    acc <= acc_sum;

                    // Result is zero until the final group arrives.
                    result <= 32'sd0;

                end
            end
        end
    end

endmodule


// ============================================================
// CSB CONTROLLER  (PIPELINED VERSION)
//
// Change from the previous version:
//   The old FSM alternated SEND -> WAIT for every group, so each
//   group of 4 weights took 2 cycles (4 groups = 8 cycles), which
//   cancelled the benefit of skipping the zero weights.
//
//   The datapath is already pipelined (weight registers + registered
//   vector-buffer read -> MAC tree -> accumulator), so a new group
//   can be issued EVERY cycle while the previous one is accumulated.
//
// States:
// - IDLE : waits for start and allows the testbench to load CSB data.
// - RUN  : issues one group per cycle (groups 0,1,2,3 -> 4 cycles).
// - DRAIN: one cycle for the last group to leave the pipeline and
//          reach the accumulator; keeps busy high until the row
//          result is written.
//
// Latency (start edge -> row_done edge): 5 cycles  (was 8).
// ============================================================
module csb_controller (
    input  wire clk,
    input  wire rst_n,

    // CSB memory loading interface
    input  wire              csb_we,
    input  wire [3:0]        csb_waddr,
    input  wire signed [7:0] csb_wdata,
    input  wire [2:0]        csb_idata,

    // Start processing one row
    input  wire start,

    // Four CSB weights
    output wire signed [7:0] weight0,
    output wire signed [7:0] weight1,
    output wire signed [7:0] weight2,
    output wire signed [7:0] weight3,

    // Four bank-local indices
    output wire [2:0] index0,
    output wire [2:0] index1,
    output wire [2:0] index2,
    output wire [2:0] index3,

    // Control signals for sparse PE
    output wire group_valid,
    output wire last_group,

    // Controller status
    output reg busy,
    output reg done
);

    // ------------------------------------------------
    // 1. CSB memories
    // 16 weights and 16 corresponding local indices
    // ------------------------------------------------

    reg signed [7:0] csb_weights_mem [0:15];
    reg        [2:0] csb_indices_mem [0:15];

    // ------------------------------------------------
    // 2. Controller states
    // ------------------------------------------------
    localparam IDLE  = 2'b00;
    localparam RUN   = 2'b01;
    localparam DRAIN = 2'b10;

    reg [1:0] state;
    // Four groups: 0, 1, 2, 3
    reg [1:0] group_count;

    // ------------------------------------------------
    // 3. Load CSB memories
    // ------------------------------------------------

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                csb_weights_mem[i] <= 8'sd0;
                csb_indices_mem[i] <= 3'd0;
            end
        end
        else if (csb_we && !busy) begin
            csb_weights_mem[csb_waddr] <= csb_wdata;
            csb_indices_mem[csb_waddr] <= csb_idata;
        end
    end

    // ------------------------------------------------
    // 4. Select four entries from the current group
    // ------------------------------------------------

    assign weight0 = csb_weights_mem[{group_count, 2'b00}];
    assign weight1 = csb_weights_mem[{group_count, 2'b01}];
    assign weight2 = csb_weights_mem[{group_count, 2'b10}];
    assign weight3 = csb_weights_mem[{group_count, 2'b11}];

    assign index0 = csb_indices_mem[{group_count, 2'b00}];
    assign index1 = csb_indices_mem[{group_count, 2'b01}];
    assign index2 = csb_indices_mem[{group_count, 2'b10}];
    assign index3 = csb_indices_mem[{group_count, 2'b11}];

    // ------------------------------------------------
    // 5. Generate control signals
    // A group is valid in every RUN cycle (back-to-back).
    // ------------------------------------------------

    assign group_valid = (state == RUN);
    assign last_group  = (state == RUN) &&
                         (group_count == 2'd3);

    // ------------------------------------------------
    // 6. Controller FSM
    // ------------------------------------------------

    always @(posedge clk) begin
    if (!rst_n) begin
        state       <= IDLE;
        group_count <= 2'd0;
        busy        <= 1'b0;
        done        <= 1'b0;
    end
    else begin
        done <= 1'b0;

        case (state)

            IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    group_count <= 2'd0;
                    busy        <= 1'b1;
                    state       <= RUN;
                end
            end

            RUN: begin
                // Issue the current group and move to the next one
                // in the very next cycle (no WAIT state).
                if (group_count == 2'd3) begin
                    state <= DRAIN;
                end
                else begin
                    group_count <= group_count + 1'b1;
                end
            end

            DRAIN: begin
                // Last group is being accumulated this cycle;
                // row_done and done rise together at the next edge.
                state       <= IDLE;
                group_count <= 2'd0;
                busy        <= 1'b0;
                done        <= 1'b1;
            end

            default: begin
                state       <= IDLE;
                group_count <= 2'd0;
                busy        <= 1'b0;
                done        <= 1'b0;
            end

        endcase
    end
end
endmodule



// ============================================================
// 5. SPARSE PE TOP MODULE
// Reference: Paper Fig. 8
// Connects the vector buffer, weight registers, MAC tree,
// and accumulator to implement the sparse dot-product datapath.
// (Unchanged.)
// ============================================================


module sparse_pe (
    input wire clk,
    input wire rst_n,

    // --------------------------------
    // Vector loading interface
    // --------------------------------
    input wire vec_we,
    input wire [4:0] vec_waddr,
    input wire signed [7:0] vec_wdata,

    // --------------------------------
    // CSB loading interface
    // --------------------------------
    input wire csb_we,
    input wire [3:0] csb_waddr,
    input wire signed [7:0] csb_wdata,
    input wire [2:0] csb_idata,

    // --------------------------------
    // Processing control
    // --------------------------------
    input wire start,
    output wire busy,
    output wire done,

    // --------------------------------
    // Result
    // --------------------------------
    output wire signed [31:0] result,
    output wire row_done
);

    // ================================================
    // Internal connections: CSB controller -> PE
    // ================================================

    wire signed [7:0] weight0;
    wire signed [7:0] weight1;
    wire signed [7:0] weight2;
    wire signed [7:0] weight3;

    wire [2:0] index0;
    wire [2:0] index1;
    wire [2:0] index2;
    wire [2:0] index3;

    wire group_valid;
    wire last_group;

    // ================================================
    // Registered vector values
    // ================================================

    wire signed [7:0] vector0;
    wire signed [7:0] vector1;
    wire signed [7:0] vector2;
    wire signed [7:0] vector3;

    // Registered CSB weights
    wire signed [7:0] weight_d0;
    wire signed [7:0] weight_d1;
    wire signed [7:0] weight_d2;
    wire signed [7:0] weight_d3;

    // MAC tree output
    wire signed [17:0] partial_sum;


    // ================================================
    // 1. CSB CONTROLLER
    // ================================================

    csb_controller u_csb_controller (
        .clk(clk),
        .rst_n(rst_n),

        .csb_we(csb_we),
        .csb_waddr(csb_waddr),
        .csb_wdata(csb_wdata),
        .csb_idata(csb_idata),

        .start(start),

        .weight0(weight0),
        .weight1(weight1),
        .weight2(weight2),
        .weight3(weight3),

        .index0(index0),
        .index1(index1),
        .index2(index2),
        .index3(index3),

        .group_valid(group_valid),
        .last_group(last_group),

        .busy(busy),
        .done(done)
    );


    // ================================================
    // 2. VECTOR BUFFER
    // ================================================

    vector_buffer u_vector_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .vec_we(vec_we),
        .vec_waddr(vec_waddr),
        .vec_wdata(vec_wdata),

        .rd_addr0(index0),
        .rd_addr1(index1),
        .rd_addr2(index2),
        .rd_addr3(index3),

        .rd_data0(vector0),
        .rd_data1(vector1),
        .rd_data2(vector2),
        .rd_data3(vector3)
    );


    // ================================================
    // 3. WEIGHT REGISTERS
    // ================================================

    weight_registers u_weight_registers (
        .clk(clk),
        .rst_n(rst_n),

        .weight0(weight0),
        .weight1(weight1),
        .weight2(weight2),
        .weight3(weight3),

        .weight_d0(weight_d0),
        .weight_d1(weight_d1),
        .weight_d2(weight_d2),
        .weight_d3(weight_d3)
    );


    // ================================================
    // 4. MAC TREE
    // ================================================

    mac_tree u_mac_tree (
        .weight0(weight_d0),
        .weight1(weight_d1),
        .weight2(weight_d2),
        .weight3(weight_d3),

        .vector0(vector0),
        .vector1(vector1),
        .vector2(vector2),
        .vector3(vector3),

        .partial_sum(partial_sum)
    );


    // ================================================
    // 5. ACCUMULATOR
    // ================================================

    accumulator u_accumulator (
        .clk(clk),
        .rst_n(rst_n),

        .group_valid(group_valid),
        .last_group(last_group),

        .partial_sum(partial_sum),

        .result(result),
        .row_done(row_done)
    );

endmodule


// Dense 4-lane baseline PE for one 32-element row.
// Loads the same PRUNED dense row used by the sparse PE.
// Processes 4 consecutive positions per cycle: 32 / 4 = 8 cycles.
// (Unchanged.)
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
