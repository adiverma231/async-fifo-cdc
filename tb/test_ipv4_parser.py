"""cocotb tests for ipv4_parser.

Clears the Stage 3 (IPv4) exit criterion: field extraction, header-checksum
validation (good + corrupted), error flags for options / bad-version / truncated
(packet dropped), correctly realigned L4 payload, and 8 bytes/cycle throughput.

Standalone: the parser is fed synthetic IPv4-over-AXIS packets (eth->IPv4
chaining is a later integration step).
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

import ref_ipv4
from axis import AxisSource, AxisSink

CLK_NS = 10


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    dut.m_axis_tready.value = 1
    dut.hdr_ready.value = 1
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)


ERR_KEYS = ["err_version", "err_options", "err_checksum", "err_truncated"]


def new_store():
    s = {"count": 0, "version": None, "ihl": None, "total_length": None,
         "protocol": None, "src_ip": None, "dst_ip": None}
    for k in ERR_KEYS:
        s[k] = 0
    return s


def reset_store(store):
    store["count"] = 0
    for k in ERR_KEYS:
        store[k] = 0


async def header_monitor(dut, store):
    while True:
        await FallingEdge(dut.clk)
        if int(dut.hdr_valid.value):
            store["count"] += 1
            store["version"] = int(dut.version.value)
            store["ihl"] = int(dut.ihl.value)
            store["total_length"] = int(dut.total_length.value)
            store["protocol"] = int(dut.protocol.value)
            store["src_ip"] = int(dut.src_ip.value)
            store["dst_ip"] = int(dut.dst_ip.value)
        for k in ERR_KEYS:
            if int(getattr(dut, k).value):
                store[k] += 1


async def wait_until(dut, cond, timeout=4000):
    for _ in range(timeout):
        if cond():
            return True
        await RisingEdge(dut.clk)
    return False


async def setup(dut, src_bp=0.0, sink_bp=0.0):
    clk = cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await reset_dut(dut)
    src = AxisSource(dut.clk, dut.s_axis_tdata, dut.s_axis_tvalid, dut.s_axis_tready,
                     dut.s_axis_tlast, dut.s_axis_tkeep, backpressure=src_bp)
    sink = AxisSink(dut.clk, dut.m_axis_tdata, dut.m_axis_tvalid, dut.m_axis_tready,
                    dut.m_axis_tlast, dut.m_axis_tkeep, backpressure=sink_bp)
    store = new_store()
    tasks = [clk,
             cocotb.start_soon(sink.run()),
             cocotb.start_soon(header_monitor(dut, store))]
    return src, sink, store, tasks


def teardown(tasks):
    for t in tasks:
        t.kill()


async def check_valid(dut, src, sink, store, packet, name):
    exp = ref_ipv4.expected(packet)
    reset_store(store)
    sink.clear()
    await src.send(packet)
    assert await wait_until(dut, lambda: store["count"] >= 1), f"{name}: no header"
    if len(exp["payload"]) > 0:
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), f"{name}: no payload"
    for _ in range(3):
        await RisingEdge(dut.clk)

    assert store["count"] == 1, f"{name}: header count {store['count']}"
    for k in ERR_KEYS:
        assert store[k] == 0, f"{name}: unexpected {k}"
    assert store["version"] == exp["version"], f"{name}: version"
    assert store["ihl"] == exp["ihl"], f"{name}: ihl"
    assert store["total_length"] == exp["total_length"], f"{name}: total_length"
    assert store["protocol"] == exp["protocol"], f"{name}: protocol"
    assert store["src_ip"] == exp["src_ip"], f"{name}: src_ip {store['src_ip']:08x} != {exp['src_ip']:08x}"
    assert store["dst_ip"] == exp["dst_ip"], f"{name}: dst_ip {store['dst_ip']:08x} != {exp['dst_ip']:08x}"
    if len(exp["payload"]) > 0:
        assert sink.frames[0] == exp["payload"], \
            f"{name}: payload {sink.frames[0].hex()} != {exp['payload'].hex()}"
    else:
        assert len(sink.frames) == 0, f"{name}: unexpected payload"


async def check_error(dut, src, sink, store, packet, errkey, name):
    reset_store(store)
    sink.clear()
    await src.send(packet)
    assert await wait_until(dut, lambda: store[errkey] >= 1), f"{name}: no {errkey}"
    for _ in range(4):
        await RisingEdge(dut.clk)
    assert store[errkey] == 1, f"{name}: {errkey} count {store[errkey]}"
    assert store["count"] == 0, f"{name}: produced a header on a rejected packet"
    assert len(sink.frames) == 0, f"{name}: produced payload on a rejected packet"
    for k in ERR_KEYS:
        if k != errkey:
            assert store[k] == 0, f"{name}: unexpected {k}"


@cocotb.test()
async def test_basic_packet(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        pkt = ref_ipv4.build_packet([(0x80 + i) & 0xFF for i in range(10)])
        await check_valid(dut, src, sink, store, pkt, "basic")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_realignment_lengths(dut):
    """Payload lengths spanning the 4-byte carry / flush boundaries."""
    src, sink, store, tasks = await setup(dut)
    try:
        for n in [0, 1, 3, 4, 5, 6, 8, 9, 12, 16, 17, 31, 64]:
            pkt = ref_ipv4.build_packet([(0x40 + i) & 0xFF for i in range(n)],
                                        src_ip=0x0A000001 + n, dst_ip=0x0A0000FF)
            await check_valid(dut, src, sink, store, pkt, f"len{n}")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_bad_checksum(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        pkt = ref_ipv4.build_packet([0xAA] * 10, corrupt_csum=True)
        await check_error(dut, src, sink, store, pkt, "err_checksum", "bad checksum")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_bad_version(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        pkt = ref_ipv4.build_packet([0xBB] * 10, version=6)
        await check_error(dut, src, sink, store, pkt, "err_version", "bad version")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_options_rejected(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        pkt = ref_ipv4.build_packet([0xCC] * 10, ihl=6)
        await check_error(dut, src, sink, store, pkt, "err_options", "options")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_truncated(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        # valid header prefix cut short at 16 bytes -> tlast during HDR1
        pkt = ref_ipv4.build_packet([])[:16]
        await check_error(dut, src, sink, store, pkt, "err_truncated", "truncated@16")
        # cut at 18 bytes -> tlast during HDR2 (header tail incomplete)
        pkt2 = ref_ipv4.build_packet([])[:18]
        await check_error(dut, src, sink, store, pkt2, "err_truncated", "truncated@18")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_output_backpressure(dut):
    src, sink, store, tasks = await setup(dut, sink_bp=0.4)
    try:
        pkt = ref_ipv4.build_packet([(0x10 + i) & 0xFF for i in range(33)])
        await check_valid(dut, src, sink, store, pkt, "output bp")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_header_backpressure(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        pkt = ref_ipv4.build_packet([(0x20 + i) & 0xFF for i in range(12)])
        exp = ref_ipv4.expected(pkt)
        dut.hdr_ready.value = 0

        async def release():
            for _ in range(8):
                await RisingEdge(dut.clk)
            dut.hdr_ready.value = 1

        rel = cocotb.start_soon(release())
        await src.send(pkt)
        await rel
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), "header bp: no payload"
        for _ in range(3):
            await RisingEdge(dut.clk)
        assert store["count"] == 1 and store["dst_ip"] == exp["dst_ip"]
        assert sink.frames[0] == exp["payload"]
    finally:
        teardown(tasks)


@cocotb.test()
async def test_random_packets(dut):
    src, sink, store, tasks = await setup(dut, src_bp=0.3, sink_bp=0.3)
    try:
        for n in range(40):
            payload = [random.randint(0, 255) for _ in range(random.randint(0, 60))]
            pkt = ref_ipv4.build_packet(
                payload,
                src_ip=random.getrandbits(32),
                dst_ip=random.getrandbits(32),
                protocol=random.choice([ref_ipv4.IP_PROTO_UDP, 6, 1]),
            )
            await check_valid(dut, src, sink, store, pkt, f"random[{n}]")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_throughput_no_bubbles(dut):
    src, sink, store, tasks = await setup(dut)   # no backpressure
    try:
        pkt = ref_ipv4.build_packet([(i * 5) & 0xFF for i in range(240)])
        sink.clear()
        await src.send(pkt)
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), "no payload"
        bc = sink.beat_cycles
        assert len(bc) >= 28, f"too few output beats: {len(bc)}"
        assert bc == list(range(bc[0], bc[0] + len(bc))), f"payload had bubbles: {bc}"
        assert sink.frames[0] == ref_ipv4.expected(pkt)["payload"]
    finally:
        teardown(tasks)
