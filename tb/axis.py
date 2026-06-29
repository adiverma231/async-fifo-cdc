"""Reusable AXI-Stream BFM for the cocotb tests.

Factored from the inline drive/collect logic proven in test_axis_async_fifo.py.
Sampling discipline matches the rest of the suite: signals are driven on the
falling edge (so they are stable entering the rising edge) and transfers are
observed on the rising edge.

  AxisSource - drives a byte stream onto an AXIS slave port (s_axis_*).
  AxisSink   - accepts an AXIS master port (m_axis_*), reassembling payload
               bytes (honoring tkeep) into per-frame byte strings.

Both support random backpressure via a `backpressure` probability in [0, 1].
"""

import random

from cocotb.triggers import RisingEdge, FallingEdge


class AxisSource:
    def __init__(self, clk, tdata, tvalid, tready, tlast, tkeep=None,
                 byte_width=8, backpressure=0.0):
        self.clk = clk
        self.tdata = tdata
        self.tvalid = tvalid
        self.tready = tready
        self.tlast = tlast
        self.tkeep = tkeep
        self.bw = byte_width
        self.backpressure = backpressure
        self.tvalid.value = 0
        self.tdata.value = 0
        self.tlast.value = 0
        if self.tkeep is not None:
            self.tkeep.value = 0

    async def send(self, data):
        """Drive `data` (bytes/list of ints) as AXIS beats, last beat tlast=1."""
        beats = [data[i:i + self.bw] for i in range(0, len(data), self.bw)]
        for k, chunk in enumerate(beats):
            await FallingEdge(self.clk)
            while random.random() < self.backpressure:   # idle gap(s)
                self.tvalid.value = 0
                await FallingEdge(self.clk)
            word = 0
            keep = 0
            for j, b in enumerate(chunk):
                word |= (b & 0xFF) << (8 * j)
                keep |= (1 << j)
            self.tdata.value = word
            if self.tkeep is not None:
                self.tkeep.value = keep
            self.tlast.value = 1 if k == len(beats) - 1 else 0
            self.tvalid.value = 1
            while True:                                   # wait for handshake
                await RisingEdge(self.clk)
                if int(self.tready.value):
                    break
        await FallingEdge(self.clk)
        self.tvalid.value = 0
        self.tlast.value = 0


class AxisSink:
    def __init__(self, clk, tdata, tvalid, tready, tlast, tkeep=None,
                 byte_width=8, backpressure=0.0):
        self.clk = clk
        self.tdata = tdata
        self.tvalid = tvalid
        self.tready = tready
        self.tlast = tlast
        self.tkeep = tkeep
        self.bw = byte_width
        self.backpressure = backpressure
        self.tready.value = 1
        self.frames = []          # completed frames (bytes)
        self.beat_cycles = []     # cycle index of each accepted beat
        self._cur = bytearray()
        self._cycle = 0

    def clear(self):
        self.frames = []
        self.beat_cycles = []
        self._cur = bytearray()

    async def run(self):
        while True:
            await FallingEdge(self.clk)
            ready = 0 if random.random() < self.backpressure else 1
            self.tready.value = ready
            valid = int(self.tvalid.value)
            data = int(self.tdata.value)
            keep = int(self.tkeep.value) if self.tkeep is not None else (1 << self.bw) - 1
            last = int(self.tlast.value)
            await RisingEdge(self.clk)
            self._cycle += 1
            if valid and ready:
                for j in range(self.bw):
                    if (keep >> j) & 1:
                        self._cur.append((data >> (8 * j)) & 0xFF)
                self.beat_cycles.append(self._cycle)
                if last:
                    self.frames.append(bytes(self._cur))
                    self._cur = bytearray()
