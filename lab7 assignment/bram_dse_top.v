
module bram_dse_top #(
    parameter DATA_W = 32,
    parameter DEPTH = 4096,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input wire CLK100MHZ,
    input wire en,
    input wire w_en,
    input wire [ADDR_W-1:0] addr,
    input wire [DATA_W-1:0] data_in,
    output reg [DATA_W-1:0] data_out
);

    // Input registers
    reg en_reg;
    reg w_en_reg;
    reg [ADDR_W-1:0] addr_reg;
    reg [DATA_W-1:0] data_in_reg;

    wire [DATA_W-1:0] bram_out;

    always @(posedge CLK100MHZ) begin
        en_reg      <= en;
        w_en_reg    <= w_en;
        addr_reg    <= addr;
        data_in_reg <= data_in;
        data_out    <= bram_out;
    end

    BRAM_top #(
        .DATA_W(DATA_W),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W)
    ) u_bram (
        .clk(CLK100MHZ),
        .en(en_reg),
        .w_en(w_en_reg),
        .addr(addr_reg),
        .data_in(data_in_reg),
        .data_out(bram_out)
    );

endmodule
