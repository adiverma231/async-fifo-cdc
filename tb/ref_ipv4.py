"""Python golden reference for the IPv4 parser.

Builds standard 20-byte IPv4 packets (with a correct or deliberately corrupted
header checksum) and computes the fields the parser should extract. Only IHL=5
headers are modeled; option-bearing / non-IPv4 / truncated cases are driven by
the test directly and asserted by the expected error flag.
"""

IP_PROTO_UDP = 17


def _ip_bytes(x):
    return bytes([(x >> 24) & 0xFF, (x >> 16) & 0xFF, (x >> 8) & 0xFF, x & 0xFF])


def ones_comp_sum(data):
    s = 0
    for i in range(0, len(data), 2):
        hi = data[i]
        lo = data[i + 1] if i + 1 < len(data) else 0
        s += (hi << 8) | lo
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return s


def compute_checksum(header):
    """Ones-complement checksum to store in the header (checksum field = 0)."""
    return (~ones_comp_sum(header)) & 0xFFFF


def build_packet(payload, src_ip=0xC0A80001, dst_ip=0xC0A80002,
                 protocol=IP_PROTO_UDP, ihl=5, version=4, ttl=64, ident=0,
                 corrupt_csum=False):
    payload = bytes(payload)
    total_len = 20 + len(payload)
    hdr = bytearray(20)
    hdr[0] = ((version & 0xF) << 4) | (ihl & 0xF)
    hdr[1] = 0
    hdr[2] = (total_len >> 8) & 0xFF
    hdr[3] = total_len & 0xFF
    hdr[4] = (ident >> 8) & 0xFF
    hdr[5] = ident & 0xFF
    hdr[6] = 0
    hdr[7] = 0
    hdr[8] = ttl & 0xFF
    hdr[9] = protocol & 0xFF
    hdr[10] = 0
    hdr[11] = 0
    hdr[12:16] = _ip_bytes(src_ip)
    hdr[16:20] = _ip_bytes(dst_ip)
    csum = compute_checksum(hdr)
    if corrupt_csum:
        csum ^= 0x0001
    hdr[10] = (csum >> 8) & 0xFF
    hdr[11] = csum & 0xFF
    return bytes(hdr) + payload


def expected(packet):
    """Fields + payload for a well-formed packet (used for valid-case scoreboard)."""
    packet = bytes(packet)
    return {
        "version": packet[0] >> 4,
        "ihl": packet[0] & 0xF,
        "total_length": (packet[2] << 8) | packet[3],
        "protocol": packet[9],
        "src_ip": int.from_bytes(packet[12:16], "big"),
        "dst_ip": int.from_bytes(packet[16:20], "big"),
        "payload": packet[20:],
    }
