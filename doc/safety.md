# PWM V2 Safety and Security Notes

PWM V2 provides one-shot and cycle-by-cycle fault response, raw fault output
gating, filtered status, software fault injection, per-output safe states, a
one-way policy lock, and complementary-output dead-time exclusion. These
mechanisms reduce accidental hazards but do not establish a functional-safety
integrity level.

Known limitations include a single fault input, no redundant comparators, no
register parity/ECC, no independent safety clock, no fault-line pulse stretcher,
and no lifecycle authentication around debug freeze. A pulse shorter than the
physical asynchronous path/pad response can be missed by synchronized status.
Software fault injection tests logic after the APB register bank; it does not
test the external board path.

Safety-oriented products should add an independent shutdown path, fault-line
diagnostics, protected configuration, output feedback/capture, clock monitors,
technology-specific fault timing evidence, FMEDA, and a product safety manual.
The integrator owns gate-level proof that both complementary outputs cannot be
high simultaneously under reset, clock loss, X propagation, and pad behavior.
