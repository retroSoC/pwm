#!/usr/bin/env python3
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# SPDX-License-Identifier: MulanPSL-2.0

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def sv_definitions(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = r"^`define PWM_([A-Z0-9_]+)\s+(?:8|12|32)'h([0-9A-Fa-f_]+)$"
    for match in re.finditer(pattern, path.read_text(encoding="utf-8"), re.MULTILINE):
        values[match.group(1)] = int(match.group(2).replace("_", ""), 16)
    return values


def c_definitions(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = r"^#define PWM_([A-Z0-9_]+)\s+UINT32_C\(0x([0-9A-Fa-f]+)\)$"
    for match in re.finditer(pattern, path.read_text(encoding="utf-8"), re.MULTILINE):
        values[match.group(1)] = int(match.group(2), 16)
    return values


def main() -> int:
    rtl = sv_definitions(ROOT / "rtl" / "pwm_define.svh")
    c_header = c_definitions(ROOT / "sw" / "include" / "pwm_regs.h")
    rtl_offsets = {key: value for key, value in rtl.items() if key.endswith("_OFFSET")}
    c_offsets = {key: value for key, value in c_header.items() if key.endswith("_OFFSET")}
    required_scalars = {
        "CTRL_VALID_MASK",
        "COMMAND_VALID_MASK",
        "FAULT_CTRL_VALID_MASK",
        "FAULT_SAFE_VALID_MASK",
        "TIMER_CTRL_VALID_MASK",
        "TIMER_DIVIDER_VALID_MASK",
        "TIMER_PERIOD_VALID_MASK",
        "CHANNEL_CTRL_VALID_MASK",
        "CHANNEL_ACTION_VALID_MASK",
        "FADE_CTRL_VALID_MASK",
        "OPERATOR_CTRL_VALID_MASK",
        "CAPTURE_CTRL_VALID_MASK",
        "CAPTURE_CH_VALID_MASK",
        "INTR_VALID_MASK",
        "IP_ID_VALUE",
        "IP_VERSION_VALUE",
        "CAPABILITY_FEATURES",
    }

    if rtl_offsets != c_offsets:
        raise SystemExit(f"register offsets differ: RTL={rtl_offsets}, C={c_offsets}")
    mismatched = sorted(key for key in required_scalars if rtl.get(key) != c_header.get(key))
    if mismatched:
        raise SystemExit(f"register scalar definitions differ: {mismatched}")
    print(f"register parity valid: {len(rtl_offsets)} offsets, {len(required_scalars)} scalars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
