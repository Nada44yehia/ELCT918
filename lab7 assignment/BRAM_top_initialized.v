
`timescale 1ns / 1ps

module BRAM_top #(
    parameter DATA_W = 32,
    parameter DEPTH  = 4096,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  en,
    input  wire                  w_en,
    input  wire [ADDR_W-1:0]     addr,
    input  wire [DATA_W-1:0]     data_in,
    output reg  [DATA_W-1:0]     data_out
);

    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    initial $readmemh("init.mem", mem);

    always @(posedge clk) begin
        if (en) begin
            // Read-first behavior
            data_out <= mem[addr];

            if (w_en)
                mem[addr] <= data_in;
        end
    end

endmodule
