// Synchronizes read pointer into write clock domain

module sync_r2w #(
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wr_clk,
    input  wire                  rst_n,
    input  wire [ADDR_WIDTH:0]   rptr_gray,
    output reg  [ADDR_WIDTH:0]   rptr_gray_sync
);

    reg [ADDR_WIDTH:0] rptr_gray_meta;

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr_gray_meta <= '0;
            rptr_gray_sync <= '0;
        end else begin
            rptr_gray_meta <= rptr_gray;
            rptr_gray_sync <= rptr_gray_meta;
        end
    end

endmodule
