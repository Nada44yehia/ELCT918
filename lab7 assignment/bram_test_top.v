`timescale 1ns / 1ps
module bram_test_top (
    input wire CLK100MHZ,
    input wire CPU_RESETN,
    output reg [15:0] LED
);
    localparam DEPTH = 4096;
    localparam [2:0] WRITE=0, READ_REQ=1, READ_CHECK=2, DONE=3;
    reg [2:0] state;
    reg [11:0] idx;
    reg [1:0] reset_sync = 2'b00;
    always @(posedge CLK100MHZ) reset_sync <= {reset_sync[0], CPU_RESETN};
    wire rst = !reset_sync[1];
    (* mark_debug = "true" *) reg [63:0] write_cycles, read_cycles;
    (* mark_debug = "true" *) reg [31:0] mismatch_count;
    (* mark_debug = "true" *) wire test_done = (state == DONE);
    (* mark_debug = "true" *) wire test_busy = !rst && !test_done;
    function [31:0] pattern(input [11:0] a);
        pattern = 32'hA5A55A3C ^ {a, a, a[7:0]};
    endfunction
    wire [31:0] data_out;
    wire en = !rst && (state == WRITE || state == READ_REQ);
    BRAM_top #(.DATA_W(32), .DEPTH(DEPTH)) u_bram (
        .clk(CLK100MHZ), .en(en), .w_en(state == WRITE),
        .addr(idx), .data_in(pattern(idx)), .data_out(data_out)
    );
    always @(posedge CLK100MHZ) begin
        if (rst) begin
            state <= WRITE; idx <= 0;
            write_cycles <= 0; read_cycles <= 0; mismatch_count <= 0;
        end else case (state)
            WRITE: begin
                write_cycles <= write_cycles + 1;
                if (idx == DEPTH-1) begin idx <= 0; state <= READ_REQ; end
                else idx <= idx + 1;
            end
            READ_REQ: begin
                read_cycles <= read_cycles + 1;
                state <= READ_CHECK;
            end
            READ_CHECK: begin
                read_cycles <= read_cycles + 1;
                if (data_out != pattern(idx)) mismatch_count <= mismatch_count + 1;
                if (idx == DEPTH-1) state <= DONE;
                else begin idx <= idx + 1; state <= READ_REQ; end
            end
            DONE: ;
            default: state <= WRITE;
        endcase
    end
    always @* begin
        if (rst) LED = 16'h0000;
        else case (state)
            WRITE: LED = 16'h0002;
            READ_REQ, READ_CHECK: LED = 16'h0004;
            DONE: LED = (mismatch_count == 0) ? 16'hFFFF : {2'b10, mismatch_count[13:0]};
            default: LED = 16'h0000;
        endcase
    end
endmodule
