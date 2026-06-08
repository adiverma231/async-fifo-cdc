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

