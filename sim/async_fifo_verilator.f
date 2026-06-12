--sv
--timing
--assert
--binary
--top-module tb_async_fifo
-Wno-fatal
src/rtl/fifo/reset_sync.sv
src/rtl/fifo/fifo_mem.sv
src/rtl/fifo/sync_r2w.sv
src/rtl/fifo/sync_w2r.sv
src/rtl/fifo/wptr_full.sv
src/rtl/fifo/rptr_empty.sv
src/rtl/fifo/async_fifo.sv
src/tb/async_fifo_assertions.sv
src/tb/tb_async_fifo.sv
