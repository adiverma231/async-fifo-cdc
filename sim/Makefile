# =============================================================================
# cocotb + Verilator simulation flow (project-standard verification stack)
# -----------------------------------------------------------------------------
# Usage (from this sim/ directory):
#
#   make                                   # default: async_fifo CDC core test
#   make MODULE=test_async_fifo TOPLEVEL=async_fifo
#   make MODULE=test_axis_async_fifo TOPLEVEL=axis_async_fifo
#   make clean
#
# Requirements: Python 3, cocotb, cocotb-coverage, Verilator.
# Note: cocotb + Verilator is a POSIX flow; on Windows run it under WSL.
# =============================================================================

TOPLEVEL_LANG ?= verilog
SIM           ?= verilator

# Repo root = parent of this Makefile's directory.
ROOT := $(realpath $(dir $(lastword $(MAKEFILE_LIST)))/..)

# ----------------------------------------------------------------------------
# RTL sources. pkg_defines must come first; assertions are bound to async_fifo
# and compiled in so SVA fires during simulation (Verilator --assert).
# ----------------------------------------------------------------------------
VERILOG_SOURCES += $(ROOT)/src/rtl/top/pkg_defines.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/reset_sync.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/fifo_mem.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/sync_r2w.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/sync_w2r.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/wptr_full.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/rptr_empty.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/async_fifo.sv
VERILOG_SOURCES += $(ROOT)/src/rtl/fifo/axis_async_fifo.sv
VERILOG_SOURCES += $(ROOT)/src/tb/async_fifo_assertions.sv

# Test selection (override on the command line).
TOPLEVEL ?= async_fifo
MODULE   ?= test_async_fifo

# Python tests live in tb/.
export PYTHONPATH := $(ROOT)/tb:$(PYTHONPATH)

# Verilator: enable SVA assertions and dump waves.
EXTRA_ARGS   += --assert --trace
COMPILE_ARGS += -Wno-fatal

include $(shell cocotb-config --makefiles)/Makefile.sim
