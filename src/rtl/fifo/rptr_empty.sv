module rptr_empty #(
    parameter ADDR_WIDTH   = 4,
    parameter AEMPTY_THRES = 4
)(
    input  wire                  rd_clk,
    input  wire                  rst_n,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH:0]   wptr_gray_sync,
    output wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [ADDR_WIDTH:0]   rptr_gray,
    output reg                   empty,
    output reg                   almost_empty
);

    reg  [ADDR_WIDTH:0] rbin;
    wire [ADDR_WIDTH:0] rbin_next;
    wire [ADDR_WIDTH:0] rptr_gray_next;
    wire [ADDR_WIDTH:0] wbin_sync;
    wire [ADDR_WIDTH:0] used_next;

    assign rd_addr = rbin[ADDR_WIDTH-1:0];
    assign rbin_next = rbin + (rd_en && !empty);
    assign rptr_gray_next = (rbin_next >> 1) ^ rbin_next;
    assign wbin_sync = gray_to_bin(wptr_gray_sync);
    assign used_next = wbin_sync - rbin_next;

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rbin         <= '0;
            rptr_gray    <= '0;
            empty        <= 1'b1;
            almost_empty <= 1'b1;
        end else begin
            rbin         <= rbin_next;
            rptr_gray    <= rptr_gray_next;
            empty        <= (rptr_gray_next == wptr_gray_sync);
            almost_empty <= (used_next <= AEMPTY_THRES);
        end
    end

    function automatic [ADDR_WIDTH:0] gray_to_bin;
        input [ADDR_WIDTH:0] gray;
        integer i;
        begin
            gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i = ADDR_WIDTH - 1; i >= 0; i = i - 1) begin
                gray_to_bin[i] = gray_to_bin[i + 1] ^ gray[i];
            end
        end
    endfunction

endmodule
