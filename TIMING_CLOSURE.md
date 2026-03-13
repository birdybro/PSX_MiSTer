# Timing Closure Analysis — PSX_MiSTer

This document identifies opportunities to improve timing closure on the Cyclone V FPGA. The design is resource-constrained (100% BRAM, 100% DSP, 80%+ logic utilization), which limits fitter flexibility and makes timing closure unreliable.

Nothing in `/sys/` should be modified — it is shared MiSTer framework code.

---

## Changes Applied

### QSF Fitter Settings

| Setting | Before | After |
|---------|--------|-------|
| `FITTER_EFFORT` | `STANDARD FIT` | `AGGRESSIVE FIT` |
| `PLACEMENT_EFFORT_MULTIPLIER` | `1.0` | `1.5` |
| `ALM_REGISTER_PACKING_EFFORT` | `LOW` | `MEDIUM` |
| `ROUTER_TIMING_OPTIMIZATION_LEVEL` | (default) | `MAXIMUM` |
| `ROUTER_EFFORT_MULTIPLIER` | (default) | `3.0` |
| `FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION` | (default) | `ALWAYS` |
| `OPTIMIZE_MULTI_CORNER_TIMING` | (default) | `ON` |
| `SYNTH_TIMING_DRIVEN_SYNTHESIS` | (default) | `ON` |
| `PHYSICAL_SYNTHESIS_EFFORT` | (default) | `EXTRA` |

Trade-off: significantly longer compile times (~2-3x) but better timing closure probability at 80%+ utilization. Try different `SEED` values during development to escape local minima.

### SDC Constraints (PSX.sdc)

1. **Completed PLL2 false path coverage** — The original SDC was missing clk_3x (general[2]) ↔ clk_vid false paths in both directions. Since PLL2 is not included in the sys_top.sdc exclusive clock groups, Quartus was trying to time paths between the 101.6 MHz SDRAM clock and the async video clock. Also added missing FPGA_CLK2_50/CLK3_50 reverse paths.

2. **False paths for quasi-static CDC signals** — `video_isPal`, `fast_forward`, and `status[*]` crossing from clk_1x to clk_vid. These only change on OSD interaction or region detection.

3. **Multicycle paths for save state broadcast bus** — SS_DataWrite (32-bit), SS_Adr (19-bit), SS_wren, and SS_rden are generated in the clk2x process of savestates.vhd and broadcast to 14+ modules. The clk2xIndex handshake ensures data is stable for 2 clk2x cycles when sampled. Relaxing to 2 setup cycles gives the fitter room to route these high fan-out nets.

### RTL Changes

1. **Restructured memorymux 9-way OR as balanced tree** — The `dataFromBusses` signal was an 8-level serial OR chain across 9 bus inputs (every memory read path). Now grouped into two parenthesized halves, reducing combinational depth from ~8 to ~4 levels.

2. **Removed unused `clk2x` port from memorymux** — Port was declared but never referenced. Removed from entity and instantiation to clarify the module's actual clock domain.

3. **Added `SYNCHRONIZER_IDENTIFICATION FORCED` attributes** to all CDC synchronizer first-stage registers:
   - `gpu_videoout_async.vhd`: All 3-FF chains for clk1x↔clkvid↔clk2x crossings
   - `justifier_sensor.vhd`: irq10 clkvid→clk1x chain
   - `PSX.sv`: SNAC input synchronizers (USER_IN3_1, USER_IN4_1, USER_IN6_1)
   - `psx_top.vhd`: Toggle synchronizers (clk1xToggle2X, clk1xToggle3X)

   This tells the fitter to place synchronizer chain stages close together for optimal metastability recovery time.

4. **Removed unused `debug_firstGTE` port chain** — The `debug_firstGTE` signal was output by GTE (with an associated 32-bit `debugCnt` counter), routed through `psx_top.vhd`, and connected to a CPU input port that was never read in the CPU architecture. Removed the port from all three files and the dead counter logic.

5. **Converted 4 MDEC tables from M10K to MLAB** — The IDCT scale tables (2× 64×16) and T-tables (2× 64×30) were using `dpram` (altsyncram/M10K) despite being small enough for MLAB. These use simple dual-port access (write A, read B) which is supported by `altdpram`/MLAB. Frees 4 M10K blocks. The `iIDCTiTable` (64×11) was NOT converted because it uses true dual-port writes (port B writes during IDCT_STAGE2).

---

## Remaining Opportunities (Not Yet Implemented)

### RTL — High Risk (cycle-accurate behavior)

These would help timing but risk breaking game compatibility:

- **GTE 64-way read mux** (`gte.vhd:392-463`): Pipelining the output would break the CPU-GTE stall timing
- **DMA control signals** (`dma.vhd:192-230`): `dmaOn`, `ram_cnt` are part of cycle-accurate CPU/DMA bus arbitration
- **CPU calcMemAddr pipeline** (`cpu.vhd:1100-1660`): Moving the 32-bit address add earlier in the pipeline could help but requires careful validation
- **SDRAM ready signal 2nd FF** (`sdram.sv:153-155`): Adding latency to the ready handshake could reduce SDRAM throughput

### BRAM/DSP Relief — Marginal

At 100% BRAM/DSP, any freed block helps placement flexibility, but the candidates are small:

| Module | Array | Size | Trade-off |
|--------|-------|------|-----------|
| cheats.vhd | `t_cheatmem` | 32 × 128-bit | Frees ~1 BRAM but costs ~512 ALMs |
| gpu.vhd | `t_ssarray` | 8 × 32-bit | Likely already in registers |
| timer.vhd | `t_ssarray` | 16 × 32-bit | Likely already in registers |

### High Fan-Out Signals

| Signal | Module | Fan-out | Notes |
|--------|--------|---------|-------|
| `ce` (clock enable) | psx_top.vhd | ~20 modules | PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION should help |
| `reset_intern` | psx_top.vhd | ~19 modules | Registered, fitter can duplicate |
| `SS_DataWrite` | psx_top.vhd | ~14 modules | Multicycle constraint applied |
| `addressData_buf` | memorymux.vhd | ~40+ loads | Manual duplication could help |

### 3-FF vs 2-FF Synchronizers

`gpu_videoout_async.vhd` uses 3-FF chains for all clk_vid crossings. Dropping to 2-FF for quasi-static signals (settings/reports records) would free registers and reduce placement pressure, but the risk is low and the gain is marginal.
