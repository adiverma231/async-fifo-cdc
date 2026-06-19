`timescale 1ns/1ps

module tb_eth_frame_parser;

    reg         clk;
    reg         rst_n;
    reg  [63:0] s_axis_tdata;
    reg  [7:0]  s_axis_tkeep;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    wire [63:0] m_axis_tdata;
    wire [7:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;
    wire [47:0] dst_mac;
    wire [47:0] src_mac;
    wire [15:0] ether_type;
    wire        hdr_valid;
    reg         hdr_ready;
    wire        frame_error;

    int unsigned errors;
    int unsigned hdr_count;
    int unsigned error_count;
    int unsigned payload_last_count;
    logic [47:0] last_dst_mac;
    logic [47:0] last_src_mac;
    logic [15:0] last_ether_type;
    byte unsigned tx_frame[$];
    byte unsigned expected_payload[$];
    byte unsigned observed_payload[$];

    eth_frame_parser dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        .dst_mac      (dst_mac),
        .src_mac      (src_mac),
        .ether_type   (ether_type),
        .hdr_valid    (hdr_valid),
        .hdr_ready    (hdr_ready),
        .frame_error  (frame_error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        errors = 0;

        apply_reset();
        test_basic_frame();

        apply_reset();
        test_two_byte_payload();

        apply_reset();
        test_unaligned_last_payload();

        apply_reset();
        test_output_backpressure();

        apply_reset();
        test_header_backpressure();

        apply_reset();
        test_short_frame_error();

        if (errors == 0) begin
            $display("PASS: tb_eth_frame_parser completed with no errors");
        end else begin
            $display("FAIL: tb_eth_frame_parser completed with %0d errors", errors);
        end

        $finish;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            hdr_count          = 0;
            error_count        = 0;
            payload_last_count = 0;
            last_dst_mac       = '0;
            last_src_mac       = '0;
            last_ether_type    = '0;
        end else begin
            if (hdr_valid) begin
                hdr_count       = hdr_count + 1;
                last_dst_mac    = dst_mac;
                last_src_mac    = src_mac;
                last_ether_type = ether_type;
            end

            if (frame_error) begin
                error_count = error_count + 1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                collect_payload_word(m_axis_tdata, m_axis_tkeep);
                if (m_axis_tlast) begin
                    payload_last_count = payload_last_count + 1;
                end
            end
        end
    end

    task automatic apply_reset;
        begin
            rst_n         = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tkeep  = '0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            m_axis_tready = 1'b1;
            hdr_ready     = 1'b1;
            tx_frame.delete();
            expected_payload.delete();
            observed_payload.delete();

            repeat (4) @(posedge clk);
            rst_n = 1'b1;
            repeat (4) @(posedge clk);

            hdr_count          = 0;
            error_count        = 0;
            payload_last_count = 0;
            last_dst_mac       = '0;
            last_src_mac       = '0;
            last_ether_type    = '0;
        end
    endtask

    task automatic build_valid_frame(input int payload_len);
        int i;
        begin
            tx_frame.delete();
            expected_payload.delete();
            observed_payload.delete();

            tx_frame.push_back(8'h00);
            tx_frame.push_back(8'h11);
            tx_frame.push_back(8'h22);
            tx_frame.push_back(8'h33);
            tx_frame.push_back(8'h44);
            tx_frame.push_back(8'h55);
            tx_frame.push_back(8'haa);
            tx_frame.push_back(8'hbb);
            tx_frame.push_back(8'hcc);
            tx_frame.push_back(8'hdd);
            tx_frame.push_back(8'hee);
            tx_frame.push_back(8'hff);
            tx_frame.push_back(8'h08);
            tx_frame.push_back(8'h00);

            for (i = 0; i < payload_len; i++) begin
                tx_frame.push_back((8'h80 + i[7:0]) & 8'hff);
                expected_payload.push_back((8'h80 + i[7:0]) & 8'hff);
            end
        end
    endtask

    task automatic build_short_frame;
        int i;
        begin
            tx_frame.delete();
            expected_payload.delete();
            observed_payload.delete();

            for (i = 0; i < 10; i++) begin
                tx_frame.push_back(8'hf0 + i[7:0]);
            end
        end
    endtask

    function automatic [63:0] pack_word(input int base_idx);
        int i;
        begin
            pack_word = '0;
            for (i = 0; i < 8; i++) begin
                if ((base_idx + i) < tx_frame.size()) begin
                    pack_word[i*8 +: 8] = tx_frame[base_idx + i];
                end
            end
        end
    endfunction

    function automatic [7:0] pack_keep(input int base_idx);
        int i;
        begin
            pack_keep = '0;
            for (i = 0; i < 8; i++) begin
                if ((base_idx + i) < tx_frame.size()) begin
                    pack_keep[i] = 1'b1;
                end
            end
        end
    endfunction

    task automatic send_frame;
        int base_idx;
        begin
            for (base_idx = 0; base_idx < tx_frame.size(); base_idx += 8) begin
                @(negedge clk);
                s_axis_tdata  = pack_word(base_idx);
                s_axis_tkeep  = pack_keep(base_idx);
                s_axis_tlast  = ((base_idx + 8) >= tx_frame.size());
                s_axis_tvalid = 1'b1;

                do begin
                    @(posedge clk);
                end while (!s_axis_tready);
            end

            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tkeep  = '0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task automatic collect_payload_word(
        input [63:0] data,
        input [7:0]  keep
    );
        int i;
        begin
            for (i = 0; i < 8; i++) begin
                if (keep[i]) begin
                    observed_payload.push_back(data[i*8 +: 8]);
                end
            end
        end
    endtask

    task automatic wait_for_header(input string name);
        int timeout;
        begin
            timeout = 0;
            while ((hdr_count == 0) && (timeout < 100)) begin
                @(posedge clk);
                timeout++;
            end

            if (hdr_count != 1) begin
                $display("ERROR: %s expected one header, got %0d", name, hdr_count);
                errors++;
            end
        end
    endtask

    task automatic wait_for_payload_last(input string name);
        int timeout;
        begin
            timeout = 0;
            while ((payload_last_count == 0) && (timeout < 100)) begin
                @(posedge clk);
                timeout++;
            end

            if (payload_last_count != 1) begin
                $display("ERROR: %s expected one payload tlast, got %0d", name, payload_last_count);
                errors++;
            end
        end
    endtask

    task automatic check_header(input string name);
        begin
            if (last_dst_mac !== 48'h001122334455) begin
                $display("ERROR: %s dst_mac expected 001122334455 got %012h", name, last_dst_mac);
                errors++;
            end

            if (last_src_mac !== 48'haabbccddeeff) begin
                $display("ERROR: %s src_mac expected aabbccddeeff got %012h", name, last_src_mac);
                errors++;
            end

            if (last_ether_type !== 16'h0800) begin
                $display("ERROR: %s ether_type expected 0800 got %04h", name, last_ether_type);
                errors++;
            end
        end
    endtask

    task automatic check_payload(input string name);
        int i;
        begin
            if (observed_payload.size() != expected_payload.size()) begin
                $display("ERROR: %s payload size expected %0d got %0d",
                         name, expected_payload.size(), observed_payload.size());
                errors++;
            end

            for (i = 0; i < expected_payload.size() && i < observed_payload.size(); i++) begin
                if (observed_payload[i] !== expected_payload[i]) begin
                    $display("ERROR: %s payload[%0d] expected 0x%02h got 0x%02h",
                             name, i, expected_payload[i], observed_payload[i]);
                    errors++;
                end
            end
        end
    endtask

    task automatic check_no_errors(input string name);
        begin
            if (error_count != 0) begin
                $display("ERROR: %s unexpected frame_error count %0d", name, error_count);
                errors++;
            end
        end
    endtask

    task automatic run_valid_case(input string name, input int payload_len);
        begin
            $display("TEST: %s", name);
            build_valid_frame(payload_len);
            send_frame();
            wait_for_header(name);
            wait_for_payload_last(name);
            check_header(name);
            check_payload(name);
            check_no_errors(name);
        end
    endtask

    task automatic test_basic_frame;
        begin
            run_valid_case("basic IPv4 frame", 10);
        end
    endtask

    task automatic test_two_byte_payload;
        begin
            run_valid_case("two-byte payload in header word", 2);
        end
    endtask

    task automatic test_unaligned_last_payload;
        begin
            run_valid_case("unaligned final payload word", 5);
        end
    endtask

    task automatic test_output_backpressure;
        begin
            $display("TEST: output backpressure");
            build_valid_frame(17);

            fork
                send_frame();
                begin
                    repeat (5) @(posedge clk);
                    m_axis_tready = 1'b0;
                    repeat (6) @(posedge clk);
                    m_axis_tready = 1'b1;
                end
            join

            wait_for_header("output backpressure");
            wait_for_payload_last("output backpressure");
            check_header("output backpressure");
            check_payload("output backpressure");
            check_no_errors("output backpressure");
        end
    endtask

    task automatic test_header_backpressure;
        begin
            $display("TEST: header backpressure");
            build_valid_frame(6);
            hdr_ready = 1'b0;

            fork
                send_frame();
                begin
                    repeat (6) @(posedge clk);
                    hdr_ready = 1'b1;
                end
            join

            wait_for_header("header backpressure");
            wait_for_payload_last("header backpressure");
            check_header("header backpressure");
            check_payload("header backpressure");
            check_no_errors("header backpressure");
        end
    endtask

    

endmodule
