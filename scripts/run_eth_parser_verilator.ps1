$ErrorActionPreference = "Stop"

verilator -f sim/eth_parser_verilator.f
.\obj_dir\Vtb_eth_frame_parser.exe