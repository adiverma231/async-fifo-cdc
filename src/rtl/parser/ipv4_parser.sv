// =============================================================================
// ipv4_parser.sv
// -----------------------------------------------------------------------------
// 64-bit AXI-Stream IPv4 parser. Consumes the L3 payload emitted by the
// Ethernet parser (an IP packet starting at the IPv4 header) and emits the L4
// payload (e.g. a UDP datagram), realigned to lane 0. Header fields and a
// validity pulse are exposed on a sideband.
//
// Datapath width comes from pkg_defines (AXIS_DATA_WIDTH, default 64). Only
// standard 20-byte headers (IHL=5) are supported; non-standard headers are
// flagged and the packet is dropped (datapath restricted per the project plan).
//
// The 20-byte header spans 2.5 beats (20 mod 8 = 4), so the payload realignment
// carry is 4 bytes (cf. the 2-byte carry in eth_frame_parser.sv). The header
// checksum is accumulated across the three header beats and validity is known
// exactly when the payload begins (HDR2), so a bad packet leaks no payload.
// =============================================================================
module ipv4_parser
    import pkg_defines::*;
(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire [AXIS_KEEP_WIDTH-1:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,
    input  wire        s_axis_tlast,

    output reg  [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output reg  [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,

    // Header sideband (valid the cycle hdr_valid pulses; held afterward)
    output reg  [3:0]  version,
    output reg  [3:0]  ihl,
    output reg  [15:0] total_length,
    output reg  [7:0]  protocol,
    output reg  [31:0] src_ip,
    output reg  [31:0] dst_ip,
    output reg         hdr_valid,
    input  wire        hdr_ready,

    // Error pulses (one cycle, packet dropped)
    output reg         err_version,    // version != 4
    output reg         err_options,    // IHL != 5 (options present)
    output reg         err_checksum,   // header checksum invalid
    output reg         err_truncated   // frame ended before the 20-byte header
);

    localparam [2:0] ST_IDLE    = 3'd0;  // beat0: bytes 0-7
    localparam [2:0] ST_HDR1    = 3'd1;  // beat1: bytes 8-15
    localparam [2:0] ST_HDR2    = 3'd2;  // beat2: bytes 16-23 (payload @ byte 20)
    localparam [2:0] ST_PAYLOAD = 3'd3;
    localparam [2:0] ST_FLUSH   = 3'd4;
    localparam [2:0] ST_DRAIN   = 3'd5;  // discard rest of a rejected packet

    reg [2:0]  state;
    reg [3:0]  version_r;
    reg [3:0]  ihl_r;
    reg [15:0] total_length_r;
    reg [7:0]  protocol_r;
    reg [31:0] src_ip_r;
    reg [31:0] carry_data;
    reg [3:0]  carry_keep;
    reg        flush_pending;
    reg [31:0] csum_acc;

    wire output_ready;
    wire input_fire;
    wire full_beat;
    wire tail4_present;
    wire [7:0] payload_keep;
    wire [7:0] flush_keep;

    // 16-bit big-endian header words of the current beat (lane 0 = first byte),
    // zero-extended to 32 bits so all checksum arithmetic is width-consistent.
    wire [31:0] cw0 = {16'b0, s_axis_tdata[7:0],   s_axis_tdata[15:8]};
    wire [31:0] cw1 = {16'b0, s_axis_tdata[23:16], s_axis_tdata[31:24]};
    wire [31:0] cw2 = {16'b0, s_axis_tdata[39:32], s_axis_tdata[47:40]};
    wire [31:0] cw3 = {16'b0, s_axis_tdata[55:48], s_axis_tdata[63:56]};
    wire [31:0] sum_full = cw0 + cw1 + cw2 + cw3;  // 4 words (8 bytes)
    wire [31:0] sum_half = cw0 + cw1;              // first 2 words (bytes 0-3)

    // Finalize the ones-complement checksum at HDR2: fold carries twice, expect
    // 0xFFFF. (Two folds suffice: the running sum is at most ~20 bits.)
    wire [31:0] csum_total = csum_acc + sum_half;
    wire [31:0] csum_fold1 = {16'b0, csum_total[15:0]} + {16'b0, csum_total[31:16]};
    wire [31:0] csum_fold2 = {16'b0, csum_fold1[15:0]} + {16'b0, csum_fold1[31:16]};
    wire        checksum_ok = (csum_fold2[15:0] == 16'hFFFF);

    assign output_ready  = !m_axis_tvalid || m_axis_tready;
    assign input_fire    = s_axis_tvalid && s_axis_tready;
    assign full_beat     = &s_axis_tkeep;
    assign tail4_present  = &s_axis_tkeep[3:0];               // bytes 16-19 present
    assign payload_keep  = {s_axis_tkeep[3:0], carry_keep};
    assign flush_keep    = {4'b0, carry_keep};

    always @(*) begin
        case (state)
            ST_IDLE:    s_axis_tready = output_ready;
            ST_HDR1:    s_axis_tready = output_ready;
            ST_HDR2:    s_axis_tready = output_ready && hdr_ready;
            ST_PAYLOAD: s_axis_tready = output_ready;
            ST_DRAIN:   s_axis_tready = 1'b1;
            default:    s_axis_tready = 1'b0;   // ST_FLUSH
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            version        <= '0;
            ihl            <= '0;
            total_length   <= '0;
            protocol       <= '0;
            src_ip         <= '0;
            dst_ip         <= '0;
            hdr_valid      <= 1'b0;
            err_version    <= 1'b0;
            err_options    <= 1'b0;
            err_checksum   <= 1'b0;
            err_truncated  <= 1'b0;
            m_axis_tdata   <= '0;
            m_axis_tkeep   <= '0;
            m_axis_tvalid  <= 1'b0;
            m_axis_tlast   <= 1'b0;
            version_r      <= '0;
            ihl_r          <= '0;
            total_length_r <= '0;
            protocol_r     <= '0;
            src_ip_r       <= '0;
            carry_data     <= '0;
            carry_keep     <= '0;
            flush_pending  <= 1'b0;
            csum_acc       <= '0;
        end else begin
            hdr_valid     <= 1'b0;
            err_version   <= 1'b0;
            err_options   <= 1'b0;
            err_checksum  <= 1'b0;
            err_truncated <= 1'b0;

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
                m_axis_tkeep  <= '0;
            end

            case (state)
                ST_IDLE: begin
                    if (input_fire) begin
                        if (!full_beat || s_axis_tlast) begin
                            err_truncated <= 1'b1;
                            state         <= s_axis_tlast ? ST_IDLE : ST_DRAIN;
                        end else if (s_axis_tdata[7:4] != 4'd4) begin
                            err_version <= 1'b1;
                            state       <= ST_DRAIN;
                        end else if (s_axis_tdata[3:0] != 4'd5) begin
                            err_options <= 1'b1;
                            state       <= ST_DRAIN;
                        end else begin
                            version_r      <= s_axis_tdata[7:4];
                            ihl_r          <= s_axis_tdata[3:0];
                            total_length_r <= {s_axis_tdata[23:16], s_axis_tdata[31:24]};
                            csum_acc       <= sum_full;
                            state          <= ST_HDR1;
                        end
                    end
                end

                ST_HDR1: begin
                    if (input_fire) begin
                        if (!full_beat || s_axis_tlast) begin
                            err_truncated <= 1'b1;
                            state         <= s_axis_tlast ? ST_IDLE : ST_DRAIN;
                        end else begin
                            protocol_r <= s_axis_tdata[15:8];
                            src_ip_r   <= {
                                s_axis_tdata[39:32], s_axis_tdata[47:40],
                                s_axis_tdata[55:48], s_axis_tdata[63:56]
                            };
                            csum_acc <= csum_acc + sum_full;
                            state    <= ST_HDR2;
                        end
                    end
                end

                ST_HDR2: begin
                    if (input_fire) begin
                        if (!tail4_present) begin
                            err_truncated <= 1'b1;
                            state         <= s_axis_tlast ? ST_IDLE : ST_DRAIN;
                        end else if (!checksum_ok) begin
                            err_checksum <= 1'b1;
                            state        <= s_axis_tlast ? ST_IDLE : ST_DRAIN;
                        end else begin
                            version      <= version_r;
                            ihl          <= ihl_r;
                            total_length <= total_length_r;
                            protocol     <= protocol_r;
                            src_ip       <= src_ip_r;
                            dst_ip       <= {
                                s_axis_tdata[7:0],   s_axis_tdata[15:8],
                                s_axis_tdata[23:16], s_axis_tdata[31:24]
                            };
                            hdr_valid  <= 1'b1;

                            carry_data <= s_axis_tdata[63:32];
                            carry_keep <= s_axis_tkeep[7:4];

                            if (s_axis_tlast) begin
                                if (|s_axis_tkeep[7:4]) begin
                                    m_axis_tdata  <= {32'b0, s_axis_tdata[63:32]};
                                    m_axis_tkeep  <= {4'b0, s_axis_tkeep[7:4]};
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
                        m_axis_tdata  <= {s_axis_tdata[31:0], carry_data};
                        m_axis_tkeep  <= payload_keep;
                        m_axis_tvalid <= |payload_keep;
                        m_axis_tlast  <= s_axis_tlast && !(|s_axis_tkeep[7:4]);

                        carry_data <= s_axis_tdata[63:32];
                        carry_keep <= s_axis_tkeep[7:4];

                        if (s_axis_tlast) begin
                            flush_pending <= |s_axis_tkeep[7:4];
                            state         <= (|s_axis_tkeep[7:4]) ? ST_FLUSH : ST_IDLE;
                        end
                    end
                end

                ST_FLUSH: begin
                    if (output_ready && flush_pending) begin
                        m_axis_tdata  <= {32'b0, carry_data};
                        m_axis_tkeep  <= flush_keep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b1;
                        flush_pending <= 1'b0;
                        state         <= ST_IDLE;
                    end
                end

                ST_DRAIN: begin
                    if (input_fire && s_axis_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
