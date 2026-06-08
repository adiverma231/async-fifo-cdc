// Synchronizes write pointer into read clock domain

module sync_w2r #(
    parameter ADDR_WIDTH = 4
)(
    input  wire                  rd_clk,
    input  wire                  rst_n,
    input  wire [ADDR_WIDTH:0]   wptr_gray,
    output reg  [ADDR_WIDTH:0]   wptr_gray_sync
);

    reg [ADDR_WIDTH:0] wptr_gray_meta;

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr_gray_meta <= '0;
            wptr_gray_sync <= '0;
        end else begin
            wptr_gray_meta <= wptr_gray;
            wptr_gray_sync <= wptr_gray_meta;
        end
    end

endmodule
