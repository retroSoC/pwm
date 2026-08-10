# PWM V2 Datasheet

## Scope and Interfaces

PWM V2 is an APB4 LED and motor-control PWM controller. It exposes four PWM
values and four output enables, one fault input, one synchronization input, two
capture inputs, a debug-halt input, and one combined interrupt output.

| Interface or port | Direction | Description |
| --- | --- | --- |
| `apb4` | slave | 32-bit APB4 programming interface. |
| `debug_halted_i` | input | Freezes enabled timers when `CTRL.DEBUG_FREEZE` is set. |
| `pwm.fault_i` | input | Asynchronous external fault input. |
| `pwm.sync_i` | input | Asynchronous timer synchronization input. |
| `pwm.capture_i[1:0]` | input | Asynchronous timestamp capture inputs. |
| `pwm.pwm_o[3:0]` | output | PWM output values. |
| `pwm.oe_o[3:0]` | output | Output enables; low represents high impedance. |
| `pwm.irq_o` | output | OR of enabled sticky interrupt sources. |

`PREADY` is always high. Misaligned, unmapped, reserved-value, read-only,
write-only, unsafe-while-running, locked, and empty-FIFO accesses complete with
`PSLVERR`. APB byte strobes are honored.

## Programming Sequence

1. Verify `IP_ID`, `IP_VERSION`, and capability ABI 2.
2. With `CTRL.ENABLE=0`, configure fault policy and the two operators.
3. Configure timer and channel shadow registers. A channel must reference an
   enabled timer and its phase plus duty must not exceed the timer period.
4. Issue `COMMAND.UPDATE`, then enable the module. Later updates commit under
   each timer's selected load policy.
5. Enable desired interrupt sources. Clear sticky state using W1C writes.
6. For capture, disable capture, program divider and channel controls, then
   write `CAPTURE_CTRL.ENABLE|CLEAR`.

Safety-critical setup may write `SAFETY_LOCK`; fault policy and operator
configuration then remain immutable until reset. `COMMAND.STOP_ALL` disables
all timer activity through the core command path.

## Global Registers

| Offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x000` | `CTRL` | RW | Module enable and debug-freeze enable. |
| `0x004` | `STATUS` | RO | Module, timer/channel, fault, lock, and update state. |
| `0x008` | `COMMAND` | WO | Update, software sync, fault test, and stop-all pulses. |
| `0x00C` | `SAFETY_LOCK` | RW1S | One-way fault/operator policy lock. |
| `0x010` | `FAULT_CTRL` | RW | Enable, polarity, one-shot mode, and filter count. |
| `0x014` | `FAULT_SAFE` | RW | Two-bit low/high/high-Z safe state for each output. |
| `0x018` | `FAULT_STATUS` | RO | Raw, synchronized, filtered, latched, and active state. |
| `0x01C` | `FAULT_CLEAR` | WO | Clear a one-shot fault latch. |
| `0x020` | `INTR_STATE` | RO/W1C | Sticky 15-source interrupt state. |
| `0x024` | `INTR_ENABLE` | RW | Interrupt source mask. |
| `0x028` | `INTR_TEST` | WO | Software-set interrupt sources. |
| `0x02C` | `OUTPUT_STATUS` | RO | Output value, enable, dead-time, and carrier observations. |
| `0x030` | `CLOCK_HZ` | RO | Integration peripheral-clock frequency. |
| `0x0F4` | `IP_ID` | RO | `0x50574D32`, ASCII-like `PWM2`. |
| `0x0F8` | `IP_VERSION` | RO | `0x00020000`, version 2.0.0. |
| `0x0FC` | `CAPABILITY` | RO | ABI, resource counts, and feature bitmap. |

Interrupt bits 0-5 are timer zero/period/update events, bits 6-9 are fade done,
bit 10 is fault, bits 11-12 are capture/watermark, and bits 13-14 are capture
FIFO overflow.

## Timer Blocks

Timer `n` is at `0x100 + n * 0x40`, for `n=0..1`.

| Local offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | Enable, count mode, load mode, and sync enable. |
| `0x04` | `DIVIDER` | RW | 24-bit Q16.8 divider, minimum `0x100`. |
| `0x08` | `PERIOD` | RW | 24-bit period, minimum 2. |
| `0x0C` | `PHASE` | RW | 24-bit reload phase, less than period. |
| `0x10` | `COUNTER` | RO | Live counter. |
| `0x14` | `ACTIVE_DIVIDER` | RO | Committed divider. |
| `0x18` | `ACTIVE_PERIOD` | RO | Committed period. |
| `0x1C` | `STATUS` | RO | Enabled, running, pending, direction, and events. |

Count mode is up, down, or up/down. Load mode is zero, period, zero-or-sync, or
sync. Timer 0 and timer 1 can be selected independently by channels.

## Channel Blocks

Channel `n` is at `0x200 + n * 0x40`, for `n=0..3`.

| Local offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | Enable, timer select, and inversion. |
| `0x04` | `PHASE` | RW | Shadow phase. |
| `0x08` | `DUTY` | RW | Shadow duty. |
| `0x0C` | `ACTION` | RW | Eight packed two-bit event actions. |
| `0x10` | `FORCE` | RW | Force enable and value. |
| `0x14` | `FADE_CTRL` | RW/WO | Start/pause/resume/stop, gamma mode, segment count. |
| `0x18` | `FADE_TARGET` | RW | Linear fade target. |
| `0x1C` | `FADE_STEP` | RW | Duty delta per fade interval. |
| `0x20` | `FADE_INTERVAL` | RW | Timer periods between steps. |
| `0x24` | `FADE_STATUS` | RO | Live output, fade, pending, and segment status. |
| `0x28` | `ACTIVE_PHASE` | RO | Committed phase. |
| `0x2C` | `ACTIVE_DUTY` | RO | Committed/current fade duty. |
| `0x30` | `GAMMA_INDEX` | RW | Selected segment index, 0-7. |
| `0x34` | `GAMMA_TARGET` | RW | Selected segment target. |
| `0x38` | `GAMMA_STEP` | RW | Selected segment step. |
| `0x3C` | `GAMMA_INTERVAL` | RW | Selected segment interval. |

`ACTION` assigns bits `[1:0]` to zero, `[3:2]` to period, `[5:4]` to
phase-up, `[7:6]` to duty-up, `[9:8]` to phase-down, `[11:10]` to duty-down,
`[13:12]` to sync, and `[15:14]` to fade-done. Each field selects hold, low,
high, or toggle behavior.

## Operator Blocks

Operator `n` is at `0x300 + n * 0x40`, for `n=0..1`.

| Local offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `CTRL` | RW | Complementary and carrier enables. |
| `0x04` | `DEADTIME` | RW | Falling `[31:16]`, rising `[15:0]` clock cycles. |
| `0x08` | `CARRIER` | RW | Period, duty, and inversion. |
| `0x0C` | `STATUS` | RO | Raw, dead-time, and carrier output observations. |

Operator registers can change only while the module is disabled and safety is
unlocked. In complementary mode, dead time guarantees outputs in one operator
are never simultaneously high.

## Capture Registers

| Offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x400` | `CAPTURE_CTRL` | RW/WO | Enable and FIFO/counter clear pulse. |
| `0x404` | `CAPTURE_DIVIDER` | RW | 24-bit Q16.8 timestamp divider. |
| `0x408` | `CAPTURE_COUNTER` | RO | Live 32-bit timestamp counter. |
| `0x40C` | `CAPTURE_STATUS` | RO | Enable, empty/full, and watermark summary. |
| `0x410/0x420` | `CAPTUREn_CTRL` | RW | Enable, edges, filter, and watermark. |
| `0x414/0x424` | `CAPTUREn_STATUS` | RO | FIFO level, empty/full, and watermark. |
| `0x418/0x428` | `CAPTUREn_DATA` | RO-pop | Oldest timestamp; empty read errors. |

Capture controls may change only while capture is disabled. A watermark value
of zero behaves as one. FIFO overflow is sticky through interrupt state.
