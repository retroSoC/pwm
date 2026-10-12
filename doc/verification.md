# PWM V2 Verification Guide

The standalone quality flow provides complementary evidence:

| Gate | Scope |
| --- | --- |
| `make format-check` | Verible SV/SVH and clang-format C/H policy. |
| `make register-check` | Exact hand-written SVH/C offset and scalar parity. |
| `make lint` | Warning-clean APB wrapper lint with Verilator. |
| `make test-iverilog` | Scalar register/core smoke test for portable SV support. |
| `make test-verilator` | Native interfaces, APB errors, PWM, fault, fade, dead time, and capture. |
| `make test-host` | Driver input validation, discovery, configuration, and commands. |
| `make test-clock-report-iverilog test-clock-report-verilator` | Production APB wrapper in static/runtime modes, 24/48/60/24 MHz reports, ignored static input, read-only errors, reset and unchanged PWM duty. Included in `make test`. |
| `make synth` | `sv2v` lowering and Yosys structural checks of `pwm_core` and both static/runtime `pwm_reg` configurations. |
| `make formal` | Bounded and induction proof of dead-time output exclusion. |

The formal harness proves that the dead-time stage never drives both sides of a
complementary pair high and checks representative rise/fall delays. It is not a
complete proof of the APB register bank, timer arithmetic, capture FIFO, or
fault path. Those remain dynamic and integration-level verification targets.

Clock-report tests emulate the product's synchronous rate-commit register.
They do not prove the consuming RCU's CDC, clock switching, quiescence or
physical operating rates. Runtime frequency validity and atomic updates are
product integration obligations described in `integration.md`.

Before release, review all assertions and warnings, repeat the standalone flow
with the locked Common revision, and run the consuming SoC's RTL, synthesis,
netlist, timing, warning, and metric flows.
