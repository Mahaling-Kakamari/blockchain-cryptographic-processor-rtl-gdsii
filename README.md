# Blockchain Cryptographic Processor: RTL to GDSII

This project implements a SHA-256 cryptographic processor in Verilog and documents its synthesis and physical-design flow.

## Overview

The RTL is a flat, single-module hardware accelerator for hashing one 512-bit, pre-padded message block. It performs one SHA-256 round per clock cycle and produces a 256-bit digest.

## Features

- Verilog RTL for a SHA-256 accelerator
- Synchronous reset and registered inputs/outputs
- 64-cycle hash computation
- 512-bit padded input block
- 256-bit digest output
- Cadence Genus synthesis scripts and constraints
- Cadence Innovus physical-design outputs
- GDSII, SDF, SPEF, and timing/power/area reports

## Repository Structure

```text
.
|-- rtl/                    # RTL implementations
|-- testbench/              # SHA-256 functional testbench
|-- synthesis/              # Genus synthesis script, netlist, and SDC
|-- physical-design/        # GDSII, DEF/ENC, SDF, SPEF, and placed netlist
|-- reports/                # Area, timing, power, DRC, and connectivity reports
|-- images/                 # Layout, routing, timing, and verification captures
`-- docs/results.md         # Concise implementation and signoff summary
```

## Flow

1. **RTL:** Implement and verify the SHA-256 datapath and control FSM.
2. **Synthesis:** Elaborate and map the design with Cadence Genus.
3. **Floorplanning:** Place and route the synthesized netlist with Cadence Innovus.
4. **Analysis:** Extract timing/power information and generate design-rule reports.
5. **Signoff:** Review GDSII and final report outputs.

## Verification

The testbench in `testbench/tb_sha256_single.v` applies `"abc"` and compares the result with the standard SHA-256 digest:

```text
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

## Status

This repository includes engineering outputs at intermediate signoff stages. The included timing and DRC reports should be reviewed before calling the design tapeout-ready. See [docs/results.md](docs/results.md).

