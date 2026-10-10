
module solution (
    input        clk,
    input        rst_n,
    input        en,
    input  [3:0] din,
    output reg [7:0] dout,
    output reg       flag
);

    // Four-phase output pattern
    reg [1:0] phase;

    // Store the previous three lower output nibbles
    reg [11:0] previous_nibbles;

    // Current lower-nibble value that will be produced
    reg [3:0] next_lower;

    // Calculate the lower nibble according to the current phase
    always @(*) begin
        case (phase)
            2'b00: next_lower = din + 4'd6;
            2'b01: next_lower = din + 4'd7;
            2'b10: next_lower = din + 4'd4;
            2'b11: next_lower = din + 4'd5;
        endcase
    end

    // Sequential logic
    always @(posedge clk) begin

        if (!rst_n) begin
            dout            <= 8'h00;
            phase           <= 2'b00;
            previous_nibbles <= 12'h000;
            flag            <= 1'b0;
        end

        else if (en) begin

            // Generate output
            dout[7:4] <= dout[7:4] + 4'd1;
            dout[3:0] <= next_lower;

            // Detect CAFE
            // previous_nibbles contains the previous
            // three lower-nibble outputs.
            if ((previous_nibbles == 12'h0CAF) &&
                (next_lower == 4'hE))
                flag <= 1'b1;
            else
                flag <= 1'b0;

            // Shift in the new lower nibble
            previous_nibbles <= {
                previous_nibbles[7:0],
                next_lower
            };

            // Advance phase
            phase <= phase + 2'd1;
        end

        else begin
            // When disabled, hold the output and state.
            dout <= dout;
            phase <= phase;
            previous_nibbles <= previous_nibbles;
            flag <= flag;
        end

    end

endmodule