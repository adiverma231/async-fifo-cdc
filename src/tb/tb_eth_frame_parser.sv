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

    