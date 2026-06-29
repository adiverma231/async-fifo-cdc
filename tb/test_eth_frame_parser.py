"""cocotb tests for eth_frame_parser.

Ports the directed cases from the legacy SV testbench into the project-standard
cocotb flow and adds constrained-random traffic and a throughput check, to clear
the Stage 2 exit criterion:
  * correct field extraction on valid frames,
  * correct error flags on invalid (short) frames,
  * 8 bytes/cycle throughput (no bubbles in the payload output).

The parser starts at the destination MAC; preamble/SFD/FCS are handled upstream
by the MAC/PHY (see eth_frame_parser.sv).
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge

import ref_eth
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


def new_store():
    return {"count": 0, "errors": 0, "dst": None, "src": None, "etype": None}


async def header_monitor(dut, store):
    while True:
        await FallingEdge(dut.clk)
        if int(dut.hdr_valid.value):
            store["count"] += 1
            store["dst"] = int(dut.dst_mac.value)
            store["src"] = int(dut.src_mac.value)
            store["etype"] = int(dut.ether_type.value)
        if int(dut.frame_error.value):
            store["errors"] += 1


async def wait_until(dut, cond, timeout=3000):
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


async def check_valid(dut, src, sink, store, frame, name):
    exp = ref_eth.expected(frame)
    assert not exp["error"], f"{name}: test frame should be valid"
    sink.clear()
    store.update(count=0, errors=0)
    await src.send(frame)
    assert await wait_until(dut, lambda: store["count"] >= 1), f"{name}: no header seen"
    if len(exp["payload"]) > 0:
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), f"{name}: no payload seen"
    for _ in range(3):
        await RisingEdge(dut.clk)

    assert store["count"] == 1, f"{name}: header count = {store['count']}"
    assert store["errors"] == 0, f"{name}: unexpected error count = {store['errors']}"
    assert store["dst"] == exp["dst"], f"{name}: dst {store['dst']:012x} != {exp['dst']:012x}"
    assert store["src"] == exp["src"], f"{name}: src {store['src']:012x} != {exp['src']:012x}"
    assert store["etype"] == exp["etype"], f"{name}: etype {store['etype']:04x} != {exp['etype']:04x}"
    if len(exp["payload"]) > 0:
        got = sink.frames[0]
        assert got == exp["payload"], \
            f"{name}: payload {got.hex()} != {exp['payload'].hex()}"
    else:
        assert len(sink.frames) == 0, f"{name}: unexpected payload for empty frame"


@cocotb.test()
async def test_basic_frame(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        await check_valid(dut, src, sink, store, ref_eth.build_frame(list(range(0x80, 0x8A))),
                          "basic")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_two_byte_payload(dut):
    """Payload of 2 bytes lands in the header beat (keep[7:6] flush path)."""
    src, sink, store, tasks = await setup(dut)
    try:
        await check_valid(dut, src, sink, store, ref_eth.build_frame([0xDE, 0xAD]),
                          "two-byte payload")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_unaligned_last_word(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        await check_valid(dut, src, sink, store, ref_eth.build_frame(list(range(5))),
                          "unaligned last word")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_output_backpressure(dut):
    src, sink, store, tasks = await setup(dut, sink_bp=0.4)
    try:
        await check_valid(dut, src, sink, store,
                          ref_eth.build_frame([(0x80 + i) & 0xFF for i in range(17)]),
                          "output backpressure")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_header_backpressure(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        frame = ref_eth.build_frame(list(range(6)))
        exp = ref_eth.expected(frame)
        dut.hdr_ready.value = 0

        async def release():
            for _ in range(8):
                await RisingEdge(dut.clk)
            dut.hdr_ready.value = 1

        rel = cocotb.start_soon(release())
        await src.send(frame)
        await rel
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), "header bp: no payload"
        for _ in range(3):
            await RisingEdge(dut.clk)
        assert store["count"] == 1 and store["errors"] == 0
        assert store["dst"] == exp["dst"] and store["src"] == exp["src"]
        assert sink.frames[0] == exp["payload"]
    finally:
        teardown(tasks)


@cocotb.test()
async def test_short_frame_error(dut):
    src, sink, store, tasks = await setup(dut)
    try:
        await src.send(bytes([0xF0 + i for i in range(10)]))   # 10-byte runt
        assert await wait_until(dut, lambda: store["errors"] >= 1), "no frame_error"
        for _ in range(3):
            await RisingEdge(dut.clk)
        assert store["errors"] == 1, f"error count = {store['errors']}"
        assert store["count"] == 0, f"unexpected header for runt: {store['count']}"
        assert len(sink.frames) == 0, "runt produced payload"
    finally:
        teardown(tasks)


@cocotb.test()
async def test_random_frames(dut):
    src, sink, store, tasks = await setup(dut, src_bp=0.3, sink_bp=0.3)
    try:
        for n in range(40):
            payload = [random.randint(0, 255) for _ in range(random.randint(1, 64))]
            dst = bytes(random.randint(0, 255) for _ in range(6))
            srcm = bytes(random.randint(0, 255) for _ in range(6))
            etype = random.choice([0x0800, 0x86DD, 0x0806])
            frame = ref_eth.build_frame(payload, dst=dst, src=srcm, ethertype=etype)
            await check_valid(dut, src, sink, store, frame, f"random[{n}]")
    finally:
        teardown(tasks)


@cocotb.test()
async def test_throughput_no_bubbles(dut):
    """Full-rate input -> contiguous payload output (8 bytes/cycle, no bubbles)."""
    src, sink, store, tasks = await setup(dut)   # no backpressure either side
    try:
        frame = ref_eth.build_frame([(i * 7) & 0xFF for i in range(200)])
        sink.clear()
        await src.send(frame)
        assert await wait_until(dut, lambda: len(sink.frames) >= 1), "no payload"
        bc = sink.beat_cycles
        assert len(bc) >= 24, f"unexpectedly few output beats: {len(bc)}"
        assert bc == list(range(bc[0], bc[0] + len(bc))), \
            f"payload output had bubbles: cycles {bc}"
        assert sink.frames[0] == ref_eth.expected(frame)["payload"]
    finally:
        teardown(tasks)
