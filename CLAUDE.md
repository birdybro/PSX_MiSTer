# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PSX_MiSTer is a PlayStation 1 FPGA core for the MiSTer platform, targeting the Cyclone V FPGA. The design is primarily written in VHDL (2008 standard) with SystemVerilog for the top-level MiSTer integration and memory controllers.

## Build System

This project uses **Intel Quartus 17.0.2** — there is no Makefile.

- **Project files:** `PSX.qpf` (standard) and `PSX_DualSDRAM.qpf` (dual SDRAM variant)
- **Settings:** `PSX.qsf` / `PSX_DualSDRAM.qsf`
- **Timing constraints:** `PSX.sdc`
- **File lists:** `files.qip`, `rtl/psx.qip`, `rtl/mem.qip`
- **Build output:** RBF (Raw Bitstream File) placed in `releases/`
- **Top-level entity:** `sys_top` (defined in `sys/sys_top.v`)
- **Verilog defines:** `MISTER_FB=1`, `MISTER_DOWNSCALE_NN=1`, `MISTER_DISABLE_ALSA=1`

To build: open `PSX.qpf` in Quartus and run compilation, or use Quartus command-line tools (`quartus_sh --flow compile PSX`).

## Architecture

### Module Hierarchy

```
PSX.sv (emu module — MiSTer HPS interface, OSD, video/audio output)
  └─ psx_mister.vhd (MiSTer-specific wrapper: memory controllers, I/O routing)
      └─ psx_top.vhd (Core PSX system — instantiates all subsystems)
          ├─ cpu.vhd          — MIPS R3000A CPU
          ├─ datacache.vhd    — CPU data/instruction cache
          ├─ gte.vhd          — Geometry Transform Engine (coprocessor 2)
          ├─ gpu.vhd          — Graphics Processing Unit
          │   ├─ gpu_poly.vhd, gpu_line.vhd, gpu_rect.vhd — primitives
          │   ├─ gpu_pixelpipeline.vhd — pixel rendering
          │   ├─ gpu_videoout.vhd / gpu_videoout_async.vhd — video output
          │   └─ gpu_cpu2vram.vhd, gpu_vram2cpu.vhd, gpu_vram2vram.vhd — transfers
          ├─ spu.vhd          — Sound Processing Unit
          ├─ cd_top.vhd       — CD-ROM controller
          ├─ dma.vhd          — DMA controller (7 channels)
          ├─ memorymux.vhd    — Memory bus arbitration
          ├─ joypad.vhd       — Controller/pad interface
          ├─ mdec.vhd         — Motion Decoder (MPEG-1 video)
          ├─ timer.vhd        — Hardware timers
          ├─ irq.vhd          — Interrupt controller
          ├─ sio.vhd          — Serial I/O
          └─ savestates.vhd   — Save state system
```

### Key Directories

- **`rtl/`** — All core VHDL/SV design files (~61 VHDL files, ~35K lines total)
- **`sys/`** — MiSTer framework files (shared across MiSTer cores, generally not modified)
- **`sim/`** — Simulation testbenches, organized by subsystem (`sim/cd/`, `sim/gpu/`, `sim/gte/`, `sim/mdec/`, `sim/pad/`, `sim/spu/`, `sim/system/`)
- **`releases/`** — Pre-compiled RBF bitstream files
- **`memcard/`** — Empty memory card template

### Clock Domains

- **clk_1x** — PSX main clock (~33.87 MHz, derived from 50 MHz)
- **clk_2x / clk_3x** — 2x and 3x multiples for pipeline stages
- **clk_vid** — Video clock (PAL/NTSC dependent, configured via PLL2)
- **CLK_AUDIO** — 24.576 MHz audio clock

Cross-domain paths are managed via false path constraints in `PSX.sdc`.

### Memory Architecture

- **SDRAM** — Main PSX RAM (16-bit bus, managed by `sdram.sv`)
- **DDR3/DDRAM** — Higher bandwidth path for framebuffer, save states, CD data (`ddram.sv`, 64-bit bus)
- **Dual SDRAM variant** — `PSX_DualSDRAM.qsf` for MiSTer boards with two SDRAM modules

### Package Files

VHDL packages define shared types and constants:
- `pGPU.vhd` — GPU types and constants
- `pGTE.vhd` — GTE types and constants
- `pJoypad.vhd` — Joypad types
- `export.vhd` — Debug export definitions

## Simulation

Each subsystem has its own testbench in `sim/<subsystem>/src/tb/tb.vhd`. The system-level testbench (`sim/system/`) includes RAM models (`sdram_model.vhd`, `ddrram_model.vhd`), a test interpreter (`tb_interpreter.vhd`), and a framebuffer model.

## Key Design Notes

- The top-level `PSX.sv` handles all MiSTer-specific integration: HPS I/O, OSD menu, video scaling, audio mixing, and SDRAM/DDR3 arbitration.
- `psx_mister.vhd` bridges between MiSTer I/O and the core, handling memory controller instantiation and I/O signal routing.
- `psx_top.vhd` is the platform-independent PSX implementation — all subsystem instantiation and bus interconnect lives here.
- The `sys/` directory is part of the MiSTer framework and is shared across cores. Avoid modifying these files unless necessary.
