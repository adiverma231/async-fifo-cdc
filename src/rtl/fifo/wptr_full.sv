module wptr_full #(
    parameter ADDR_WIDTH  = 4,
    parameter AFULL_THRES = 12
)(
    input  wire                  wr_clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH:0]   rptr_gray_sync,
    output wire [ADDR_WIDTH-1:0] wr_addr,
    output reg  [ADDR_WIDTH:0]   wptr_gray,
    output reg                   full,
    output reg                   almost_full
);

    reg  [ADDR_WIDTH:0] wbin;
    wire [ADDR_WIDTH:0] wbin_next;
    wire [ADDR_WIDTH:0] wptr_gray_next;
    wire [ADDR_WIDTH:0] rbin_sync;
    wire [ADDR_WIDTH:0] used_next;
    wire                full_next;

    assign wr_addr = wbin[ADDR_WIDTH-1:0];
    assign wbin_next = wbin + (wr_en && !full);
    assign wptr_gray_next = (wbin_next >> 1) ^ wbin_next;
    assign rbin_sync = gray_to_bin(rptr_gray_sync);
    assign used_next = wbin_next - rbin_sync;
    assign full_next = (wptr_gray_next == {
        ~rptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1],
         rptr_gray_sync[ADDR_WIDTH-2:0]
    });

    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wbin        <= '0;
            wptr_gray   <= '0;
            full        <= 1'b0;
            almost_full <= 1'b0;
        end else begin
            wbin        <= wbin_next;
            wptr_gray   <= wptr_gray_next;
            full        <= full_next;
            almost_full <= (used_next >= AFULL_THRES);
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