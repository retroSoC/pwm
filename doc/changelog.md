# Changelog

## Unreleased

- Added opt-in runtime peripheral-clock reporting with `UseRuntimeClockHz`
  and `pclk_hz_i`; static `PCLK_HZ` behavior remains the default. Register
  offsets, discovery values, HAL and PWM timing logic are unchanged.
- Added dual-simulator APB wrapper coverage for 24/48/60 MHz reports,
  static compatibility, read-only access, peripheral reset and PWM waveform
  conservation, plus synthesis checks of both register-bank configurations.

## 2.0.0

- Replaced the legacy single-counter register ABI with strict V2 discovery and
  access behavior.
- Added two Q16.8-divided 24-bit timers and four shadowed action channels.
- Added linear/gamma fade, complementary output, dead time, carrier modulation,
  timer synchronization, fault handling, and timestamp capture FIFOs.
- Added Common structural components, freestanding C software, register parity,
  open-source simulation, synthesis, formal verification, CI, and delivery
  documentation.
