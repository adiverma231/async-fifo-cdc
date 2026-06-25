"""cocotb test for axis_async_fifo: proves AXIS framing survives the CDC.

Streams randomly-sized packets (each terminated by tlast, with a random valid
tkeep on the final beat) through the AXIS async FIFO under write-side full
backpressure and read-side random tready backpressure, then asserts the exact
same sequence of (tdata, tkeep, tlast) beats is received in order on the far
clock domain. This directly validates the framing decision recorded in
pkg_defines: tlast/tkeep are carried alongside tdata across the clock crossing.

DUT defaults: TDATA_WIDTH=64, ADDR_WIDTH=5 (depth 32).
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

TDATA_WIDTH = 64
KEEP_WIDTH = TDATA_WIDTH // 8
DATA_MASK = (1 << TDATA_WIDTH) - 1

S_PERIOD_NS = 8                  # 125 MHz ingress
M_PERIOD_NS = 5                  # 200 MHz core

# Contiguous-from-LSB keep patterns for a final beat (1..8 valid bytes).
LAST_KEEPS = [0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F, 0xFF]


def start_clocks(dut):
    cocotb.start_soon(Clock(dut.s_aclk, S_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.m_aclk, M_PERIOD_NS, units="ns").start())


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tlast.value = 0
    dut.m_axis_tready.value = 0
    for _ in range(5):
        await RisingEdge(dut.s_aclk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.s_aclk)
    for _ in range(5):
        await RisingEdge(dut.m_aclk)


def make_beats(num_packets):
    """Return a list of (tdata, tkeep, tlast) beats spanning several packets."""
    beats = []
    for _ in range(num_packets):
        plen = random.randint(1, 6)
        for j in range(plen):
            last = (j == plen - 1)
            keep = random.choice(LAST_KEEPS) if last else 0xFF
            data = random.getrandbits(TDATA_WIDTH)
            beats.append((data, keep, int(last)))
    return beats


async def axis_send(dut, beats):
    for data, keep, last in beats:
        await FallingEdge(dut.s_aclk)
        dut.s_axis_tdata.value = data
        dut.s_axis_tkeep.value = keep
        dut.s_axis_tlast.value = last
        dut.s_axis_tvalid.value = 1
        # hold the beat until accepted (tready high at a rising edge)
        while True:
            await RisingEdge(dut.s_aclk)
            if int(dut.s_axis_tready.value):
                break
    await FallingEdge(dut.s_aclk)
    dut.s_axis_tvalid.value = 0


async def axis_recv(dut, n, out):
    while len(out) < n:
        await FallingEdge(dut.m_aclk)
        ready = random.randint(0, 1)
        dut.m_axis_tready.value = ready
        # sample the head word that will be consumed at the upcoming edge
        valid = int(dut.m_axis_tvalid.value)
        data = int(dut.m_axis_tdata.value) & DATA_MASK
        keep = int(dut.m_axis_tkeep.value)
        last = int(dut.m_axis_tlast.value)
        await RisingEdge(dut.m_aclk)
        if valid and ready:
            out.append((data, keep, last))


@cocotb.test()
async def test_axis_framing_preserved(dut):
    start_clocks(dut)
    await reset_dut(dut)

    beats = make_beats(num_packets=20)
    received = []

    sender = cocotb.start_soon(axis_send(dut, beats))
    receiver = cocotb.start_soon(axis_recv(dut, len(beats), received))
    await sender
    await receiver
    await Timer(1, units="ns")

    assert len(received) == len(beats), \
        f"beat count mismatch: sent {len(beats)} received {len(received)}"

    for idx, (exp, got) in enumerate(zip(beats, received)):
        assert exp == got, (
            f"beat {idx} mismatch across CDC:\n"
            f"  sent     data={exp[0]:#018x} keep={exp[1]:#04x} last={exp[2]}\n"
            f"  received data={got[0]:#018x} keep={got[1]:#04x} last={got[2]}"
        )
