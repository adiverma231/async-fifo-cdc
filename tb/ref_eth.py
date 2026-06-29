"""Python golden reference for the Ethernet frame parser.

The parser starts at the destination MAC (preamble/SFD/FCS are handled by the
MAC/PHY) and emits the 14-byte Ethernet header's payload, exposing dst/src MAC
and EtherType on a sideband.

Error model (matches eth_frame_parser.sv):
  * The first 64-bit beat must be a full 8 bytes and must not be the last beat
    (ST_IDLE rejects a short or single-beat frame).
  * The second beat must carry at least 6 bytes (bytes 8..13) so the header
    completes (ST_HEADER1 rejects an incomplete header).
  => any frame of 13 bytes or fewer is flagged as an error; 14+ is valid
     (14 == header only, empty payload).
"""

ETH_HDR_LEN = 14
DEFAULT_DST = bytes([0x00, 0x11, 0x22, 0x33, 0x44, 0x55])
DEFAULT_SRC = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
DEFAULT_ETYPE = 0x0800


def build_frame(payload, dst=DEFAULT_DST, src=DEFAULT_SRC, ethertype=DEFAULT_ETYPE):
    """Assemble a frame (bytes): dst MAC | src MAC | EtherType | payload."""
    return (bytes(dst) + bytes(src)
            + bytes([(ethertype >> 8) & 0xFF, ethertype & 0xFF])
            + bytes(payload))


def expected(frame):
    """Return the expected parser result for a frame (list/bytes of ints)."""
    frame = bytes(frame)
    if len(frame) <= ETH_HDR_LEN - 1:          # <= 13 bytes -> error
        return {"error": True}
    return {
        "error": False,
        "dst": int.from_bytes(frame[0:6], "big"),
        "src": int.from_bytes(frame[6:12], "big"),
        "etype": int.from_bytes(frame[12:14], "big"),
        "payload": frame[14:],
    }
