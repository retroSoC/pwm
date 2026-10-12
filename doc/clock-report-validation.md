# Runtime clock-reporting candidate

This uncommitted candidate starts from PWM revision
`79ae32f725e848a1e7f6134847b3fb032ed64006`. It supplies the shared PWM prerequisite
for Tiny `TINY-R2-P7`, not the Tiny RCU implementation or phase acceptance.

`UseRuntimeClockHz=0` keeps the existing `PCLK_HZ` readback. Setting it to one
selects the product-owned, PCLK-synchronous `pclk_hz_i` value at the existing
read-only `CLOCK_HZ` offset. No register definition, discovery value, C API,
timer, channel or capture implementation changes. See `integration.md` for
the quiescence, atomic commit and reset contract.

## Executed checks

The locked PWM standalone Common revision is
`6c318bf06570a2d195afb1708853ee921a058e5c`; an isolated sibling checkout supplies
that exact revision without changing the lock. Tools were supplied by
retroSoC's existing `tiny-r2-p1` development environment: Verilator 5.046,
Icarus 13.0, sv2v 0.0.13-9-gd381209, Yosys 0.67, SBY 0.67, Bitwuzla 0.9.1,
Verible v0.0-3946-g851d3ff4 and clang-format-14.

From the PWM checkout, the following commands passed. Each command's exit
status, timestamps and complete output are retained in `build/validation/`.

```sh
make --silent doctor format-check register-check lint test-host
make --silent -j2 test
make --silent synth
make --silent formal
make --silent \
  COMMON_ROOT=/nfs/share/home/miaoyuchi/retroSoC/rtl/managed/clusterip/common \
  BUILD_DIR=/tmp/retrosoc-pwm-pclk.jMjgi1/pwm/build/soc-common \
  test-clock-report-iverilog test-clock-report-verilator
```

Formal execution used the existing retroSoC `scripts/bitwuzla_smt2.py`
compatibility adapter via a build-local executable symlink, with
`RETROSOC_BITWUZLA` pointing to the real Bitwuzla binary. Neither the locked
solver nor the existing dead-time property was changed. This is the original
dead-time exclusion proof (base case plus induction), not a proof of an RCU.

| Result | Scope |
| --- | --- |
| `quality-final.json` | Formatting, parity (57 offsets / 17 scalars), wrapper lint, tools and unchanged host driver tests. |
| `tests-final.json` | Original scalar/channel Icarus and APB-wrapper Verilator tests plus the new clock-report fixture in both simulators. |
| `synthesis.json` | Existing core synthesis plus both register-bank configurations; structural checks report zero problems. |
| `formal.json` | Existing bounded/base-case and induction dead-time proof. |
| `soc-common.json` | Both clock-report simulators using retroSoC Common `964a54d70cb78e394ba9a25c05f2aa2b02941fb7`. |

The directed fixture checks runtime reports of 24/48/60/24 MHz, the static
72 MHz default even with an unknown sideband input, the existing static
parameter override, full/partial writes to the read-only register, unaligned
reads, actual clock-period changes, equal static/runtime output behavior and
an eight-high/eight-low waveform. A peripheral reset preserves the externally
committed 60 MHz report while resetting normal PWM control state. The original
fixtures separately test the 1 MHz static parameter override.

Yosys optimizes the new input out of the static read path; all 32 bits feed the
runtime read path. Optimized register-bank JSONs contain zero latch cells.
The logs retain intermediate loop-variable latch inference and memory-array
lowering observations; these are not technology-mapped timing or area results.
Native Icarus emits existing constant-select/unique-case limitations. The
parallel Make test run reports jobserver fallback to one build thread. Final
Verilator test/lint logs have no new RTL or fixture warning.

## Attempts and remaining boundaries

The first directed attempt failed because its test action table raised the
waveform at wrap rather than phase-up, producing nine high clocks instead of
eight. The test now explicitly uses phase-up high / duty-up low actions.
The next attempt exposed sv2v removal of the test's timescale directive;
Icarus now compiles a checked-in test-only timescale preamble before the
converted source. Neither correction changes PWM timing RTL. Earlier failed
logs remain separate from the final results.

No full Tiny/Mini firmware, PDK synthesis/netlist, STA, physical, CDC/RDC or
analog qualification was run for this standalone candidate. The default-mode
and actual-Common checks are component compatibility evidence only. No new
MISRA deviation is introduced; the C driver and its ABI are unchanged.

The original managed PWM checkout and retroSoC dependency lock remain at the
old revision. No commit or push has been performed. Upstream review and an
explicitly authorized published revision must precede a retroSoC lock upgrade
and product integration validation. Do not assign these reports to a future
revision without checking its exact source identity.
