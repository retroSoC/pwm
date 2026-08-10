// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

package pwm_pkg;

  typedef enum logic [1:0] {
    PWM_COUNT_UP      = 2'd0,
    PWM_COUNT_DOWN    = 2'd1,
    PWM_COUNT_UP_DOWN = 2'd2
  } pwm_count_mode_e;

  typedef enum logic [1:0] {
    PWM_LOAD_ZERO      = 2'd0,
    PWM_LOAD_PERIOD    = 2'd1,
    PWM_LOAD_ZERO_SYNC = 2'd2,
    PWM_LOAD_SYNC      = 2'd3
  } pwm_load_mode_e;

  typedef enum logic [1:0] {
    PWM_OUTPUT_LOW   = 2'd0,
    PWM_OUTPUT_HIGH  = 2'd1,
    PWM_OUTPUT_HIGHZ = 2'd2,
    PWM_OUTPUT_SAFE  = 2'd3
  } pwm_safe_state_e;

endpackage
