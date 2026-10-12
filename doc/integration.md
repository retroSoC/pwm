# PWM V2 Integration Guide

## Clock, Reset, and Pins

With the default `UseRuntimeClockHz=0`, `PCLK_HZ` must match the APB clock
supplied through `apb4.pclk`. Tie the new `pclk_hz_i[31:0]` input to zero in
static integrations; it is ignored in this mode. Existing named-port instances
that omit it retain their static behavior, but should connect it when updating
their source lists to avoid missing-pin lint warnings.

Variable-clock products set `UseRuntimeClockHz=1` and drive `pclk_hz_i` with
the committed nominal peripheral rate in Hz. `CLOCK_HZ` remains read-only at
offset `0x030`; the register ABI, discovery values and common C HAL do not
change. This input changes reporting only, not the timers or clock hardware.

The product owns the following integration contract:

- Supply a valid nonzero 32-bit value from a register in the APB/PCLK domain.
  This port is not a CDC synchronizer, frequency detector or clock-change command.
- Quiesce PWM/capture and drain APB work before a rate transition. Commit the
  complete value atomically, keep it stable throughout each APB transfer, and
  acknowledge the product clock transition only after that commit.
- Keep software out of frequency-dependent configuration while the product RCU
  reports BUSY. Recalculate timer/capture settings before restarting PWM.
- Drive the safe rate at cold boot. A peripheral-only reset does not reset
  this product-owned value: readback continues to describe the committed rate.

No fallback to `PCLK_HZ` is applied in runtime mode: zero or unknown input is
an integration error, not a request to report the static rate. The PWM block
does not qualify source stability, analog lock or physical timing.

The design uses
only that clock and active-low `apb4.presetn`; timer and capture rates are
clock-enable based. Route `pwm_o` and `oe_o` through the SoC pin multiplexer so
high-impedance fault policy reaches the physical pad enable.

The fault, sync, and capture pins may be asynchronous. The IP synchronizes
status/control behavior with Common `cdc_sync`. The active fault has an
additional combinational path to the final safe-state mux for prompt shutdown.
Constrain this asynchronous safety path explicitly and verify its pulse-width,
pad, and technology behavior. Do not treat the synchronized fault latency as
the product's only shutdown path.

## Recommended Pin Routing

- Four alternate-function GPIOs for `pwm_o[3:0]` and `oe_o[3:0]`.
- One dedicated or alternate-function GPIO for `fault_i`.
- One alternate-function GPIO for `sync_i`.
- Two alternate-function GPIOs for `capture_i[1:0]`.
- One maskable interrupt input for `irq_o`.

## Constraints and Sign-off

- Declare external inputs asynchronous to the APB clock.
- Preserve/identify the two-stage synchronizers for CDC analysis.
- Apply an input delay or explicit asynchronous exception to the raw fault path
  according to the technology sign-off methodology.
- Check minimum external fault pulse width in post-layout simulation.
- Verify dead-time and safe-state behavior through I/O cells, including output
  enable polarity.
- Define low-power retention, debug-halt, and clock-gating policy at SoC level.

PWM V2 deliberately has no ETM/event-fabric sideband. Synchronization sources
are software, external input, and the peer timer zero event.
