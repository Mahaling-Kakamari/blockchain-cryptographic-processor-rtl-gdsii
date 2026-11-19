# Implementation Summary

## Synthesis

- Tool: Cadence Genus Synthesis Solution
- Top module: `blockchain`
- Cell count: 13,410
- Combinational/sequential cell area: 285,810.944
- Target clock: 667 MHz, 1.5 ns period
- Clock uncertainty: 50 ps
- Input/output delay: 300 ps
- Maximum fanout: 20

## Power

The synthesized implementation reports approximately:

- Total power: 0.163 W
- Internal power: 77.91%
- Switching power: 22.09%
- Leakage power: 0.01%

## Timing Status

The captured synthesis timing report shows a setup violation:

- Reported worst slack: approximately -2839 ps
- Capture/launch clock period: 1.5 ns
- Violating endpoint: `digest_out_reg[244]/D`

## Layout Status

Physical implementation outputs include:

- GDSII: `physical-design/blockchain.gds`
- Encoded design state: `physical-design/blockchain.enc`
- Post-layout Verilog: `physical-design/blockchain_pd.v`
- Max/min SDF and worst/best SPEF

The included DRC report contains Metal1 short violations that require correction before signoff.
