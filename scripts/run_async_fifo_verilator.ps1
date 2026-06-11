$ErrorActionPreference = "Stop"

verilator -f sim/async_fifo_verilator.f
.\obj_dir\Vtb_async_fifo.exe
