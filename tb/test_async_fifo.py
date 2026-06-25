"""cocotb unit test for the async_fifo CDC core.

Ports the sequencing proven by the legacy src/tb/tb_async_fifo.sv into the
project-standard cocotb flow:
  * directed fill/drain test exercising full / empty / almost_* flags against
    the Python reference model (ref_model.FifoModel);
  * constrained-random asynchronous traffic with a shared, order-preserving
    scoreboard asserting zero data loss and correct ordering, swept across
    several asynchronous clock ratios (>10k transactions total) to satisfy the
    Stage 1 exit criterion.

Sampling discipline mirrors the SV testbench: status flags (full/empty) are
registered and only change on their own posedge, so we sample them on the
FALLING edge (the value entering the next posedge) to decide acceptance, then
commit on the RISING edge. Read data is registered and settles to the popped
head word just after the rising edge, so it is sampled post-edge.

NOTE: constants below track the async_fifo.sv parameter DEFAULTS. If the DUT is
elaborated with overridden parameters, update these to match.
"""

from collections import deque
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

from ref_model import FifoModel

# --- must track async_fifo.sv defaults ---
DATA_WIDTH = 32
ADDR_WIDTH = 4
DEPTH = 1 << ADDR_WIDTH          # 16
AFULL_THRES = 12
AEMPTY_THRES = 4
DATA_MASK = (1 << DATA_WIDTH) - 1


class ClockGen:
    """Free-running clock with an adjustable half-period (ns).

    Lets one test sweep several asynchronous clock ratios on the same signal
    without restarting cocotb. Drive with cocotb.start_soon(gen.run()) and stop
    the returned task with .kill().
    """

    def __init__(self, sig, half_ns):
        self.sig = sig
        self.half = half_ns
        self.sig.value = 0

    async def run(self):
        while True:
            await Timer(self.half, units="ns")
            self.sig.value = 0 if int(self.sig.value) else 1


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0
    for _ in range(5):
        await RisingEdge(dut.wr_clk)
    dut.rst_n.value = 1
    for _ in range(5):
        await RisingEdge(dut.wr_clk)
    for _ in range(5):
        await RisingEdge(dut.rd_clk)


async def write_word(dut, value):
    """Single write; returns True if it was accepted (FIFO not full)."""
    await FallingEdge(dut.wr_clk)
    was_full = int(dut.full.value)
    dut.wr_en.value = 1
    dut.wr_data.value = value & DATA_MASK
    await RisingEdge(dut.wr_clk)
    dut.wr_en.value = 0
    await Timer(1, units="ns")
    return not was_full


async def read_word(dut):
    """Single read; returns (accepted, data)."""
    await FallingEdge(dut.rd_clk)
    was_empty = int(dut.empty.value)
    dut.rd_en.value = 1
    await RisingEdge(dut.rd_clk)
    dut.rd_en.value = 0
    await Timer(1, units="ns")
    data = int(dut.rd_data.value) & DATA_MASK
    return (not was_empty), data


async def run_random_traffic(dut, total):
    """Concurrent randomized write/read with an order-preserving scoreboard."""
    scoreboard = deque()
    errors = []

    async def wr_proc():
        sent = 0
        while sent < total:
            await FallingEdge(dut.wr_clk)
            do_it = random.randint(0, 2) != 0
            was_full = int(dut.full.value)
            val = random.getrandbits(DATA_WIDTH)
            if do_it and not was_full:
                dut.wr_data.value = val
                dut.wr_en.value = 1
            else:
                dut.wr_en.value = 0
            await RisingEdge(dut.wr_clk)
            if do_it and not was_full:
                scoreboard.append(val)
                sent += 1
        await FallingEdge(dut.wr_clk)
        dut.wr_en.value = 0

    async def rd_proc():
        got = 0
        while got < total:
            await FallingEdge(dut.rd_clk)
            do_it = random.randint(0, 2) != 0
            was_empty = int(dut.empty.value)
            dut.rd_en.value = 1 if do_it else 0
            await RisingEdge(dut.rd_clk)
            await Timer(1, units="ns")
            if do_it and not was_empty:
                if not scoreboard:
                    errors.append(f"read {got}: FIFO produced data before scoreboard had any")
                else:
                    exp = scoreboard.popleft()
                    act = int(dut.rd_data.value) & DATA_MASK
                    if act != exp:
                        errors.append(f"read {got}: expected {exp:#x} got {act:#x}")
                got += 1
        await FallingEdge(dut.rd_clk)
        dut.rd_en.value = 0

    w = cocotb.start_soon(wr_proc())
    r = cocotb.start_soon(rd_proc())
    await w
    await r
    assert not errors, "data integrity errors:\n" + "\n".join(errors[:20])


@cocotb.test()
async def test_fill_drain(dut):
    """Directed fill to full and drain to empty, checking status flags."""
    wr = cocotb.start_soon(ClockGen(dut.wr_clk, 4).run())   # 8 ns / 125 MHz
    rd = cocotb.start_soon(ClockGen(dut.rd_clk, 3).run())   # 6 ns
    try:
        await reset_dut(dut)
        model = FifoModel(DEPTH, AFULL_THRES, AEMPTY_THRES)

        # reset state
        assert int(dut.empty.value) == 1, "empty must assert after reset"
        assert int(dut.almost_empty.value) == 1, "almost_empty must assert after reset"
        assert int(dut.full.value) == 0, "full must be low after reset"
        assert int(dut.almost_full.value) == 0, "almost_full must be low after reset"

        # fill (no concurrent reads -> almost_full is exact)
        for i in range(DEPTH):
            accepted = await write_word(dut, i)
            assert accepted, f"write {i} unexpectedly rejected during fill"
            model.push(i & DATA_MASK)
            assert int(dut.almost_full.value) == int(model.is_almost_full()), \
                f"almost_full mismatch at count={model.count}"

        assert int(dut.full.value) == 1, "full must assert after DEPTH writes"

        # overflow write must be rejected and must not corrupt contents
        accepted = await write_word(dut, 0xABCD)
        assert not accepted, "overflow write was accepted while full"

        # let the (now stable) write pointer propagate to the read domain
        for _ in range(4):
            await RisingEdge(dut.rd_clk)

        # drain (no concurrent writes -> almost_empty is exact)
        for i in range(DEPTH):
            accepted, data = await read_word(dut)
            assert accepted, f"read {i} unexpectedly rejected during drain"
            expected = model.pop()
            assert data == expected, f"read {i}: expected {expected:#x} got {data:#x}"
            assert int(dut.almost_empty.value) == int(model.is_almost_empty()), \
                f"almost_empty mismatch at count={model.count}"

        assert int(dut.empty.value) == 1, "empty must assert after draining"
        assert model.count == 0, "model not drained"
    finally:
        wr.kill()
        rd.kill()


@cocotb.test()
async def test_random_async_ratios(dut):
    """Randomized traffic swept across several asynchronous clock ratios."""
    # (wr_half_ns, rd_half_ns) -- all asynchronous, mostly coprime to avoid
    # trivial edge alignment. ~2200 transactions each -> >10k total.
    ratios = [(4, 3), (3, 4), (5, 2), (2, 5), (7, 4)]
    per_ratio = 2200

    wr = ClockGen(dut.wr_clk, ratios[0][0])
    rd = ClockGen(dut.rd_clk, ratios[0][1])
    wr_task = cocotb.start_soon(wr.run())
    rd_task = cocotb.start_soon(rd.run())
    try:
        for wr_half, rd_half in ratios:
            wr.half = wr_half
            rd.half = rd_half
            dut._log.info(f"ratio wr_half={wr_half}ns rd_half={rd_half}ns, {per_ratio} transactions")
            await reset_dut(dut)
            await run_random_traffic(dut, per_ratio)
    finally:
        wr_task.kill()
        rd_task.kill()
