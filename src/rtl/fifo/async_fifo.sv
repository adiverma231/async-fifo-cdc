module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4,  // depth = 2^ADDR_WIDTH = 16
    parameter AFULL_THRES  = 12,
    parameter AEMPTY_THRES = 4
)(
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  rst_n,       // async assert, sync deassert

    // Write interface
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  wr_en,
    output wire                  full,
    output wire                  almost_full,

    // Read interface
    output wire [DATA_WIDTH-1:0] rd_data,
    input  wire                  rd_en,
    output wire                  empty,
    output wire                  almost_empty
);

    wire [ADDR_WIDTH-1:0] wr_addr;
    wire [ADDR_WIDTH-1:0] rd_addr;
    wire [ADDR_WIDTH:0]   wptr_gray;
    wire [ADDR_WIDTH:0]   rptr_gray;
    wire [ADDR_WIDTH:0]   wptr_gray_sync;
    wire [ADDR_WIDTH:0]   rptr_gray_sync;
    wire                  wr_mem_en;

    assign wr_mem_en = wr_en && !full;

    fifo_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) fifo_mem_inst (
        .wr_clk (wr_clk),
        .wr_en  (wr_mem_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk (rd_clk),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    sync_r2w #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) sync_r2w_inst (
        .wr_clk         (wr_clk),
        .rst_n          (rst_n),
        .rptr_gray      (rptr_gray),
        .rptr_gray_sync (rptr_gray_sync)
    );

    sync_w2r #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) sync_w2r_inst (
        .rd_clk         (rd_clk),
        .rst_n          (rst_n),
        .wptr_gray      (wptr_gray),
        .wptr_gray_sync (wptr_gray_sync)
    );

    wptr_full #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AFULL_THRES(AFULL_THRES)
    ) wptr_full_inst (
        .wr_clk        (wr_clk),
        .rst_n         (rst_n),
        .wr_en         (wr_en),
        .rptr_gray_sync(rptr_gray_sync),
        .wr_addr       (wr_addr),
        .wptr_gray     (wptr_gray),
        .full          (full),
        .almost_full   (almost_full)
    );

    rptr_empty #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .AEMPTY_THRES(AEMPTY_THRES)
    ) rptr_empty_inst (
        .rd_clk        (rd_clk),
        .rst_n         (rst_n),
        .rd_en         (rd_en),
        .wptr_gray_sync(wptr_gray_sync),
        .rd_addr       (rd_addr),
        .rptr_gray     (rptr_gray),
        .empty         (empty),
        .almost_empty  (almost_empty)
    );

endmodule
