/* Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn> */
/* SPDX-License-Identifier: MulanPSL-2.0 */

#ifndef PWM_H
#define PWM_H

#include <stdbool.h>
#include <stdint.h>

#include "pwm_regs.h"

typedef enum {
    PWM_STATUS_OK = 0,
    PWM_STATUS_INVALID_ARGUMENT = -1,
    PWM_STATUS_TIMEOUT = -2,
    PWM_STATUS_BUSY = -3,
    PWM_STATUS_EMPTY = -4,
    PWM_STATUS_LOCKED = -5,
    PWM_STATUS_INCOMPATIBLE = -6
} pwm_status_t;

typedef enum {
    PWM_COUNT_MODE_UP = 0,
    PWM_COUNT_MODE_DOWN = 1,
    PWM_COUNT_MODE_UP_DOWN = 2
} pwm_count_mode_t;

typedef enum {
    PWM_LOAD_ON_ZERO = 0,
    PWM_LOAD_ON_PERIOD = 1,
    PWM_LOAD_ON_ZERO_OR_SYNC = 2,
    PWM_LOAD_ON_SYNC = 3
} pwm_load_mode_t;

typedef enum { PWM_SAFE_LOW = 0, PWM_SAFE_HIGH = 1, PWM_SAFE_HIGH_Z = 2 } pwm_safe_state_t;

typedef struct {
    uint32_t divider_q16_8;
    uint32_t period;
    uint32_t phase;
    pwm_count_mode_t count_mode;
    pwm_load_mode_t load_mode;
    bool sync_enable;
    bool enable;
} pwm_timer_config_t;

typedef struct {
    uint32_t phase;
    uint32_t duty;
    uint16_t action;
    uint8_t timer;
    bool invert;
    bool enable;
} pwm_channel_config_t;

typedef struct {
    uint16_t rising_deadtime;
    uint16_t falling_deadtime;
    uint8_t carrier_period;
    uint8_t carrier_duty;
    bool carrier_invert;
    bool complementary;
    bool carrier_enable;
} pwm_operator_config_t;

typedef struct {
    uint32_t target;
    uint32_t step;
    uint16_t interval;
} pwm_fade_segment_t;

typedef struct {
    uint8_t filter_cycles;
    pwm_safe_state_t safe_state[PWM_CHANNEL_COUNT];
    bool active_high;
    bool one_shot;
    bool enable;
    bool lock;
} pwm_fault_config_t;

typedef struct {
    uint32_t divider_q16_8;
    uint8_t filter_cycles[PWM_CAPTURE_COUNT];
    uint8_t watermark[PWM_CAPTURE_COUNT];
    bool rising_edge[PWM_CAPTURE_COUNT];
    bool falling_edge[PWM_CAPTURE_COUNT];
    bool enable[PWM_CAPTURE_COUNT];
} pwm_capture_config_t;

typedef struct {
    uint32_t status;
    uint32_t fault_status;
    uint32_t interrupt_state;
    uint32_t output_status;
} pwm_snapshot_t;

pwm_status_t pwm_probe(uintptr_t base);
pwm_status_t pwm_timer_configure(uintptr_t base, uint8_t timer, const pwm_timer_config_t *config);
pwm_status_t pwm_channel_configure(uintptr_t base, uint8_t channel,
                                   const pwm_channel_config_t *config);
pwm_status_t pwm_operator_configure(uintptr_t base, uint8_t operator_id,
                                    const pwm_operator_config_t *config);
pwm_status_t pwm_fault_configure(uintptr_t base, const pwm_fault_config_t *config);
pwm_status_t pwm_capture_configure(uintptr_t base, const pwm_capture_config_t *config);
pwm_status_t pwm_enable(uintptr_t base, bool debug_freeze);
pwm_status_t pwm_disable(uintptr_t base);
pwm_status_t pwm_apply_update(uintptr_t base, uint32_t timeout);
pwm_status_t pwm_software_sync(uintptr_t base);
pwm_status_t pwm_set_duty(uintptr_t base, uint8_t channel, uint32_t duty, uint32_t timeout);
pwm_status_t pwm_fade_configure(uintptr_t base, uint8_t channel, const pwm_fade_segment_t *segment);
pwm_status_t pwm_fade_start(uintptr_t base, uint8_t channel);
pwm_status_t pwm_fade_pause(uintptr_t base, uint8_t channel);
pwm_status_t pwm_fade_resume(uintptr_t base, uint8_t channel);
pwm_status_t pwm_fade_stop(uintptr_t base, uint8_t channel);
pwm_status_t pwm_gamma_program(uintptr_t base, uint8_t channel, const pwm_fade_segment_t *segments,
                               uint8_t count);
pwm_status_t pwm_gamma_start(uintptr_t base, uint8_t channel, uint8_t count);
pwm_status_t pwm_fault_clear(uintptr_t base);
pwm_status_t pwm_fault_test(uintptr_t base);
pwm_status_t pwm_capture_read(uintptr_t base, uint8_t channel, uint32_t *timestamp,
                              uint32_t timeout);
pwm_status_t pwm_interrupt_enable(uintptr_t base, uint32_t mask);
pwm_status_t pwm_interrupt_clear(uintptr_t base, uint32_t mask);
pwm_status_t pwm_interrupt_test(uintptr_t base, uint32_t mask);
pwm_status_t pwm_get_status(uintptr_t base, pwm_snapshot_t *snapshot);

#endif
