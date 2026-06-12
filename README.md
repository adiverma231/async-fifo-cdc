# async-fifo-cdc

## One-Liner
Designing a pipelined Ethernet packet parser with async FIFO CDC, targeting sub-10ns classification latency at 200+ MHz on Xilinx Artix-7.

### What I'm Building

```
RX PHY Clock (125 MHz)              Logic Clock (200 MHz)
       |                                    |
[Ethernet Parser] --> [Async FIFO CDC] --> [Packet Classifier] --> [Market Data Decoder] --> [Top-of-Book Register]
```

### RTL Module Breakdown

```
src/
  rtl/
    fifo/
      async_fifo.sv          -- Top wrapper, parameterized (DATA_WIDTH, ADDR_WIDTH)
      fifo_mem.sv            -- Dual-port BRAM inference
      sync_r2w.sv            -- 2-FF synchronizer, read ptr -> write domain
      sync_w2r.sv            -- 2-FF synchronizer, write ptr -> read domain
      rptr_empty.sv          -- Read pointer + gray conversion + empty flag
      wptr_full.sv           -- Write pointer + gray conversion + full flag

    parser/
      eth_frame_parser.sv    -- Preamble strip, MAC extract, EtherType, FCS
      ipv4_parser.sv         -- IP header extract, checksum validate
      udp_parser.sv          -- Port/length/payload extraction
      packet_classifier.sv   -- FSM: route by port/protocol to output channels

    app/
      market_data_decoder.sv -- Parse simplified ITCH-like messages
      top_of_book.sv         -- Track best bid/ask (register-based)

    top/
      system_top.sv          -- Full integration with CDC boundary
      pkg_defines.sv         -- Packed structs for headers, parameters

  tb/
    tb_async_fifo.sv         -- FIFO unit test (or cocotb equivalent)
    tb_parser.sv             -- Parser unit test with PCAP-derived vectors
    tb_system.sv             -- Integration test, end-to-end

  constraints/
    arty_a7.xdc             -- Pin/timing constraints (if targeting board)

  docs/
    block_diagram.png        -- Architecture diagram
    timing_report.pdf        -- Vivado timing summary
```
### Key Design Decisions (locked in)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | SystemVerilog | Self explanatory |
| FIFO pointer encoding | Gray code (Cummings style) | Only 1 bit transitions per cycle, safe for CDC |
| FIFO depth | Parameterized, power-of-2 | Gray code requires power-of-2 |
| Inter-stage interface | AXI-Stream (tvalid/tready/tdata/tlast) | Industry standard |
| Parser architecture | Pipelined, cut-through | Minimizes latency (start parsing before full frame arrives) |
| Target device | Xilinx Artix-7 (XC7A35T or XC7A100T) | Vivado is industry standard; Arty A7 has Ethernet PHY |
| Verification | cocotb (Python) + SVA assertions | cocotb for stimulus generation; SVA for formal-friendly properties |

## Target Metrics

| Metric | Target | Stretch |
|--------|--------|---------|
| FIFO throughput | 1 word/cycle, no bubbles | -- |
| Parser latency | < 8 cycles (< 40ns @ 200 MHz) | < 5 cycles |
| System Fmax | 200 MHz on Artix-7 | 250 MHz |
| Resource usage | < 5% of XC7A100T | < 2% |
| FIFO depth range | 16 to 4096 (parameterized) | -- |
| Data width range | 8 to 512 bits (parameterized) | -- |
| Verification coverage | > 95% line | + formal proof |
| Clock domains | 2 (RX 125 MHz, logic 200 MHz) | 3 (add TX) |
