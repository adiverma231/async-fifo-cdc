// =============================================================================
// pkg_defines.sv
// -----------------------------------------------------------------------------
// Shared definitions for the low-latency packet-processing pipeline:
//   * AXI-Stream datapath defaults (width, keep)
//   * The async-FIFO CDC payload packing convention (tlast/tkeep/tdata)
//   * Packed protocol header structs (Ethernet / IPv4 / UDP)
//   * Protocol constants used by the classifier
//
// This package is the single source of truth for the AXIS framing decision:
// the async FIFO carries the AXIS sidebands (tlast, tkeep) alongside tdata so
// that frame boundaries survive the clock-domain crossing. Every module that
// touches the stream packs/unpacks in the SAME order defined here.
// =============================================================================
package pkg_defines;

    // -------------------------------------------------------------------------
    // AXI-Stream datapath defaults
    // -------------------------------------------------------------------------
    // 64-bit (8 bytes/cycle) is the project default; modules are parameterized
    // and may override, but should default to these.
    localparam int unsigned AXIS_DATA_WIDTH = 64;
    localparam int unsigned AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;  // 1 bit/byte

    // -------------------------------------------------------------------------
    // Async-FIFO CDC payload packing
    // -------------------------------------------------------------------------
    // Canonical packing order, MSB -> LSB:  { tlast, tkeep, tdata }
    //
    // The async FIFO is data-width agnostic, so the wrapper concatenates in
    // this order for any TDATA_WIDTH. This struct is the default-width witness
    // of that order and is what system_top / downstream stages should use.
    typedef struct packed {
        logic                         tlast;
        logic [AXIS_KEEP_WIDTH-1:0]   tkeep;
        logic [AXIS_DATA_WIDTH-1:0]   tdata;
    } axis_word_t;

    localparam int unsigned AXIS_WORD_WIDTH = $bits(axis_word_t);

    // Width of the packed FIFO word for an arbitrary tdata width. Keep this in
    // lockstep with the concatenation in axis_async_fifo.sv.
    //   width = tdata + tkeep(tdata/8) + tlast(1)
    function automatic int unsigned axis_word_width(input int unsigned tdata_w);
        axis_word_width = tdata_w + (tdata_w / 8) + 1;
    endfunction

    // -------------------------------------------------------------------------
    // Protocol header structs (standard, no-options cases)
    // -------------------------------------------------------------------------
    // Field order is wire order (first byte on the wire = most-significant
    // field). Endianness of multi-byte fields is network (big-endian); the
    // parsers are responsible for presenting these in host order.

    // Ethernet II header (14 bytes), preamble/SFD/FCS handled by MAC/PHY.
    typedef struct packed {
        logic [47:0] dst_mac;
        logic [47:0] src_mac;
        logic [15:0] ether_type;
    } eth_hdr_t;

    // IPv4 header (20 bytes, IHL == 5, no options).
    typedef struct packed {
        logic [3:0]  version;
        logic [3:0]  ihl;
        logic [7:0]  dscp_ecn;
        logic [15:0] total_length;
        logic [15:0] identification;
        logic [2:0]  flags;
        logic [12:0] frag_offset;
        logic [7:0]  ttl;
        logic [7:0]  protocol;
        logic [15:0] hdr_checksum;
        logic [31:0] src_ip;
        logic [31:0] dst_ip;
    } ipv4_hdr_t;

    // UDP header (8 bytes).
    typedef struct packed {
        logic [15:0] src_port;
        logic [15:0] dst_port;
        logic [15:0] length;
        logic [15:0] checksum;
    } udp_hdr_t;

    // -------------------------------------------------------------------------
    // Protocol constants
    // -------------------------------------------------------------------------
    localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
    localparam logic [7:0]  IP_PROTO_UDP   = 8'd17;

    // Destination UDP port the classifier routes to the market-data decoder.
    // PLACEHOLDER default — confirm against the target feed spec before tape-in.
    localparam logic [15:0] MARKET_DATA_PORT = 16'd12345;

endpackage : pkg_defines
