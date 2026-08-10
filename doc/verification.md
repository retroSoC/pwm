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
| `make synth` | `sv2v` lowering and Yosys structural check of `pwm_core`. |
| `make formal` | Bounded and induction proof of dead-time output exclusion. |

The formal harness proves that the dead-time stage never drives both sides of a
complementary pair high and checks representative rise/fall delays. It is not a
complete proof of the APB register bank, timer arithmetic, capture FIFO, or
fault path. Those remain dynamic and integration-level verification targets.

Before release, review all assertions and warnings, repeat the standalone flow
with the locked Common revision, and run the consuming SoC's RTL, synthesis,
netlist, timing, warning, and metric flows.
