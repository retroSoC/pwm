# APB4 PWM Controller

`pwm` is a synthesizable APB4 pulse-width-modulation controller for LED and
motor-control workloads. Version 2 replaces the legacy single-counter ABI with
a resource-scaled LEDC/MCPWM architecture:

- two 24-bit Q16.8-divided timers with up, down, and center-aligned modes;
- four output channels with shadowed phase, duty, and action tables;
- linear fades and eight-segment gamma fades;
- two operators with complementary outputs, dead time, and carrier modulation;
- filtered one-shot/cycle-by-cycle fault handling and per-output safe states;
- external/software/peer synchronization;
- two filtered edge-capture inputs with four-entry FIFOs;
- sticky interrupt state, interrupt test, APB errors, and a one-way safety lock.

The controller generates clock enables rather than internal clocks. Common
`dffr`, `cdc_sync`, and `fifo` components implement state, asynchronous input
synchronization, and capture queues.

## Repository Layout

- `rtl/`: APB wrapper, interface, register bank, timers, channels, operators,
  fault handling, and capture logic.
- `dv/unit/`: scalar Icarus test and interface-level Verilator test.
- `formal/`: SymbiYosys/Bitwuzla dead-time safety proof.
- `sw/`: freestanding V2 register definitions, driver, and host test.
- `doc/`: architecture, programming, integration, safety, and verification
  collateral.
- `config/` and `scripts/`: locked standalone dependencies and setup flow.

## Validation

Use a sibling Common checkout or set `COMMON_ROOT` explicitly:

```bash
make doctor
make format-check register-check lint
make test synth formal
```

For a clean CI-equivalent environment:

```bash
python3 scripts/setup_dependencies.py --common \
  --tool verible --tool verilator --tool sv2v --tool iverilog \
  --tool yosys --tool sby --tool bitwuzla
```

The programming model and ABI are specified in
[`doc/datasheet.md`](doc/datasheet.md). This IP is suitable for commercial SoC
integration, but it is not a certified motor-safety element.
