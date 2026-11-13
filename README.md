# 16-bit ALU: RTL to GDSII on SKY130A

A registered 16-bit ALU (8 operations, flags Z/N/C/V) implemented three ways with
OpenLane 2 on the SkyWater SKY130A PDK (sky130_fd_sc_hd), then compared on delay,
area and power. Semester project (Project-I), Dept. of Electronics & Communication,
NIT Raipur.

## Designs

| Design | Goal | Key architecture | Result |
|---|---|---|---|
| A: Delay | Shortest clock | Grouped CLA, one-hot two-level AND-OR shifters, early zero flags | Timing met at 6.5 ns, +0.087 ns slack, 9 corners |
| B: Area + power | Smallest, lowest power | Shared RCA, shared bidirectional shifter, integrated shift-carry | 4,299.12 µm², 0.331 mW at 20 ns |
| C: Hybrid | Balanced | 8-bit RCA + 8-bit carry-increment, shared rotator and P/G | Timing met at 8.5 ns, 4,863 µm² |

### Three-way comparison at 20 ns

| Metric | B | A | C |
|---|---|---|---|
| Cell area (µm²) | 4,299.12 | 6,293.54 | 4,878.43 |
| Est. power (mW) | 0.331 | 0.553 | 0.476 |
| STA path proxy (ns) | 11.32 | 6.34 | 8.31 |

All numbers are OpenLane 2 / OpenROAD tool estimates (vectorless power), not silicon
measurements. DRC and LVS are clean for all three final runs.

## ALU operations
ADD, SUB, AND, OR, XOR, NOT, SLL, SRL (3-bit opcode). Flags: Z, N, C, V.

## Repository layout
(see tree below)

## Tools
Verilog HDL, Vivado XSIM / Icarus Verilog, Yosys + ABC, OpenLane 2, OpenROAD,
Magic, KLayout, Netgen, SKY130A PDK.

## How to run

Simulation:
```bash
iverilog -g2012 -o sim rtl/delay_opt/*.v tb/tb_alu16.v && vvp sim
```

Physical flow (OpenLane 2 installed):
```bash
cd openlane/delay_opt
openlane config.json
```
Outputs appear under `runs/`. Tight-clock runs use the config in `openlane/<design>/`.

## Verification
Self-checking testbench, 13,375 test cases, plus a 150,000-cycle random stress test
(0 mismatches). RTL-level only; no gate-level simulation.

## Report and slides
See `docs/` for the project report and presentation.

## References
(List the 11 papers from the report.)

## Authors
Ayush Tiwari, Abeer Gupta. Guide: Dr. Chitrakant Sahu.

## License
MIT (code). Report and slides: all rights reserved / CC BY 4.0 (your choice).
