module reset_sync (
    input  wire clk,
    input  wire arst_n,
    output reg  srst_n
);

    reg srst_n_meta;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            srst_n_meta <= 1'b0;
            srst_n      <= 1'b0;
        end else begin
            srst_n_meta <= 1'b1;
            srst_n      <= srst_n_meta;
        end
    end

endmodule
