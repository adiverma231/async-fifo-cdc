# async-fifo-cdc

## One-Liner
Designing a pipelined Ethernet packet parser with async FIFO CDC, targeting sub-10ns classification latency at 200+ MHz on Xilinx Artix-7.

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
