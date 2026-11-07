# rp-open-hls: open C → FPGA bitstream pipeline for the Red Pitaya STEMlab 125-14

Prototype of a fully open, **aarch64-native** (Raspberry Pi 5, Debian forky,
4 cores, 15 GB RAM, no swap, no sudo) flow from a C kernel to a loadable
bitstream for the Red Pitaya STEMlab 125-14 (Zynq-7010, `xc7z010clg400-1`):

```
hls/biquad.c ──Bambu 2026.11 (+clang 19)──► biquad2.v ──┐
rtl/rp_top.v  (PS7 + AXI GP0 regs, PLLE2, ADC, /16 decimator, ODDR DAC)
                                                         ▼
 yosys ─► nextpnr-himbaechel (openXC7, xc7z010 chipdb) ─► .fasm
       ─► fasm2frames + xc7frames2bit (prjxray) ─► .bit ─► bootgen ─► .bit.bin
```

**No Red Pitaya was attached.** Everything up to `.bit.bin` was produced
and checked by simulation and a bitstream round-trip. Nothing has run on
hardware.

Reproduce everything: `tools/build_all.sh` (toolchain, about 2.5 h of builds),
then `tools/run_all.sh` (all tests, HLS, bitstreams and reports, ~10 min).

## Status by stage

| # | Stage | Status |
|---|---|---|
| 1 | Toolchain (yosys, nextpnr-xilinx/openXC7 + xc7z010 chipdb, prjxray + db, fasm, bootgen, iverilog, verilator) | **done** (yosys 0.70 source build only partly done; the Debian 0.66 binary was used for every result) |
| 2 | Open HLS front end on aarch64 | **done**: PandA Bambu 2026.11 built from source with clang 19. XLS, Dynamatic and CIRCT were rejected (evidence below) |
| 3 | Demo kernel in C + bit-exact RTL test | **done**: 1 section and the 2-section cascade, 0 mismatches over 4702 vectors each |
| 4 | Red Pitaya top → bitstream | **done**, with 2 open-tool workarounds and 1 big caveat: nextpnr does not time DSP48 paths |
| 5 | Bonus: cds_io2 through yosys + nextpnr | **done**: 1965 LUT, 113.7 MHz (fails 125 MHz) |
| 6 | Multi-clock / multi-rate in Bambu | notes + one experiment (decimating FIFO kernel, bit-exact) |

---

## 1. Toolchain (all user space, `~/opt`)

Pinned in `tools/build_all.sh` (it calls `tools/build_*.sh`); `tools/env.sh`
sets PATH and the database paths. Versions follow openXC7's CI-validated
combination (`openXC7/toolchain-nix`, `nix/*.nix`).

| Tool | Version / rev | How | Build time on the Pi 5 |
|---|---|---|---|
| micromamba + conda-forge env | python 3.12, cmake 4.4, boost 1.92, eigen, bison, flex, **verilator 5.054** | `micromamba create` | ~3 min |
| clang/LLVM (for Bambu) | 19.1.7 (conda-forge `clangdev`/`llvmdev`) | `micromamba create` | ~3 min |
| yosys | **0.66** Debian arm64 `.deb` unpacked with `apt-get download` + `dpkg -x` (`tools/get_yosys_deb.sh`) | binary | <1 min |
| yosys (source) | v0.70, `tools/build_yosys.sh` | cmake/ninja -j3 | **not finished**: 1900/2224 objects after ~70 min, paused to give the CPU to Bambu. The slang SystemVerilog front end alone is ~155 heavy objects |
| nextpnr | openXC7/nextpnr `cf5f7a210fa2` (himbaechel, `-DHIMBAECHEL_UARCH=xilinx`) | `tools/build_nextpnr.sh` | 9 min (-j2) |
| chipdb | `xilinx_gen.py --device xc7z010` + `bbasm` → `chipdb-xc7z010.bin` (21.8 MB) | same script | 2 min + 6 s |
| prjxray-db | openXC7/prjxray-db `b12466df16ec` | git | – |
| prjxray | openXC7/prjxray `54fea88cc61b` (`xc7frames2bit`, `bitread`; `fasm2frames.py`, `bit2fasm.py`) | `tools/build_prjxray.sh` (toolchain-nix patches) | 7 min (-j1) |
| fasm | openXC7 fork `2f57ccb1727a`, pure-Python textX parser (the ANTLR fast path did not build) | PYTHONPATH | – |
| bootgen | Xilinx/bootgen `xilinx_v2026.2` | `tools/build_bootgen.sh` | 6 min |
| iverilog | v13_0 | `tools/build_iverilog.sh` | 12 min |
| Bambu | PandA-bambu `2026.11` (cda4db2e) | `tools/build_bambu.sh` | ~65 min wall (-j2, then -j4) |

Notes:
- nextpnr-xilinx (gatecat/openXC7 fork) is **archived**. Development
  continues in `openXC7/nextpnr` (himbaechel xilinx uarch), which is what
  is used here. The `nextpnr-xilinx` CLI is provided by the upstream shim
  script.
- openXC7 now assembles bitstreams with `fpga-as` (lromor/fpga-assembler,
  Bazel). This repo uses the classic `fasm2frames` + `xc7frames2bit` pair,
  which openXC7 CI still cross-checks against fpga-as.
- The chipdb generator reports that 3.7 % of xc7z010 tile pips have no
  bitstream bits in prjxray-db, including 260 in `PSS2` (see risks).
- verilator was installed but not used; all simulations are iverilog.

## 2. HLS front end: tool comparison

| Tool | aarch64? | Verdict | Evidence |
|---|---|---|---|
| **PandA Bambu 2026.11** | builds from source | **chosen** | CMake build with system gcc 16 + conda clang 19. Needed one aarch64 fix (below). C front end, scheduling, binding, Verilog writer and testbench all work. ~11 s per kernel. |
| Google XLS (xlscc) | no binaries | rejected | Releases ship only `xls-…-linux-x64.tar.gz` (checked 2026-11-07); litex-hub conda `xls` exists for linux-64 only. A source build means Bazel 8.7 building all of LLVM+clang (xlscc links clang), Z3, etc.: hours on 4 cores and large memory, with no aarch64 CI. |
| Dynamatic (EPFL) | source only | rejected | `build.sh --use-prebuilt-llvm` stops with "Prebuilt LLVM is currently configured only for Linux/X86". Building its LLVM fork needs "at least 50GB of free disk space and 16GB+ of RAM" (their docs); this box has 52 GB free, 15 GB RAM and no swap. Also VHDL-first and its simulation flow needs ModelSim/Questa. |
| CIRCT (handshake / Calyx flows) | no binaries | rejected | GitHub releases: linux-x64 and macOS only. PyPI `circt` wheels: `manylinux x86_64` and `macosx arm64` only. It also has no C front end of its own; it needs Polygeist (cgeist), i.e. another LLVM/MLIR source build. |
| Vericert, PipelineC, LegUp, … | – | not attempted | Vericert (Coq/CompCert) is research-grade and needs an opam/Coq build. PipelineC emits VHDL and needs GHDL + the yosys plugin. LegUp is closed/commercial now. |

Bambu-on-aarch64 findings:
- **Bug, fixed in `tools/build_bambu.sh`.** Without 32-bit glibc headers,
  Bambu builds libbambu only for `-mx32`/`-m64`. With `-m64`, the host clang
  targets **aarch64**, which defines `__FP_FAST_FMA`. musl's `log`, `log2` and
  `pow` then use `fma`, and Bambu's IR dumper aborts with "Code generator does
  not support intrinsic function 'llvm.fma.f64'". Fix: add
  `-U__FP_FAST_FMA -U__FP_FAST_FMAF` to the libbambu libm flags.
- Related caveat: on this host the HLS front end compiles C with aarch64 C
  semantics. **Plain `char` is unsigned**, and `long double` is 128-bit.
  The kernel uses only `<stdint.h>` types, so it is unaffected.
- Device `xc7z020-1clg484-YOSYS` errors out with "Unknown backend flow:
  xilinx/yosys_flow" *after* writing identical RTL. `xc7z020-1clg484`
  (same 7-series -1 fabric as the 7z010) runs cleanly and is the default.
- `--no-iob` no longer exists. The default `--reset-type=no` gives registers
  without reset, so `run_bambu.sh` uses `--reset-type=sync --reset-level=high`.
- C `static` state becomes a 1-word `ARRAY_1D_STD_DISTRAM` initialised from a
  `.mem` file through `$readmemb`. Yosys needs these files (and a default
  `array.mem`) in its working directory; `tools/flow.sh` copies them.

## 3. Demo kernel and bit-exact verification

`hls/biquad.c` is plain C99 (no `ap_fixed`, no pragmas), the same file for gcc
and Bambu. It implements the LIGO biquad from the PyRPL-track doc and
`hls_codegen.py`:
`tmp = G·x + C0·w + C1·u; w' = G·x + A10·w + A11·u; u' = u + w; y = tmp`.
- Formats: signals int32 Q16.16, coefficients int32 Q4.28. These match the
  `hls_codegen.py` defaults `ap_fixed<32,16>` / `ap_fixed<32,4>` with
  AP_TRN/AP_WRAP.
- Arithmetic: the three products are exact 64-bit, the sum wraps mod 2^64,
  and the result is bits [59:28] wrapped to 32 bits.
- Kernels: `biquad1` (one section) and `biquad2` (2-section cascade). A
  `clear` argument resets the state.

Verification chain:
1. `ref/biquad_ref.py` is an independent Python model (unbounded ints with
   explicit wrap). It generates 4702 vectors per kernel:
   - full-scale impulse, then 199 zeros;
   - negative full-scale step;
   - 2000 random 14-bit ADC codes;
   - mid-stream coefficient change;
   - clear + impulse;
   - 2000 samples with full-range random x and coefficients and 2 % random
     clears, which exercise both wrap paths.
   The default coefficients are a 50 kHz Butterworth lowpass and a +6 dB
   200 kHz peak, both at fs = 125 MHz / 16.
2. `ref/check_c.c`: gcc-compiled `biquad.c` vs Python. **0 mismatches**
   (biquad1 and biquad2, 4702 vectors each).
3. `sim/tb_kernel.v` (iverilog) drives the Bambu RTL through `kernel_wrap`
   (start/done):

| Kernel | Vectors | Mismatches | Latency (clocks) |
|---|---|---|---|
| Bambu `biquad1` | 4702 (+ again with 7 idle clocks between samples) | **0** | 5 |
| Bambu `biquad2` | 4702 (+ gap run) | **0** | 8–9 |
| hand RTL `kernel_hand.v`, 1 / 2 sections (comparison) | 4702 | 0 | 3 / 4 |
| Bambu `decim_biquad2` (stage 6) | 400 calls × 16 ADC samples | **0** | 27 per call |

4. `sim/tb_top.v` is a system simulation of `rp_top` with the Bambu cascade.
   It uses a PS7 stub that drives AXI GP0 and behavioural PLL/ODDR models.
   Checks: ID register, coefficient defaults, an atomic coefficient write
   with CTRL.freeze, every kernel output (256 samples) against a reference,
   DAC A decoded from the interleaved ODDR pins equals `sat14(Y_LAST)`, and
   bypass mode. Result: **0 errors**, LATENCY 9, OVERRUNS 0.

## 4. Red Pitaya top level → bitstream

`rtl/rp_top.v`, `rtl/axi_regs.v`, `constraints/rp_125_14.xdc` (generated by
`tools/gen_xdc.py` from the vendor `redpitaya-fpga/sdc/red_pitaya.xdc`).
- **Clocks.** `IBUFDS` on the ADC clock (U18/U19, DIFF_HSTL_I_18) feeds a
  `PLLE2_ADV` (VCO 1 GHz) with outputs 125 MHz (ADC + DAC 1x), 250 MHz (DAC
  WRT) and 250 MHz at −45° (DAC CLK), each through a BUFG, as in the vendor
  `red_pitaya_pll.sv`.
- **ADC → DAC path.**
  - ADC A goes through a boxcar /16 decimator into the kernel at
    7.8125 MS/s (start/done handshake; overruns are counted).
  - The kernel output passes Q16.16 → 14-bit saturation and a
    sample-and-hold, then reaches DAC A through the vendor ODDR interleave
    (clk/wrt/sel/rst + 14 data ODDRs).
  - DAC B passes ADC B straight through.
- **PS7.** `M_AXI_GP0` is clocked by the 125 MHz PL clock, so the whole PL is
  one domain plus the 250 MHz ODDR clocks, with no CDC. A minimal AXI3 slave
  (`axi_regs.v`) at 0x4000_0000 holds:
  - ID, CTRL (clear / bypass / coefficient freeze / LEDs);
  - status: SAMPLES, LATENCY, OVERRUNS, X_LAST, Y_LAST, DECIM;
  - 2×5 Q4.28 coefficients, double-buffered into a shadow copy at each
    sample unless frozen.
- DDR/MIO ports of PS7 are left unconnected, as in openXC7's PYNQ-Z1 PS7 demo.

Results (`tools/run_all.sh` → `python3 tools/report.py build/top_*`):

| Design | LUT | FF | CARRY4 | DSP48E1 | BRAM | nextpnr Fmax `clk` (target 125 MHz) | yosys / nextpnr / bitgen time |
|---|---|---|---|---|---|---|---|
| `top_bambu2` (HLS 2-section cascade) | 1571 | 2610 | 220 | 40 | 0 | 168.9 MHz* | 12 s / 77 s / 23 s |
| `top_bambu1` (HLS 1 section) | 1013 | 1654 | 127 | 20 | 0 | 183.6 MHz* | 9 s / 26 s / 15 s |
| `top_hand` (hand RTL 2 sections, 1 section/clock) | 1312 | 1320 | 134 | 20 | 0 | 167.2 MHz* | 23 s / 93 s / 44 s |
| kernel only: Bambu biquad1 / biquad2 | 556 / 1116 | 702 / 1498 | 93 / 186 | 20 / 40 | 0 | – | – |
| kernel only: hand RTL 1 / 2 sections | 977 / 1043 | 102 / 167 | 99 / 99 | 20 / 20 | 0 | – | – |

LUT is the count of yosys LUT1–6 cells (xc7z010: 17,600). nextpnr's own
`SLICE_LUTX` counts LUT5/LUT6 halves (35,200). The 250 MHz DAC clocks
drive only ODDRs, so they have no FF-to-FF paths and nextpnr reports no Fmax
for them. The final bitstreams are `build/top_bambu2/top_bambu2.bit` (2,083,848 B)
and `.bit.bin` (2,083,744 B, byte-swapped for `fpgautil`/fpga_manager).

**\* Timing caveat (most important finding).** nextpnr-himbaechel/xilinx
has **no timing arcs for DSP48E1**: the chipdb generator imports SDF timing
for LUT/FF/CARRY/BRAM but nothing for DSP. Paths through DSPs are therefore
cut, and the Fmax above excludes the multiplier datapath. Proof:
`sim/probe/dsp_timing_probe.v` (two chained 32×32 multiplies between
registers, 6 DSP48) reports **330–400 MHz, PASS at 300 MHz**. That is
impossible on a −1 part.

Bambu maps each 32×32 multiply to a single stage (`PIPE_PARAMETER=1`), and
yosys builds it as a 4-DSP48 cascade with LUT adders. Yosys packs the operand
registers into AREG/BREG but **never uses MREG/PREG**, at every Bambu pipeline
depth tried (`--clock-period` 8 / 4 / 2.5 → `PIPE_PARAMETER` 1 / 2 / 6, all
still bit-exact, latency 9 / 12 / 22). Yosys does not retime registers into
the cascade. A datasheet-level estimate of that path (A→P ≈ 4 ns plus ≈ 2 ns
per PCIN hop, plus input muxes and routing) is **≈ 10–12 ns. This likely
fails at 8 ns on silicon.**

Open-tool blockers hit and worked around:
1. **ODDR with a non-constant `R`.** The vendor DAC ODDRs use `.R(dac_rst)`.
   nextpnr aborts in the packer: `net '$PACKER_GND_NET' user port
   'oddr_dac_sel.SR' connected to incorrect net 'dac_rst'` (INTERNAL CHECK
   FAILED). Workaround: `R=0`, with the reset folded into D1/D2.
2. **PLLE2 `COMPENSATION="ZHOLD"`** (vendor setting) hits
   `Assertion failure: unsupported compensation type` (`fasm.cc:2712`); only
   `INTERNAL` is supported. Workaround: `PLL_COMPENSATION="INTERNAL"`.
   This changes the ADC capture phase relative to the vendor bitstream.
3. Minor: PS7 `MAXIGP0AxSIZE` is 2 bits wide (a yosys warning led to a fix
   in the RTL). Yosys 0.66 asserts in `xilinx_dsp.cc:400` on initialised
   registers feeding a DSP (only seen in the probe). nextpnr needs every
   top-level port constrained ("unconstrained IO not supported").
   nextpnr exits 1 when a clock misses its constraint, unless
   `--timing-allow-fail` is given (used for the cds_io2 bench).

Bitstream sanity check (`tools/check_bit.sh`): the `.bit` is decoded back to
FASM with prjxray `bit2fasm`. All bit-carrying features that nextpnr emitted
are present (**0 missing configuration bits**). The ~19.6 k nextpnr-only
features are bitless pseudo-pips and defaults. About 4.2 k of them are
PS7↔PL interface pips in the PSS tiles that prjxray-db documents as having no
bits.

## 5. Bonus: cds_io2 (hand-written RTL) through yosys + nextpnr

`bonus/cds_io2_bench.v` wraps the unmodified `rp-frontend-bot/fpga/rtl/cds_io2*.v`
(TAPS=2, the 7z010 configuration). All ~310 inputs are fed from an LFSR
shift chain (one FF each, no constant propagation) and the outputs are
XOR-reduced onto one LED.

- One yosys incompatibility: a module-level `integer i` reused by several
  `initial for` loops gives "Conflicting initialization values for \i".
  Vivado accepts it. `bonus/localize_initial_loops.py` rewrites a build-time
  copy so each loop gets a local `integer i`; the source repo is untouched.
- **Result:** LUT 1965, FF 2643 (≈310 of them bench), LUTRAM 27, CARRY4 177,
  DSP48E1 8, RAMB36 1 + RAMB18 2.
- **nextpnr Fmax 113.7 MHz: FAIL at 125 MHz.** The critical path is a
  comparator chain at `cds_io2.v:734`, 8.8 ns, 62 % routing. Its 8 DSPs are
  untimed, as above.
- yosys 47 s, nextpnr 146 s.
- For comparison, the PyRPL-track budget leaves ~2.2 k LUTs free on the 7010.

## 6. Multiple clocks / sample rates in Bambu

- **One clock per design.** `--clock-name` and `--clock-period` are single
  values and there is no clock-domain concept in the IR or interfaces. Any
  CDC (for example ADC 125 MHz ↔ AXI on FCLK0) must be hand RTL around the
  kernel: async FIFOs or register synchronisers. Here it was avoided by
  clocking GP0 from the ADC clock.
- **Rates are handshake-driven.** The MINIMAL interface (start/done/idle) is
  a natural multi-rate boundary: the kernel runs once per `start`. The
  surrounding RTL owns the rate (decimate by 16 here), and the kernel's
  latency must stay below the sample period. `OVERRUNS` counts violations.
- **In-C rate change works through stream ports, with traps.**
  `hls/decim_biquad.c` uses `#pragma HLS interface port=adc mode=fifo` with
  `--generate-interface=INFER`. That gives `adc_dout` / `adc_empty_n` /
  `adc_read`, and the function pops 16 samples per output, bit-exact over
  400 calls.
  - Without `volatile`, LLVM merges the 16 `*adc` reads into one pop.
    Simulation caught it: one pop per call and 300/400 mismatches. Use
    `volatile` or `ac_channel` (Bambu also has `ac_channel` with blocking and
    non-blocking read/write, "async" in Bambu's tests means non-blocking, not
    another clock).
  - The sequential loop + cascade take **27 clocks per 16 input samples**, so
    this form cannot sustain 125 MS/s input.
  - `#pragma HLS pipeline` inside the loop is rejected ("Loop pipelining
    pragma not supported"); at function level Bambu refuses because the
    function contains a loop.
  - Overlapping decimator and filter needs Bambu's dataflow/task mode
    (`ac_channel` between functions, new in 2026.11), which was not tried.
- **Practical split for this platform:** keep the 125 MS/s parts (decimator,
  CIC, DAC interleave) in hand RTL and run HLS kernels at the decimated rate
  behind start/done or FIFO ports. This matches the "fast front end +
  engine" split in `open-toolchain-track.md`.

## What remains before trying the bitstream on a board

1. **Timing of the DSP datapath.** Either:
   - add DSP48E1 timing arcs to the openXC7 chipdb (the prjxray `DSP_L/R.sdf`
     timings exist but are not imported), or
   - re-check the kernel with an independent STA, or
   - narrow the arithmetic to one DSP per product (25×18: for example
     18-bit coefficients with 25-bit signals, or a cascaded multiply that is
     deliberately pipelined in hand RTL or a Bambu library override).
   Until then, treat 125 MHz kernel timing as unverified, and probably
   failing.
2. **ADC capture phase.** With `COMPENSATION=INTERNAL` instead of `ZHOLD`, and
   because nextpnr did not pack the ADC input FFs into ILOGIC (0 `ILOGICE3_IFF`
   used despite `IOB=TRUE`), the sampling point moves by the clock-insertion
   and fabric-routing delay. The ADC data may be sampled near its transition.
   Plan: test with a DC/slow sine input. If the bits are noisy, use the
   PLL `CLKOUT0_PHASE` or an IDELAYE2 (+IDELAYCTRL) to re-centre.
3. **PS7/AXI.** Load the bitstream on RP OS 2.x:
   - `bootgen -image x.bif -arch zynq -process_bitstream bin` (done; the
     output is `*.bit.bin`), then `fpgautil -b top_bambu2.bit.bin`, or
     `/lib/firmware` + fpga_manager;
   - `devmem 0x40000000` should read `0x52504831`.
   The PS7↔PL pips that have no bits in prjxray-db are the biggest unknown.
   openXC7's PYNQ-Z1 PS7 demo is the existence proof that this path works.
4. **DAC.** Verify the ODDR interleave and the 250 MHz/−45° clocks on a scope
   (the reset-in-D workaround is functionally equivalent). Check sel/wrt
   polarity against the AD9767.
5. **Software.** Write a small `devmem`/Python loader for the coefficient
   registers (`ref/biquad_ref.py` already produces Q4.28 LIGO-form words),
   then measure the transfer function.

**What I'd expect to fail first:** if the board takes the bitstream at all
(DONE high; the PS7 pips without bits are the risk), the first visible
failure is probably **corrupted ADC samples** (point 2) or a **wrong filter
output from timing violations in the untimed 32×32 DSP cascades** (point 1).
These would show as noisy or garbage DAC output while the AXI registers still
read correctly. A pure-RTL bypass test (`CTRL=2`: DAC A = decimated ADC A)
isolates (2) from (1).

## Repository layout

```
hls/        biquad.c/.h (kernel), decim_biquad.c (multi-rate experiment), run_bambu.sh
ref/        biquad_ref.py (bit-exact Python model + vectors), check_c.c, decim_vectors.py
rtl/        rp_top.v, axi_regs.v, kernel_bambu.v (wrapper), kernel_hand.v (hand RTL)
sim/        tb_kernel.v, tb_top.v, tb_decim.v, prims_sim.v, probe/ (DSP timing probe)
constraints/rp_125_14.xdc (generated by tools/gen_xdc.py from the vendor pin file)
bonus/      cds_io2 bench + yosys workaround script
tools/      env.sh, build_*.sh (pinned toolchain), flow.sh, check_bit.sh, report.py,
            synth_kernel.sh, run_all.sh
build/      (git-ignored) all generated RTL, logs, .json/.fasm/.bit/.bit.bin
```
