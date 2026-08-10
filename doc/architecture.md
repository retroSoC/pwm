# PWM V2 Architecture

## Block Structure

`apb4_pwm` adapts the Common APB4 interface to `pwm_reg`. The register bank
owns access validation, byte strobes, shadow configuration, commands, sticky
interrupt state, and capability discovery. `pwm_core` contains the datapath:

```text
APB4 -> pwm_reg -> timers -> channels -> dead time -> carrier -> PWM/OE
                    |          |                         ^
sync ---------------+          +-> linear/gamma fade    |
fault -> sync/filter/latch ------------------------------+
capture -> sync/filter -> timestamp FIFO -> APB4
```

The implementation has two timer resources, four channels, two operators, and
two capture channels. Operator 0 owns outputs 0/1 and operator 1 owns outputs
2/3. A channel selects either timer independently; complementary mode instead
uses the even channel as the operator source and derives the odd output.

## Timing Model

Each timer has a 24-bit Q16.8 divider. `pwm_tickgen` adds 256 to a phase
accumulator every peripheral clock and emits a one-cycle tick when the sum
reaches the divider. Therefore:

```text
timer_tick_hz = PCLK_HZ * 256 / DIVIDER_Q16_8
```

The minimum divider is 256, so the timer never advances faster than `PCLK_HZ`.
No generated clocks are used. Up/down modes and compare actions run from tick
enables in the APB clock domain.

## Coherent Update and Synchronization

Timer divider/period/phase and channel phase/duty are shadowed. `COMMAND.UPDATE`
marks them pending; each timer load policy commits at zero, period, sync, or
zero/sync. Software can issue `COMMAND.SYNC`, and an enabled timer can also
accept the external sync input or the other timer's delayed zero event. This
permits coherent multi-channel updates without output glitches or combinational
timer loops.

## LED and Motor Features

Every channel has a 16-bit action table with two-bit actions for zero, period,
phase-up, duty-up, phase-down, duty-down, sync, and fade-done events. Actions
are hold, low, high, or toggle. Linear fade moves duty toward one target. Gamma
mode executes up to eight target/step/interval segments stored in channel-local
register arrays.

Each operator supports complementary generation, independent rising/falling
dead time, and a programmable carrier period/duty/inversion stage. Fault logic
supports polarity, digital filtering, cycle-by-cycle or one-shot behavior,
software injection, sticky status, and low/high/high-impedance safe state per
output. The raw active fault also gates outputs immediately; synchronized logic
provides deterministic latching and status.

## Capture

A 32-bit timestamp counter has its own Q16.8 divider. Each synchronized capture
input selects rising and/or falling edges, a 0-15 cycle stability filter, and a
1-4 entry watermark. Timestamps enter a Common four-entry FIFO. Reading `DATA`
pops one entry; an empty read returns APB `PSLVERR`.
