`timescale 1ns/1ps

module tb_async_fifo;

    localparam DATA_WIDTH   = 8;
    localparam ADDR_WIDTH   = 3;
    localparam DEPTH        = 1 << ADDR_WIDTH;
    localparam AFULL_THRES  = DEPTH - 2;
    localparam AEMPTY_THRES = 2;

    time wr_half_period;
    time rd_half_period;

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
    int unsigned model_count;
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

    initial begin
        wr_half_period = 5ns;
        wr_clk = 1'b0;
        forever #(wr_half_period) wr_clk = ~wr_clk;
    end

    initial begin
        rd_half_period = 7ns;
        rd_clk = 1'b0;
        forever #(rd_half_period) rd_clk = ~rd_clk;
    end

    initial begin
        errors = 0;

        run_ratio_test("write faster than read", 5ns, 7ns);
        run_ratio_test("read faster than write", 9ns, 3ns);

        if (errors == 0) begin
            $display("PASS: tb_async_fifo completed with no errors");
        end else begin
            $display("FAIL: tb_async_fifo completed with %0d errors", errors);
        end

        $finish;
    end

    task automatic run_ratio_test(
        input string name,
        input time   wr_half,
        input time   rd_half
    );
        begin
            $display("TEST RATIO: %s", name);
            wr_half_period = wr_half;
            rd_half_period = rd_half;

            apply_reset();
            check_reset_state();
            test_fill_flags_and_overflow();
            test_drain_flags_and_empty();

            apply_reset();
            test_async_random();
        end
    endtask

    task automatic apply_reset;
        begin
            rst_n       = 1'b0;
            wr_data     = '0;
            wr_en       = 1'b0;
            rd_en       = 1'b0;
            model_count = 0;
            expected_q.delete();

            repeat (4) @(posedge wr_clk);
            #3;
            rst_n = 1'b1;

            repeat (4) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
        end
    endtask

    task automatic check_reset_state;
        begin
            if (!empty) begin
                $display("ERROR: FIFO should be empty after reset");
                errors++;
            end

            if (!almost_empty) begin
                $display("ERROR: FIFO should be almost_empty after reset");
                errors++;
            end

            if (full) begin
                $display("ERROR: FIFO should not be full after reset");
                errors++;
            end

            if (almost_full) begin
                $display("ERROR: FIFO should not be almost_full after reset");
                errors++;
            end
        end
    endtask

    task automatic attempt_write(
        input  byte unsigned data,
        output bit           accepted
    );
        bit was_full;
        begin
            @(negedge wr_clk);
            wr_data = data;
            wr_en   = 1'b1;

            @(posedge wr_clk);
            was_full = full;
            #1;
            accepted = !was_full;

            @(negedge wr_clk);
            wr_en = 1'b0;
        end
    endtask

    task automatic expect_write(input byte unsigned data);
        bit accepted;
        begin
            attempt_write(data, accepted);
            if (!accepted) begin
                $display("ERROR: write 0x%0h was rejected unexpectedly", data);
                errors++;
            end else begin
                expected_q.push_back(data);
                model_count++;
            end
        end
    endtask

    task automatic attempt_read(
        output bit           accepted,
        output byte unsigned data
    );
        bit was_empty;
        begin
            data = '0;

            @(negedge rd_clk);
            rd_en = 1'b1;

            @(posedge rd_clk);
            was_empty = empty;
            #1;
            accepted = !was_empty;
            if (accepted) begin
                data = rd_data;
            end

            @(negedge rd_clk);
            rd_en = 1'b0;
        end
    endtask

    task automatic expect_read;
        bit accepted;
        byte unsigned actual;
        byte unsigned expected;
        begin
            if (expected_q.size() == 0) begin
                $display("ERROR: scoreboard underflow before read");
                errors++;
                return;
            end

            attempt_read(accepted, actual);
            if (!accepted) begin
                $display("ERROR: read was rejected unexpectedly");
                errors++;
                return;
            end

            expected = expected_q.pop_front();
            model_count--;
            if (actual !== expected) begin
                $display("ERROR: read mismatch, expected 0x%0h got 0x%0h", expected, actual);
                errors++;
            end
        end
    endtask

    task automatic check_almost_full(input string where);
        bit exp_afull;
        begin
            exp_afull  = (model_count >= AFULL_THRES);

            if (almost_full !== exp_afull) begin
                $display("ERROR: almost_full mismatch at %s count=%0d expected=%0b got=%0b",
                         where, model_count, exp_afull, almost_full);
                errors++;
            end
        end
    endtask

    task automatic check_almost_empty(input string where);
        bit exp_aempty;
        begin
            exp_aempty = (model_count <= AEMPTY_THRES);

            if (almost_empty !== exp_aempty) begin
                $display("ERROR: almost_empty mismatch at %s count=%0d expected=%0b got=%0b",
                         where, model_count, exp_aempty, almost_empty);
                errors++;
            end
        end
    endtask

    task automatic test_fill_flags_and_overflow;
        int i;
        bit accepted;
        begin
            $display("TEST: fill, almost_full, full, overflow protection");

            for (i = 0; i < DEPTH; i++) begin
                wait (!full);
                expect_write(i[7:0]);
                check_almost_full("fill");
            end

            if (!full) begin
                $display("ERROR: full should assert after %0d accepted writes", DEPTH);
                errors++;
            end

            attempt_write(8'hff, accepted);
            if (accepted) begin
                $display("ERROR: overflow write was accepted while full");
                errors++;
                expected_q.push_back(8'hff);
                model_count++;
            end
        end
    endtask

    task automatic test_drain_flags_and_empty;
        int i;
        begin
            $display("TEST: drain, almost_empty, empty, overflow data absence");

            repeat (4) @(posedge rd_clk);

            for (i = 0; i < DEPTH; i++) begin
                wait (!empty);
                expect_read();
                check_almost_empty("drain");
            end

            if (!empty) begin
                $display("ERROR: empty should assert after draining FIFO");
                errors++;
            end

            if (expected_q.size() != 0) begin
                $display("ERROR: scoreboard not empty after drain, size=%0d", expected_q.size());
                errors++;
            end
        end
    endtask

    task automatic test_async_random;
        mailbox random_mb;
        int writes_done;
        int reads_done;
        int total_words;
        begin
            $display("TEST: randomized async traffic");

            random_mb   = new();
            writes_done = 0;
            reads_done  = 0;
            total_words  = 200;

            fork
                begin : writer
                    bit was_full;
                    byte unsigned data;

                    while (writes_done < total_words) begin
                        @(negedge wr_clk);
                        if ($urandom_range(0, 2) != 0) begin
                            data    = writes_done[7:0];
                            wr_data = data;
                            wr_en   = 1'b1;
                        end else begin
                            wr_en = 1'b0;
                        end

                        @(posedge wr_clk);
                        was_full = full;
                        #1;
                        if (wr_en && !was_full) begin
                            random_mb.put(data);
                            writes_done++;
                        end
                    end

                    @(negedge wr_clk);
                    wr_en = 1'b0;
                end

                begin : reader
                    bit was_empty;
                    int expected;

                    while (reads_done < total_words) begin
                        @(negedge rd_clk);
                        rd_en = ($urandom_range(0, 2) != 0);

                        @(posedge rd_clk);
                        was_empty = empty;
                        #1;
                        if (rd_en && !was_empty) begin
                            if (!random_mb.try_get(expected)) begin
                                $display("ERROR: FIFO produced data before scoreboard had data");
                                errors++;
                            end else if (rd_data !== expected[DATA_WIDTH-1:0]) begin
                                $display("ERROR: random read mismatch at read %0d, expected 0x%0h got 0x%0h",
                                         reads_done, expected[DATA_WIDTH-1:0], rd_data);
                                errors++;
                            end
                            reads_done++;
                        end
                    end

                    @(negedge rd_clk);
                    rd_en = 1'b0;
                end
            join
        end
    endtask

endmodule
