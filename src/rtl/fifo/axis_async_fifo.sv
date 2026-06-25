// =============================================================================
// axis_async_fifo.sv
// -----------------------------------------------------------------------------
// AXI-Stream wrapper around the gray-code async_fifo CDC core.
//
// Realizes the framing decision recorded in pkg_defines: the AXIS sidebands
// (tlast, tkeep) are packed alongside tdata into a single FIFO word, so frame
// boundaries are preserved across the clock-domain crossing.
//
//   Packed word (MSB -> LSB):  { tlast, tkeep, tdata }
//
//   s_axis_*  : ingress / write clock domain (s_aclk)
//   m_axis_*  : core / read   clock domain (m_aclk)
//
// Read side: the async_fifo core presents the head word continuously while
// !empty (read data tracks the read address). This wrapper adds a 2-entry
// output buffer that absorbs the one-cycle read-address-to-data latency so the
// master side is a clean, full-throughput AXIS source with backpressure.
// =============================================================================
module axis_async_fifo
    import pkg_defines::*;
#(
    parameter int unsigned TDATA_WIDTH = AXIS_DATA_WIDTH,
    parameter int unsigned ADDR_WIDTH  = 5  // depth = 2^ADDR_WIDTH
)(
    input  wire                    rst_n,   // async assert, sync deassert (both domains)

    // ---- Slave / ingress (write clock domain) ----
    input  wire                    s_aclk,
    input  wire [TDATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [TDATA_WIDTH/8-1:0] s_axis_tkeep,
    input  wire                    s_axis_tlast,
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,

    // ---- Master / core (read clock domain) ----
    input  wire                    m_aclk,
    output wire [TDATA_WIDTH-1:0]  m_axis_tdata,
    output wire [TDATA_WIDTH/8-1:0] m_axis_tkeep,
    output wire                    m_axis_tlast,
    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready
);

    localparam int unsigned KEEP_WIDTH    = TDATA_WIDTH / 8;
    localparam int unsigned PAYLOAD_WIDTH = TDATA_WIDTH + KEEP_WIDTH + 1;

    // -------------------------------------------------------------------------
    // Pack the ingress beat into the FIFO word.
    // -------------------------------------------------------------------------
    wire [PAYLOAD_WIDTH-1:0] wr_word;
    assign wr_word = {s_axis_tlast, s_axis_tkeep, s_axis_tdata};

    wire                     full;
    wire                     empty;
    wire [PAYLOAD_WIDTH-1:0] rd_word;
    wire                     rd_en;

    // Write transfer accepted whenever tvalid && !full. The core gates its own
    // pointer/memory write with (wr_en && !full), so driving wr_en = tvalid is
    // safe and matches s_axis_tready = !full.
    assign s_axis_tready = !full;

    async_fifo #(
        .DATA_WIDTH (PAYLOAD_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) core (
        .wr_clk       (s_aclk),
        .rd_clk       (m_aclk),
        .rst_n        (rst_n),
        .wr_data      (wr_word),
        .wr_en        (s_axis_tvalid),
        .full         (full),
        .almost_full  (/* unused */),
        .rd_data      (rd_word),
        .rd_en        (rd_en),
        .empty        (empty),
        .almost_empty (/* unused */)
    );

    // -------------------------------------------------------------------------
    // Read-domain reset (async assert, sync deassert) for the output buffer.
    // -------------------------------------------------------------------------
    wire rd_rst_n;
    reset_sync m_reset_sync (
        .clk    (m_aclk),
        .arst_n (rst_n),
        .srst_n (rd_rst_n)
    );

    // -------------------------------------------------------------------------
    // Output buffer (2 entries) + one outstanding read.
    //
    // Invariant maintained: count + inflight <= 2, so a read is only issued
    // when there is guaranteed room for the result one cycle later.
    // -------------------------------------------------------------------------
    reg  [PAYLOAD_WIDTH-1:0] buf0, buf1;  // buf0 = head (drives master)
    reg  [1:0]               count;       // words currently buffered (0..2)
    reg                      inflight;    // read issued last cycle; rd_word valid now

    wire consume   = (count != 2'd0) && m_axis_tready;
    // Reserve space for the in-flight result: issue only when count+inflight < 2.
    assign rd_en   = !empty && ((count + {1'b0, inflight}) < 2'd2);

    always @(posedge m_aclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            buf0     <= '0;
            buf1     <= '0;
            count    <= 2'd0;
            inflight <= 1'b0;
        end else begin
            inflight <= rd_en;

            // Enqueue (when inflight, rd_word is a valid new word) / dequeue.
            // count + inflight <= 2 guarantees no enqueue when count == 2.
            case ({inflight, consume})
                2'b00: begin
                    // hold
                end
                2'b01: begin
                    // dequeue only
                    buf0  <= buf1;
                    count <= count - 2'd1;
                end
                2'b10: begin
                    // enqueue only
                    if (count == 2'd0) buf0 <= rd_word;
                    else               buf1 <= rd_word;  // count == 1
                    count <= count + 2'd1;
                end
                2'b11: begin
                    // simultaneous enqueue + dequeue -> count unchanged
                    buf0  <= (count == 2'd1) ? rd_word : buf1;
                    if (count == 2'd2) buf1 <= rd_word;
                    // count stays
                end
            endcase
        end
    end

    assign {m_axis_tlast, m_axis_tkeep, m_axis_tdata} = buf0;
    assign m_axis_tvalid = (count != 2'd0);

endmodule
