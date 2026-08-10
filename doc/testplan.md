# PWM V2 Test Plan

| Requirement | Icarus | Verilator | Formal | Host C |
| --- | --- | --- | --- | --- |
| Timer tick, period, and waveform | Yes | Yes | No | Configuration |
| APB alignment, access, byte strobes | Scalar subset | Yes | No | No |
| Shadow update and debug freeze | Yes | Yes | No | Timeout API |
| Linear and gamma fade | Basic | Linear | No | API validation |
| Complementary/dead-time exclusion | Yes | Yes | Proven | Configuration |
| Carrier modulation | Structural | Configuration | No | Validation |
| Raw/filtered/one-shot fault | Yes | Yes | Safe output | Configuration |
| Safety lock and fault injection | Register | Yes | No | API validation |
| Sync modes | Software | Software/peer | No | Command API |
| Capture edge/filter/FIFO/overflow | Basic | FIFO read | No | Poll API |
| Sticky IRQ, W1C, interrupt test | Basic | Yes | No | API validation |
| RTL/C register parity | Generated | Generated | Not applicable | Generated |

SoC sign-off adds pinmux tests, CDC/RDC analysis, asynchronous fault timing,
gate-level output-enable behavior, interrupt-controller routing, clock/reset
transition tests, and application-level LED/motor/capture scenarios.
