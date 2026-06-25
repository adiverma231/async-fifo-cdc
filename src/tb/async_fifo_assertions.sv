module async_fifo_assertions #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4
)(
    input wire                  wr_clk,
    input wire                  rd_clk,
    input wire                  wr_rst_n,
    input wire                  rd_rst_n,

    input wire                  wr_en,
    input wire                  rd_en,
    input wire                  full,
    input wire                  almost_full,
    input wire                  empty,
    input wire                  almost_empty,
    input wire                  wr_mem_en,

    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    input wire [ADDR_WIDTH:0]   wptr_gray,
    input wire [ADDR_WIDTH:0]   rptr_gray
);

    property p_write_enable_gated;
        @(posedge wr_clk) disable iff (!wr_rst_n)
            wr_mem_en == (wr_en && !full);
    endproperty

    property p_write_blocked_when_full;
        @(posedge wr_clk) disable iff (!wr_rst_n)
            (wr_en && full) |=> ($stable(wptr_gray) && $stable(wr_addr));
    endproperty

    property p_write_pointer_only_advances_on_accepted_write;
        @(posedge wr_clk) disable iff (!wr_rst_n)
            !(wr_en && !full) |=> ($stable(wptr_gray) && $stable(wr_addr));
    endproperty

    property p_write_gray_one_bit_change;
        @(posedge wr_clk) disable iff (!wr_rst_n)
            $onehot0(wptr_gray ^ $past(wptr_gray));
    endproperty

    property p_write_reset_state;
        @(posedge wr_clk)
            !wr_rst_n |=> (wptr_gray == '0 && full == 1'b0 && almost_full == 1'b0);
    endproperty

    property p_write_flags_known;
        @(posedge wr_clk) disable iff (!wr_rst_n)
            !$isunknown({full, almost_full, wr_mem_en});
    endproperty

    property p_read_blocked_when_empty;
        @(posedge rd_clk) disable iff (!rd_rst_n)
            (rd_en && empty) |=> ($stable(rptr_gray) && $stable(rd_addr));
    endproperty

    property p_read_pointer_only_advances_on_accepted_read;
        @(posedge rd_clk) disable iff (!rd_rst_n)
            !(rd_en && !empty) |=> ($stable(rptr_gray) && $stable(rd_addr));
    endproperty

    property p_read_gray_one_bit_change;
        @(posedge rd_clk) disable iff (!rd_rst_n)
            $onehot0(rptr_gray ^ $past(rptr_gray));
    endproperty

    property p_read_reset_state;
        @(posedge rd_clk)
            !rd_rst_n |=> (rptr_gray == '0 && empty == 1'b1 && almost_empty == 1'b1);
    endproperty

    property p_read_flags_known;
        @(posedge rd_clk) disable iff (!rd_rst_n)
            !$isunknown({empty, almost_empty});
    endproperty

    a_write_enable_gated:
        assert property (p_write_enable_gated)
        else $error("wr_mem_en must equal wr_en && !full");

    a_write_blocked_when_full:
        assert property (p_write_blocked_when_full)
        else $error("write pointer advanced while full");

    a_write_pointer_only_advances_on_accepted_write:
        assert property (p_write_pointer_only_advances_on_accepted_write)
        else $error("write pointer changed without an accepted write");

    a_write_gray_one_bit_change:
        assert property (p_write_gray_one_bit_change)
        else $error("write Gray pointer changed by more than one bit");

    a_write_reset_state:
        assert property (p_write_reset_state)
        else $error("write-domain reset state is incorrect");

    a_write_flags_known:
        assert property (p_write_flags_known)
        else $error("write-domain status contains X/Z");

    a_read_blocked_when_empty:
        assert property (p_read_blocked_when_empty)
        else $error("read pointer advanced while empty");

    a_read_pointer_only_advances_on_accepted_read:
        assert property (p_read_pointer_only_advances_on_accepted_read)
        else $error("read pointer changed without an accepted read");

    a_read_gray_one_bit_change:
        assert property (p_read_gray_one_bit_change)
        else $error("read Gray pointer changed by more than one bit");

    a_read_reset_state:
        assert property (p_read_reset_state)
        else $error("read-domain reset state is incorrect");

    a_read_flags_known:
        assert property (p_read_flags_known)
        else $error("read-domain status contains X/Z");

endmodule

bind async_fifo async_fifo_assertions #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) async_fifo_assertions_inst (
    .wr_clk      (wr_clk),
    .rd_clk      (rd_clk),
    .wr_rst_n    (wr_rst_n),
    .rd_rst_n    (rd_rst_n),
    .wr_en       (wr_en),
    .rd_en       (rd_en),
    .full        (full),
    .almost_full (almost_full),
    .empty       (empty),
    .almost_empty(almost_empty),
    .wr_mem_en   (wr_mem_en),
    .wr_addr     (wr_addr),
    .rd_addr     (rd_addr),
    .wptr_gray   (wptr_gray),
    .rptr_gray   (rptr_gray)
);
