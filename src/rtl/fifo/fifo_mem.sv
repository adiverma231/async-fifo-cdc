module fifo_mem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,

    input  wire                  rd_clk,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule