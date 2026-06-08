`timescale 1ns/1ps

module tb_async_fifo;

    localparam DATA_WIDTH   = 8;
    localparam ADDR_WIDTH   = 3;
    localparam DEPTH        = 1 << ADDR_WIDTH;
    localparam AFULL_THRES  = DEPTH - 2;
    localparam AEMPTY_THRES = 2;

    reg                   wr_clk;
    reg                   rd_clk;
    reg                   rst_n;
    reg  [DATA_WIDTH-1:0] wr_data;
    reg                   wr_en;
    wire                  full;
    wire                  almost_full;
    wire [DATA_WIDTH-1:0] rd_data;
    reg                   rd_en;
    wire                  empty;
    wire                  almost_empty;

    int unsigned errors;
    byte unsigned expected_q[$];

    async_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .AFULL_THRES (AFULL_THRES),
        .AEMPTY_THRES(AEMPTY_THRES)
    ) dut (
        .wr_clk      (wr_clk),
        .rd_clk      (rd_clk),
        .rst_n       (rst_n),
        .wr_data     (wr_data),
        .wr_en       (wr_en),
        .full        (full),
        .almost_full (almost_full),
        .rd_data     (rd_data),
        .rd_en       (rd_en),
        .empty       (empty),
        .almost_empty(almost_empty)
    );

    initial wr_clk = 1'b0;
    always #5 wr_clk = ~wr_clk;

    initial rd_clk = 1'b0;
    always #7 rd_clk = ~rd_clk;

    initial begin
        errors  = 0;
        rst_n   = 1'b0;
        wr_data = '0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;

        repeat (5) @(posedge wr_clk);
        rst_n = 1'b1;
        repeat (5) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);

        check_reset_state();
        test_fill_and_full();
        test_drain_and_empty();
        test_async_random();

        if (errors == 0) begin
            $display("PASS: tb_async_fifo completed with no errors");
        end else begin
            $display("FAIL: tb_async_fifo completed with %0d errors", errors);
        end

        $finish;
    end

    task automatic check_reset_state;
        begin
            if (!empty) begin
                $display("ERROR: FIFO should be empty after reset");
                errors++;
            end

            if (full) begin
                $display("ERROR: FIFO should not be full after reset");
                errors++;
            end
        end
    endtask

    task automatic write_word(input byte unsigned data);
        begin
            @(negedge wr_clk);
            wr_data = data;
            wr_en   = 1'b1;
            @(negedge wr_clk);
            wr_en   = 1'b0;
            expected_q.push_back(data);
        end
    endtask

    task automatic read_word;
        byte unsigned expected;
        begin
            if (expected_q.size() == 0) begin
                $display("ERROR: scoreboard underflow before read");
                errors++;
                return;
            end

            expected = expected_q.pop_front();

            @(negedge rd_clk);
            rd_en = 1'b1;
            @(posedge rd_clk);
            #1;
            if (rd_data !== expected) begin
                $display("ERROR: read mismatch, expected 0x%0h got 0x%0h", expected, rd_data);
                errors++;
            end
            @(negedge rd_clk);
            rd_en = 1'b0;
        end
    endtask

    task automatic test_fill_and_full;
        int i;
        begin
            $display("TEST: fill and full");

            for (i = 0; i < DEPTH; i++) begin
                wait (!full);
                write_word(i[7:0]);
            end

            repeat (3) @(posedge wr_clk);
            if (!full) begin
                $display("ERROR: full should assert after %0d writes", DEPTH);
                errors++;
            end

            @(negedge wr_clk);
            wr_data = 8'hff;
            wr_en   = 1'b1;
            @(negedge wr_clk);
            wr_en   = 1'b0;

            if (expected_q.size() != DEPTH) begin
                $display("ERROR: extra write changed scoreboard size");
                errors++;
            end
        end
    endtask

    task automatic test_drain_and_empty;
        int i;
        begin
            $display("TEST: drain and empty");

            for (i = 0; i < DEPTH; i++) begin
                wait (!empty);
                read_word();
            end

            repeat (3) @(posedge rd_clk);
            if (!empty) begin
                $display("ERROR: empty should assert after draining FIFO");
                errors++;
            end
        end
    endtask

    task automatic test_async_random;
        int writes_done;
        int reads_done;
        int total_words;
        begin
            $display("TEST: randomized async traffic");

            writes_done = 0;
            reads_done  = 0;
            total_words  = 200;

            fork
                begin : writer
                    while (writes_done < total_words) begin
                        @(negedge wr_clk);
                        if (!full && ($urandom_range(0, 2) != 0)) begin
                            wr_data = writes_done[7:0];
                            wr_en   = 1'b1;
                            expected_q.push_back(writes_done[7:0]);
                            writes_done++;
                        end else begin
                            wr_en = 1'b0;
                        end
                    end

                    @(negedge wr_clk);
                    wr_en = 1'b0;
                end

                begin : reader
                    while (reads_done < total_words) begin
                        @(negedge rd_clk);
                        if (!empty && expected_q.size() != 0 && ($urandom_range(0, 2) != 0)) begin
                            rd_en = 1'b1;
                            @(posedge rd_clk);
                            #1;
                            if (rd_data !== expected_q.pop_front()) begin
                                $display("ERROR: random read mismatch at read %0d", reads_done);
                                errors++;
                            end
                            reads_done++;
                        end else begin
                            rd_en = 1'b0;
                        end
                    end

                    @(negedge rd_clk);
                    rd_en = 1'b0;
                end
            join

            if (expected_q.size() != 0) begin
                $display("ERROR: scoreboard not empty after random test, size=%0d", expected_q.size());
                errors++;
            end
        end
    endtask

endmodule