# Timing Closure Analysis — PSX_MiSTer

This document identifies opportunities to improve timing closure on the Cyclone V FPGA. The design is resource-constrained (100% BRAM, 100% DSP, 80%+ logic utilization), which limits fitter flexibility and makes timing closure unreliable.

Nothing in `/sys/` should be modified — it is shared MiSTer framework code.

---

## 1. Fitter Settings (QSF) — Zero Risk, Immediate Benefit

Current QSF settings are conservative for a design at this utilization level.

| Setting | Current | Recommended | Notes |
|---------|---------|-------------|-------|
| `FITTER_EFFORT` | `STANDARD FIT` | `AGGRESSIVE FIT` | More placement/routing iterations on critical paths |
| `PLACEMENT_EFFORT_MULTIPLIER` | `1.0` | `1.5` – `2.0` | Extra placement iterations; helps at high utilization |
| `ALM_REGISTER_PACKING_EFFORT` | `LOW` | `MEDIUM` | Packs registers more aggressively to reduce routing congestion |
| `SEED` | `1` (fixed) | Try multiple seeds during dev | Different seeds escape local minima; keep fixed for release |

These cost compile time but require no RTL changes. `AGGRESSIVE FIT` alone can make a meaningful difference at 80%+ utilization.

---

## 2. SDC Constraint Improvements — Low Risk, Frees Fitter Effort

### Missing false paths for quasi-static CDC signals

`PSX.sdc` has 10 false paths for PLL isolation but is missing constraints for quasi-static signals that the fitter is currently trying (and struggling) to time. These signals only change on OSD interaction or region detection:

```tcl
# Quasi-static control signals — change only on OSD/region change
set_false_path -from [get_registers {emu|video_isPal}]
set_false_path -from [get_registers {emu|fast_forward}]
set_false_path -from [get_registers {emu|status[*]}] -to [get_clocks {*pll2*}]
```

Telling the fitter to ignore these paths frees routing resources for paths that actually matter.

### Phase-aligned clock crossings

Crossings between `clk_1x ↔ clk_2x` and `clk_1x ↔ clk_3x` are safe because these clocks come from the same PLL with fixed phase alignment. Adding multicycle path constraints documents this and gives the fitter margin:

```tcl
# clk_1x and clk_2x are phase-aligned from same PLL (2:1 ratio)
# Direct cross-domain transfers in savestates.vhd and spu_ram.vhd rely on this
set_multicycle_path -from [get_clocks {*clk_1x*}] -to [get_clocks {*clk_2x*}] -setup 2
set_multicycle_path -from [get_clocks {*clk_1x*}] -to [get_clocks {*clk_2x*}] -hold 1
```

---

## 3. Critical Combinational Paths — Highest Impact RTL Changes

### 3a. memorymux.vhd — 9-way bus OR (line ~426)

**The single widest combinational path in the design.** Every memory read passes through:

```vhdl
dataFromBusses <= bus_memc_dataRead or bus_pad_dataRead or bus_sio_dataRead or
                  bus_memc2_dataRead or bus_irq_dataRead or bus_dma_dataRead or
                  bus_tmr_dataRead or bus_gpu_dataRead or bus_mdec_dataRead;
```

This is 8 levels of 32-bit OR gates in series.

**Options:**
- **Tree restructure** (no latency cost): Group into two sets of 4–5, OR each group, then OR the results. Reduces depth from ~8 to ~4 levels.
- **Register pipeline** (1-cycle latency): Register `dataFromBusses` output. Peripheral reads already have latency tolerance, but requires verifying no tight read-to-use dependencies.

Additionally, `addressData_buf` fans out to all 9 bus decoders (~40+ loads), creating high capacitive load. Manual register duplication of this signal could help.

### 3b. cpu.vhd — Instruction decode + ALU (lines ~1100–1660)

Massive case statement with 60+ instruction types. Key issue:

- `calcMemAddr` (32-bit addition) is computed, then immediately used for alignment checks and exception generation — all combinationally in the same cycle
- Overflow detection requires XOR trees + AND gates + conditional logic (~5–6 gate levels)
- Address alignment checks at lines 1562–1650 add further depth

**Options:**
- Move `calcMemAddr` computation earlier in the pipeline (to decode stage)
- Register exception outputs separately from ALU results

### 3c. gte.vhd — 64-way read mux (lines ~392–463)

A 64-entry case statement with conditional saturation logic (clamping IR1/IR2/IR3 values). The saturation comparisons add 4 gate levels on top of the mux selection.

**Option:** Register `gte_readData` output. The GTE read path likely has a cycle of tolerance since the CPU must decode the MFC2 instruction result.

### 3d. dma.vhd — Control decode (lines ~192–230)

Barrel shifters for `chopsize`/`chopwaittime` plus the multi-condition `dmaOn` signal (~6–8 gate levels).

**Option:** Register `ram_cnt`, `dmaOn`, `chopsize`, and `chopwaittime`. DMA state transitions are already clocked, so adding one cycle of output latency is straightforward.

---

## 4. High Fan-Out Signals

| Signal | Module | Estimated Fan-out | Notes |
|--------|--------|-------------------|-------|
| `addressData_buf` | memorymux.vhd | ~40+ | Address bus to all 9 peripheral decoders |
| `ce` (clock enable) | cpu.vhd | ~100+ | Gates all pipeline stage updates |
| `dmaState` | dma.vhd | ~15+ | Enum compared in many places |
| `bus_gpu_stall` | gpu.vhd → memorymux.vhd | ~3–5 (but critical path) | Combinational feedback loop |

The fitter has `PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON` (already enabled), which should handle some of this automatically. Manual duplication of `ce` in cpu.vhd may help if it appears in timing reports.

---

## 5. BRAM/DSP Relief — Marginal Gains

At 100% BRAM and 100% DSP utilization, any freed block helps the fitter with placement flexibility.

### Small arrays that could move to registers (free BRAM)

| Module | Array | Size | Candidate? |
|--------|-------|------|------------|
| cheats.vhd | `t_cheatmem` | 32 × 128-bit | Yes — small, infrequent access |
| gpu.vhd | `t_ssarray` | 8 × 32-bit | Yes — tiny save state |
| timer.vhd | `t_ssarray` | 16 × 32-bit | Maybe — small save state |
| memctrl.vhd | `t_ssarray` | 32 × 32-bit | Maybe — borderline size |

### DSP considerations

- All multiplications are in performance-critical paths (GTE MAC units, audio mixing) — these should stay in DSP blocks
- The divider (`divider.vhd`) is already implemented in logic, not DSP
- No obvious DSP-to-logic trade candidates without significant rework

---

## 6. 3-FF vs 2-FF Synchronizers

`gpu_videoout_async.vhd` uses 3-FF synchronizer chains for all `clk_vid` domain crossings. At high utilization, extra FFs compete for placement. If the fitter can't place all 3 stages close together, the added routing delay can eat into the resolution time the 3rd stage was supposed to provide.

**Consider:** Dropping to 2-FF for signals where the MTBF with 2 stages is already sufficient (the quasi-static settings/reports records). This frees a small number of registers and reduces placement pressure. The truly asynchronous `clk_vid` domain justifies 3-FF only for signals that change frequently relative to the clock period.

---

## Recommended Priority

| Priority | Change | Risk | Effort |
|----------|--------|------|--------|
| 1 | Fitter settings in QSF | None | Trivial |
| 2 | Add false_path / multicycle_path constraints in SDC | Minimal | Small |
| 3 | Tree-restructure memorymux OR chain | Low | Small |
| 4 | Register GTE read mux output | Low | Small |
| 5 | Register DMA control outputs | Low | Small |
| 6 | Move small arrays from BRAM to registers | Low | Medium |
| 7 | Pipeline CPU calcMemAddr | Medium | Medium |
| 8 | Evaluate 3-FF → 2-FF for quasi-static signals | Low | Small |
