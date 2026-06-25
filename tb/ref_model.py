"""Python golden reference for the async-FIFO scoreboard.

A plain in-order queue model with occupancy-derived status flags. The cocotb
tests push every accepted write and pop on every accepted read, comparing the
DUT's read data and status flags against this model. The model is intentionally
clock-agnostic: it captures *ordering and occupancy* invariants, which is what
a correct CDC FIFO must preserve regardless of the clock relationship.
"""

from collections import deque


class FifoModel:
    """Reference model for async_fifo / axis_async_fifo.

    Parameters
    ----------
    depth : int
        2 ** ADDR_WIDTH.
    afull_thres : int
        Occupancy at/above which almost_full is expected.
    aempty_thres : int
        Occupancy at/below which almost_empty is expected.
    """

    def __init__(self, depth, afull_thres=None, aempty_thres=None):
        self.depth = depth
        self.afull_thres = depth - 2 if afull_thres is None else afull_thres
        self.aempty_thres = 2 if aempty_thres is None else aempty_thres
        self.q = deque()

    # -- occupancy -----------------------------------------------------------
    @property
    def count(self):
        return len(self.q)

    def is_full(self):
        return self.count >= self.depth

    def is_empty(self):
        return self.count == 0

    def is_almost_full(self):
        return self.count >= self.afull_thres

    def is_almost_empty(self):
        return self.count <= self.aempty_thres

    # -- mutation ------------------------------------------------------------
    def push(self, value):
        """Model an accepted write. Returns False if it would overflow."""
        if self.is_full():
            return False
        self.q.append(value)
        return True

    def pop(self):
        """Model an accepted read. Returns the expected value (FIFO order)."""
        if self.is_empty():
            raise AssertionError("scoreboard underflow: read with empty model")
        return self.q.popleft()

    def peek(self):
        return self.q[0] if self.q else None
