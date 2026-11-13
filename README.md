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
[1] N. Ravindran and R. Mary Lourde, “An Optimum VLSI Design of a 16-Bit ALU,” 2015 International
Conference on Information and Communication Technology Research (ICTRC 2015), pp. 52-55.
DOI: 10.1109/ICTRC.2015.7156419.
[2] S. Santhanam and S. Rajendra Prasad, “Performance Comparison of 16-Bit ALU and 32-Bit ALU
Using Verilog,” 2025 3rd International Conference on Integrated Circuits and Communication
Systems (ICICACS). DOI: 10.1109/ICICACS65178.2025.10968047.
[3] A. Uniyal and V. Niranjan, “A new 16-bit ALU using variable stage adder and PTL mux,” 2017
International Conference on Computing, Communication and Automation (ICCCA), pp. 1374-1378.
DOI: 10.1109/CCAA.2017.8230050.
[4] S. Das and S. P. Khatri, “A Timing-Driven Approach to Synthesize Fast Barrel Shifters,” IEEE Trans.
Circuits and Systems II: Express Briefs, vol. 55, no. 1, pp. 31-35, 2008. DOI:
10.1109/TCSII.2007.908951.
[5] D. Chon, Y. Yang, H. Choi and W. Choi, “Hardware-Efficient Barrel Shifter Design Using
Customized Dynamic Logic Based MUX,” 2022 19th International SoC Design Conference
(ISOCC), pp. 59-60. DOI: 10.1109/ISOCC56007.2022.10031545.
[6] Y. Kim and L. S. Kim, “A low power carry select adder with reduced area,” Proc. 2001 IEEE
International Symposium on Circuits and Systems (ISCAS), vol. 4, pp. 218-221. DOI:
10.1109/ISCAS.2001.922211.
[7] C. Nagendra, M. J. Irwin and R. M. Owens, “Area-time-power tradeoffs in parallel adders,” IEEE
Trans. Circuits and Systems II: Analog and Digital Signal Processing, vol. 43, no. 10, pp. 689-702,
1996. DOI: 10.1109/82.539001.
[8] N. Banerjee, A. Raychowdhury, S. Bhunia, H. Mahmoodi and K. Roy, “Novel Low-Overhead
Operand Isolation Techniques for Low-Power Datapath Synthesis,” IEEE International Conference
on Computer Design (ICCD), 2005, pp. 206-214. DOI: 10.1109/ICCD.2005.80.
[9] V. K. Saini, S. Akhter and T. Chauhan, “Implementation, Test Pattern Generation, and Comparative
Analysis of Different Adder Circuits,” VLSI Design, 2016, Article 1260879. DOI:
10.1155/2016/1260879.
[10] B. Ramkumar and H. M. Kittur, “Low-Power and Area-Efficient Carry Select Adder,” IEEE Trans.
Very Large Scale Integration (VLSI) Systems, vol. 20, no. 2, pp. 371-375, 2012. DOI:
10.1109/TVLSI.2010.2101621.
[11] P. V. S. D. D. Mallikarjuna, “Design of 4-Bit ALU Implementation Using OpenLane (RTL to
GDSII),” PrimeMOS Research & Solutions, tutorial document, undated.

## Authors
Ayush Tiwari, Abeer Gupta. Guide: Dr. Chitrakant Sahu.

