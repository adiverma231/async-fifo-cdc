// =============================================================================
// fifo_props.sv
// -----------------------------------------------------------------------------
// Formal safety properties for the async_fifo CDC core, bound into the DUT and
// proven with SymbiYosys (see async_fifo.sby). Scope is the FIFO only, per the
// project plan: prove the FIFO can never overflow or underflow.
//
// The flow is MULTICLOCK (clk2fflogic): the two clocks are modeled as ordinary
// signals the solver may toggle independently, so there is no global sampling
// clock and SVA concurrent assertions cannot be used. The safety invariants
// here are therefore expressed as IMMEDIATE combinational assertions, which is
// exactly right for them -- they must hold continuously, in any clock phase.
//
// "occ" is the TRUE occupancy from both un-synchronized gray pointers. The
// no-overflow argument: the write side computes `full` from the *synchronized*
// (older, hence <=) read pointer, so its apparent occupancy >= true occupancy;
// writes stop at apparent occupancy == DEPTH, so true occupancy <= DEPTH always.
// Symmetrically `empty` is conservative, so reads never see a truly-empty FIFO.
//
// (The temporal gray-pointer "one-bit-change" CDC property needs a sampling
// clock and is covered by the simulation SVA in src/tb/async_fifo_assertions.sv.)
// =============================================================================
module fifo_props #(
    parameter int ADDR_WIDTH = 4
)(
    input wire                  wr_clk,
    input wire                  rst_n,
    input wire                  wr_rst_n,
    input wire                  rd_rst_n,
    input wire                  wr_en,
    input wire                  rd_en,
    input wire                  full,
    input wire                  empty,
    input wire                  wr_mem_en,
    input wire [ADDR_WIDTH:0]   wptr_gray,
    input wire [ADDR_WIDTH:0]   rptr_gray
);

    localparam int unsigned DEPTH = 1 << ADDR_WIDTH;

    function automatic [ADDR_WIDTH:0] gray_to_bin(input [ADDR_WIDTH:0] gray);
        integer i;
        begin
            gray_to_bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i = ADDR_WIDTH - 1; i >= 0; i = i - 1)
                gray_to_bin[i] = gray_to_bin[i + 1] ^ gray[i];
        end
    endfunction

    wire [ADDR_WIDTH:0] wbin = gray_to_bin(wptr_gray);
    wire [ADDR_WIDTH:0] rbin = gray_to_bin(rptr_gray);
    wire [ADDR_WIDTH:0] occ  = wbin - rbin;            // mod 2^(ADDR_WIDTH+1)

    wire out_of_reset = wr_rst_n && rd_rst_n;

    // ---- Formal reset: hold rst_n low for the first few wr_clk edges so the
    //      per-domain reset synchronizers initialize before any check. ----
    reg [3:0] init_cnt = 4'd0;
    always @(posedge wr_clk)
        if (init_cnt != 4'hf)
            init_cnt <= init_cnt + 4'd1;

    always @(*)
        if (init_cnt < 4'd4)
            assume (!rst_n);

    // ---- Safety invariants (must hold continuously, any clock phase) ----
    always @(*) begin
        if (out_of_reset) begin
            assert (occ <= DEPTH[ADDR_WIDTH:0]);            // no overflow
            assert (!(wr_mem_en && (occ == DEPTH[ADDR_WIDTH:0])));  // no write into full
            assert (!(rd_en && !empty && (occ == 0)));      // no underflow
        end
    end

    // ---- Reachability covers: the FIFO can actually fill and empty ----
    always @(*) begin
        if (out_of_reset) begin
            cover (occ == DEPTH[ADDR_WIDTH:0]);   // reaches full occupancy
            cover (full);
            cover (empty && (occ == 0));          // reaches genuine empty
        end
    end

endmodule

bind async_fifo fifo_props #(
    .ADDR_WIDTH(ADDR_WIDTH)
) fifo_props_i (
    .wr_clk   (wr_clk),
    .rst_n    (rst_n),
    .wr_rst_n (wr_rst_n),
    .rd_rst_n (rd_rst_n),
    .wr_en    (wr_en),
    .rd_en    (rd_en),
    .full     (full),
    .empty    (empty),
    .wr_mem_en(wr_mem_en),
    .wptr_gray(wptr_gray),
    .rptr_gray(rptr_gray)
);
