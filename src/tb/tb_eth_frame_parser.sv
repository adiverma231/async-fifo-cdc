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

    