# PWM V2 Integration Guide

## Clock, Reset, and Pins

`PCLK_HZ` must match the APB clock supplied through `apb4.pclk`. The design uses
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
