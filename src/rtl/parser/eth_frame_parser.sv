// 64-bit AXI-Stream Ethernet parser.
// Byte lane 0 is tdata[7:0]. Preamble/SFD and FCS are assumed to be handled
// by the MAC/PHY layer; this block starts at destination MAC and emits payload.
module eth_frame_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [63:0] s_axis_tdata,
    input  wire [7:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,
    input  wire        s_axis_tlast,

    output reg  [63:0] m_axis_tdata,
    output reg  [7:0]  m_axis_tkeep,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,

    output reg  [47:0] dst_mac,
    output reg  [47:0] src_mac,
    output reg  [15:0] ether_type,
    output reg         hdr_valid,
    input  wire        hdr_ready,
    output reg         frame_error
);

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_HEADER1 = 2'd1;
    localparam [1:0] ST_PAYLOAD = 2'd2;
    localparam [1:0] ST_FLUSH   = 2'd3;

    reg [1:0]  state;
    reg [47:0] dst_mac_next;
    reg [15:0] src_mac_hi;
    reg [15:0] carry_data;
    reg [1:0]  carry_keep;
    reg        flush_pending;

    wire output_ready;
    wire input_fire;
    wire header0_valid;
    wire header1_valid;
    wire [7:0] payload_keep;
    wire [7:0] flush_keep;

    assign output_ready  = !m_axis_tvalid || m_axis_tready;
    assign input_fire    = s_axis_tvalid && s_axis_tready;
    assign header0_valid = &s_axis_tkeep;
    assign header1_valid = &s_axis_tkeep[5:0];
    assign payload_keep  = {s_axis_tkeep[5:0], carry_keep};
    assign flush_keep    = {6'b0, carry_keep};

    always @(*) begin
        s_axis_tready = 1'b0;

        case (state)
            ST_IDLE: begin
                s_axis_tready = output_ready;
            end

            ST_HEADER1: begin
                s_axis_tready = output_ready && hdr_ready;
            end

            ST_PAYLOAD: begin
                s_axis_tready = output_ready;
            end

            ST_FLUSH: begin
                s_axis_tready = 1'b0;
            end

            default: begin
                s_axis_tready = 1'b0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            dst_mac       <= '0;
            src_mac       <= '0;
            ether_type    <= '0;
            hdr_valid     <= 1'b0;
            frame_error   <= 1'b0;
            m_axis_tdata  <= '0;
            m_axis_tkeep  <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            dst_mac_next  <= '0;
            src_mac_hi    <= '0;
            carry_data    <= '0;
            carry_keep    <= '0;
            flush_pending <= 1'b0;
        end else begin
            hdr_valid   <= 1'b0;
            frame_error <= 1'b0;

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
                m_axis_tkeep  <= '0;
            end

            case (state)
                ST_IDLE: begin
                    if (input_fire) begin
                        if (!header0_valid || s_axis_tlast) begin
                            frame_error <= 1'b1;
                            state       <= ST_IDLE;
                        end else begin
                            dst_mac_next <= {
                                s_axis_tdata[7:0],
                                s_axis_tdata[15:8],
                                s_axis_tdata[23:16],
                                s_axis_tdata[31:24],
                                s_axis_tdata[39:32],
                                s_axis_tdata[47:40]
                            };
                            src_mac_hi <= {s_axis_tdata[55:48], s_axis_tdata[63:56]};
                            state      <= ST_HEADER1;
                        end
                    end
                end

                ST_HEADER1: begin
                    if (input_fire) begin
                        if (!header1_valid) begin
                            frame_error <= 1'b1;
                            state       <= ST_IDLE;
                        end else begin
                            dst_mac    <= dst_mac_next;
                            src_mac    <= {
                                src_mac_hi,
                                s_axis_tdata[7:0],
                                s_axis_tdata[15:8],
                                s_axis_tdata[23:16],
                                s_axis_tdata[31:24]
                            };
                            ether_type <= {s_axis_tdata[39:32], s_axis_tdata[47:40]};
                            hdr_valid  <= 1'b1;

                            carry_data <= s_axis_tdata[63:48];
                            carry_keep <= s_axis_tkeep[7:6];

                            if (s_axis_tlast) begin
                                if (|s_axis_tkeep[7:6]) begin
                                    m_axis_tdata  <= {48'b0, s_axis_tdata[63:48]};
                                    m_axis_tkeep  <= {6'b0, s_axis_tkeep[7:6]};
                                    m_axis_tvalid <= 1'b1;
                                    m_axis_tlast  <= 1'b1;
                                end
                                state <= ST_IDLE;
                            end else begin
                                state <= ST_PAYLOAD;
                            end
                        end
                    end
                end

                ST_PAYLOAD: begin
                    if (input_fire) begin
                        m_axis_tdata  <= {s_axis_tdata[47:0], carry_data};
                        m_axis_tkeep  <= payload_keep;
                        m_axis_tvalid <= |payload_keep;
                        m_axis_tlast  <= s_axis_tlast && !(|s_axis_tkeep[7:6]);

                        carry_data <= s_axis_tdata[63:48];
                        carry_keep <= s_axis_tkeep[7:6];

                        if (s_axis_tlast) begin
                            flush_pending <= |s_axis_tkeep[7:6];
                            state         <= (|s_axis_tkeep[7:6]) ? ST_FLUSH : ST_IDLE;
                        end
                    end
                end

                ST_FLUSH: begin
                    if (output_ready && flush_pending) begin
                        m_axis_tdata  <= {48'b0, carry_data};
                        m_axis_tkeep  <= flush_keep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b1;
                        flush_pending <= 1'b0;
                        state         <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
