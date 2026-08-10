/* Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn> */
/* SPDX-License-Identifier: MulanPSL-2.0 */

#include "pwm.h"

#include <stddef.h>

static volatile uint32_t *pwm_register(uintptr_t base, uint32_t offset) {
    return (volatile uint32_t *)(base + (uintptr_t)offset);
}

static uint32_t pwm_read_register(uintptr_t base, uint32_t offset) {
    return *pwm_register(base, offset);
}

static void pwm_write_register(uintptr_t base, uint32_t offset, uint32_t value) {
    *pwm_register(base, offset) = value;
}

static bool pwm_channel_valid(uint8_t channel) { return (uint32_t)channel < PWM_CHANNEL_COUNT; }

static bool pwm_timer_valid(uint8_t timer) { return (uint32_t)timer < PWM_TIMER_COUNT; }

static bool pwm_operator_valid(uint8_t operator_id) {
    return (uint32_t)operator_id < PWM_OPERATOR_COUNT;
}

static bool pwm_interrupt_mask_valid(uint32_t mask) { return (mask & ~PWM_INTR_ALL_MASK) == 0U; }

static bool pwm_disabled(uintptr_t base) {
    return (pwm_read_register(base, PWM_CTRL_OFFSET) & PWM_CTRL_ENABLE_MASK) == 0U;
}

pwm_status_t pwm_probe(uintptr_t base) {
    uint32_t capability;

    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    if ((pwm_read_register(base, PWM_IP_ID_OFFSET) != PWM_IP_ID_VALUE) ||
        (pwm_read_register(base, PWM_IP_VERSION_OFFSET) != PWM_IP_VERSION_VALUE)) {
        return PWM_STATUS_INCOMPATIBLE;
    }
    capability = pwm_read_register(base, PWM_CAPABILITY_OFFSET);
    if (((capability & PWM_CAPABILITY_ABI_MASK) >> PWM_CAPABILITY_ABI_SHIFT) != PWM_ABI_VERSION) {
        return PWM_STATUS_INCOMPATIBLE;
    }
    return PWM_STATUS_OK;
}

pwm_status_t pwm_timer_configure(uintptr_t base, uint8_t timer, const pwm_timer_config_t *config) {
    uint32_t ctrl;

    if ((base == (uintptr_t)0U) || !pwm_timer_valid(timer) || (config == NULL) ||
        (config->divider_q16_8 < PWM_TIMER_DIVIDER_MIN) ||
        (config->divider_q16_8 > PWM_TIMER_DIVIDER_VALID_MASK) ||
        (config->period < PWM_TIMER_PERIOD_MIN) || (config->period > PWM_TIMER_PERIOD_VALID_MASK) ||
        (config->phase >= config->period) ||
        ((uint32_t)config->count_mode > (uint32_t)PWM_COUNT_MODE_UP_DOWN) ||
        ((uint32_t)config->load_mode > (uint32_t)PWM_LOAD_ON_SYNC)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }

    ctrl = ((uint32_t)config->count_mode << PWM_TIMER_CTRL_MODE_SHIFT) |
           ((uint32_t)config->load_mode << PWM_TIMER_CTRL_LOAD_SHIFT);
    if (config->enable) {
        ctrl |= PWM_TIMER_CTRL_ENABLE_MASK;
    }
    if (config->sync_enable) {
        ctrl |= PWM_TIMER_CTRL_SYNC_ENABLE_MASK;
    }

    pwm_write_register(base, PWM_TIMER_REG(timer, PWM_TIMER_CTRL_OFFSET), ctrl);
    pwm_write_register(base, PWM_TIMER_REG(timer, PWM_TIMER_DIVIDER_OFFSET), config->divider_q16_8);
    pwm_write_register(base, PWM_TIMER_REG(timer, PWM_TIMER_PERIOD_OFFSET), config->period);
    pwm_write_register(base, PWM_TIMER_REG(timer, PWM_TIMER_PHASE_OFFSET), config->phase);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_channel_configure(uintptr_t base, uint8_t channel,
                                   const pwm_channel_config_t *config) {
    uint32_t ctrl;
    uint32_t period;

    if ((base == (uintptr_t)0U) || !pwm_channel_valid(channel) || (config == NULL) ||
        !pwm_timer_valid(config->timer)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    period = pwm_read_register(base, PWM_TIMER_REG(config->timer, PWM_TIMER_PERIOD_OFFSET));
    if ((period < PWM_TIMER_PERIOD_MIN) || (config->phase >= period) ||
        (config->duty > (period - config->phase))) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }

    ctrl = config->enable ? PWM_CHANNEL_CTRL_ENABLE_MASK : 0U;
    if (config->timer != 0U) {
        ctrl |= PWM_CHANNEL_CTRL_TIMER_MASK;
    }
    if (config->invert) {
        ctrl |= PWM_CHANNEL_CTRL_INVERT_MASK;
    }
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_CTRL_OFFSET), ctrl);
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_PHASE_OFFSET), config->phase);
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_DUTY_OFFSET), config->duty);
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_ACTION_OFFSET),
                       (uint32_t)config->action);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_operator_configure(uintptr_t base, uint8_t operator_id,
                                    const pwm_operator_config_t *config) {
    uint32_t ctrl;
    uint32_t deadtime;
    uint32_t carrier;

    if ((base == (uintptr_t)0U) || !pwm_operator_valid(operator_id) || (config == NULL)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    if (!pwm_disabled(base)) {
        return PWM_STATUS_BUSY;
    }
    if (config->carrier_enable &&
        ((config->carrier_period < 2U) || (config->carrier_duty > config->carrier_period))) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }

    ctrl = config->complementary ? PWM_OPERATOR_CTRL_COMPLEMENT_MASK : 0U;
    if (config->carrier_enable) {
        ctrl |= PWM_OPERATOR_CTRL_CARRIER_MASK;
    }
    deadtime = ((uint32_t)config->falling_deadtime << 16) | config->rising_deadtime;
    carrier = (uint32_t)config->carrier_period | ((uint32_t)config->carrier_duty << 8);
    if (config->carrier_invert) {
        carrier |= UINT32_C(0x00010000);
    }
    pwm_write_register(base, PWM_OPERATOR_REG(operator_id, PWM_OPERATOR_CTRL_OFFSET), ctrl);
    pwm_write_register(base, PWM_OPERATOR_REG(operator_id, PWM_OPERATOR_DEADTIME_OFFSET), deadtime);
    pwm_write_register(base, PWM_OPERATOR_REG(operator_id, PWM_OPERATOR_CARRIER_OFFSET), carrier);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_fault_configure(uintptr_t base, const pwm_fault_config_t *config) {
    uint32_t ctrl = 0U;
    uint32_t safe = 0U;

    if ((base == (uintptr_t)0U) || (config == NULL) || (config->filter_cycles > 15U)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    if (!pwm_disabled(base)) {
        return PWM_STATUS_BUSY;
    }
    if ((pwm_read_register(base, PWM_SAFETY_LOCK_OFFSET) & PWM_SAFETY_LOCK_MASK) != 0U) {
        return PWM_STATUS_LOCKED;
    }
    for (uint32_t channel = 0U; channel < PWM_CHANNEL_COUNT; ++channel) {
        if ((uint32_t)config->safe_state[channel] > (uint32_t)PWM_SAFE_HIGH_Z) {
            return PWM_STATUS_INVALID_ARGUMENT;
        }
        safe |= (uint32_t)config->safe_state[channel] << (channel * 2U);
    }
    if (config->enable) {
        ctrl |= PWM_FAULT_CTRL_ENABLE_MASK;
    }
    if (config->active_high) {
        ctrl |= PWM_FAULT_CTRL_ACTIVE_HIGH_MASK;
    }
    if (config->one_shot) {
        ctrl |= PWM_FAULT_CTRL_ONE_SHOT_MASK;
    }
    ctrl |= (uint32_t)config->filter_cycles << PWM_FAULT_CTRL_FILTER_SHIFT;
    pwm_write_register(base, PWM_FAULT_CTRL_OFFSET, ctrl);
    pwm_write_register(base, PWM_FAULT_SAFE_OFFSET, safe);
    if (config->lock) {
        pwm_write_register(base, PWM_SAFETY_LOCK_OFFSET, PWM_SAFETY_LOCK_MASK);
    }
    return PWM_STATUS_OK;
}

pwm_status_t pwm_capture_configure(uintptr_t base, const pwm_capture_config_t *config) {
    uint32_t channel_ctrl;

    if ((base == (uintptr_t)0U) || (config == NULL) ||
        (config->divider_q16_8 < PWM_TIMER_DIVIDER_MIN) ||
        (config->divider_q16_8 > PWM_TIMER_DIVIDER_VALID_MASK)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_CAPTURE_CTRL_OFFSET, 0U);
    pwm_write_register(base, PWM_CAPTURE_DIVIDER_OFFSET, config->divider_q16_8);
    for (uint32_t channel = 0U; channel < PWM_CAPTURE_COUNT; ++channel) {
        if ((config->filter_cycles[channel] > 15U) ||
            (config->watermark[channel] > PWM_CAPTURE_FIFO_DEPTH) ||
            (config->enable[channel] && !config->rising_edge[channel] &&
             !config->falling_edge[channel])) {
            return PWM_STATUS_INVALID_ARGUMENT;
        }
        channel_ctrl = config->enable[channel] ? PWM_CAPTURE_CH_ENABLE_MASK : 0U;
        if (config->rising_edge[channel]) {
            channel_ctrl |= PWM_CAPTURE_CH_RISE_MASK;
        }
        if (config->falling_edge[channel]) {
            channel_ctrl |= PWM_CAPTURE_CH_FALL_MASK;
        }
        channel_ctrl |= (uint32_t)config->filter_cycles[channel] << PWM_CAPTURE_CH_FILTER_SHIFT;
        channel_ctrl |= (uint32_t)config->watermark[channel] << PWM_CAPTURE_CH_WATERMARK_SHIFT;
        pwm_write_register(base,
                           channel == 0U ? PWM_CAPTURE0_CTRL_OFFSET : PWM_CAPTURE1_CTRL_OFFSET,
                           channel_ctrl);
    }
    pwm_write_register(base, PWM_CAPTURE_CTRL_OFFSET,
                       PWM_CAPTURE_CTRL_ENABLE_MASK | PWM_CAPTURE_CTRL_CLEAR_MASK);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_enable(uintptr_t base, bool debug_freeze) {
    pwm_status_t status = pwm_probe(base);
    uint32_t ctrl;

    if (status != PWM_STATUS_OK) {
        return status;
    }
    ctrl = PWM_CTRL_ENABLE_MASK;
    if (debug_freeze) {
        ctrl |= PWM_CTRL_DEBUG_FREEZE_MASK;
    }
    pwm_write_register(base, PWM_CTRL_OFFSET, ctrl);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_disable(uintptr_t base) {
    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_CTRL_OFFSET, 0U);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_apply_update(uintptr_t base, uint32_t timeout) {
    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_COMMAND_OFFSET, PWM_COMMAND_UPDATE_MASK);
    while (timeout != 0U) {
        if ((pwm_read_register(base, PWM_STATUS_OFFSET) & PWM_STATUS_UPDATE_PENDING_MASK) == 0U) {
            return PWM_STATUS_OK;
        }
        --timeout;
    }
    return PWM_STATUS_TIMEOUT;
}

pwm_status_t pwm_software_sync(uintptr_t base) {
    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_COMMAND_OFFSET, PWM_COMMAND_SYNC_MASK);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_set_duty(uintptr_t base, uint8_t channel, uint32_t duty, uint32_t timeout) {
    uint32_t ctrl;
    uint32_t period;
    uint32_t phase;
    uint8_t timer;

    if ((base == (uintptr_t)0U) || !pwm_channel_valid(channel)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    ctrl = pwm_read_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_CTRL_OFFSET));
    timer = (ctrl & PWM_CHANNEL_CTRL_TIMER_MASK) != 0U ? 1U : 0U;
    period = pwm_read_register(base, PWM_TIMER_REG(timer, PWM_TIMER_PERIOD_OFFSET));
    phase = pwm_read_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_PHASE_OFFSET));
    if ((phase >= period) || (duty > (period - phase))) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_DUTY_OFFSET), duty);
    return pwm_apply_update(base, timeout);
}

pwm_status_t pwm_fade_configure(uintptr_t base, uint8_t channel,
                                const pwm_fade_segment_t *segment) {
    if ((base == (uintptr_t)0U) || !pwm_channel_valid(channel) || (segment == NULL) ||
        (segment->step == 0U) || (segment->step > PWM_FADE_STEP_VALID_MASK)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_FADE_TARGET_OFFSET),
                       segment->target);
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_FADE_STEP_OFFSET), segment->step);
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_FADE_INTERVAL_OFFSET),
                       (uint32_t)segment->interval);
    return PWM_STATUS_OK;
}

static pwm_status_t pwm_fade_command(uintptr_t base, uint8_t channel, uint32_t command) {
    if ((base == (uintptr_t)0U) || !pwm_channel_valid(channel)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_FADE_CTRL_OFFSET), command);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_fade_start(uintptr_t base, uint8_t channel) {
    return pwm_fade_command(base, channel, PWM_FADE_CTRL_START_MASK);
}

pwm_status_t pwm_fade_pause(uintptr_t base, uint8_t channel) {
    return pwm_fade_command(base, channel, PWM_FADE_CTRL_PAUSE_MASK);
}

pwm_status_t pwm_fade_resume(uintptr_t base, uint8_t channel) {
    return pwm_fade_command(base, channel, PWM_FADE_CTRL_RESUME_MASK);
}

pwm_status_t pwm_fade_stop(uintptr_t base, uint8_t channel) {
    return pwm_fade_command(base, channel, PWM_FADE_CTRL_STOP_MASK);
}

pwm_status_t pwm_gamma_program(uintptr_t base, uint8_t channel, const pwm_fade_segment_t *segments,
                               uint8_t count) {
    if ((base == (uintptr_t)0U) || !pwm_channel_valid(channel) || (segments == NULL) ||
        (count == 0U) || ((uint32_t)count > PWM_GAMMA_SEGMENT_COUNT)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0U; index < (uint32_t)count; ++index) {
        if ((segments[index].step == 0U) || (segments[index].step > PWM_FADE_STEP_VALID_MASK)) {
            return PWM_STATUS_INVALID_ARGUMENT;
        }
        pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_GAMMA_INDEX_OFFSET), index);
        pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_GAMMA_TARGET_OFFSET),
                           segments[index].target);
        pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_GAMMA_STEP_OFFSET),
                           segments[index].step);
        pwm_write_register(base, PWM_CHANNEL_REG(channel, PWM_CHANNEL_GAMMA_INTERVAL_OFFSET),
                           (uint32_t)segments[index].interval);
    }
    return PWM_STATUS_OK;
}

pwm_status_t pwm_gamma_start(uintptr_t base, uint8_t channel, uint8_t count) {
    uint32_t command;

    if ((count == 0U) || ((uint32_t)count > PWM_GAMMA_SEGMENT_COUNT)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    command = PWM_FADE_CTRL_START_MASK | PWM_FADE_CTRL_GAMMA_MASK |
              ((uint32_t)count << PWM_FADE_CTRL_SEGMENTS_SHIFT);
    return pwm_fade_command(base, channel, command);
}

pwm_status_t pwm_fault_clear(uintptr_t base) {
    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_FAULT_CLEAR_OFFSET, PWM_FAULT_CLEAR_MASK);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_fault_test(uintptr_t base) {
    if (base == (uintptr_t)0U) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_COMMAND_OFFSET, PWM_COMMAND_FAULT_TEST_MASK);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_capture_read(uintptr_t base, uint8_t channel, uint32_t *timestamp,
                              uint32_t timeout) {
    uint32_t status_offset;
    uint32_t data_offset;

    if ((base == (uintptr_t)0U) || ((uint32_t)channel >= PWM_CAPTURE_COUNT) ||
        (timestamp == NULL)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    status_offset = channel == 0U ? PWM_CAPTURE0_STATUS_OFFSET : PWM_CAPTURE1_STATUS_OFFSET;
    data_offset = channel == 0U ? PWM_CAPTURE0_DATA_OFFSET : PWM_CAPTURE1_DATA_OFFSET;
    while (timeout != 0U) {
        if ((pwm_read_register(base, status_offset) & PWM_CAPTURE_STATUS_EMPTY_MASK) == 0U) {
            *timestamp = pwm_read_register(base, data_offset);
            return PWM_STATUS_OK;
        }
        --timeout;
    }
    return PWM_STATUS_TIMEOUT;
}

pwm_status_t pwm_interrupt_enable(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || !pwm_interrupt_mask_valid(mask)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_INTR_ENABLE_OFFSET, mask);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_interrupt_clear(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || !pwm_interrupt_mask_valid(mask)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_INTR_STATE_OFFSET, mask);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_interrupt_test(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || !pwm_interrupt_mask_valid(mask)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    pwm_write_register(base, PWM_INTR_TEST_OFFSET, mask);
    return PWM_STATUS_OK;
}

pwm_status_t pwm_get_status(uintptr_t base, pwm_snapshot_t *snapshot) {
    if ((base == (uintptr_t)0U) || (snapshot == NULL)) {
        return PWM_STATUS_INVALID_ARGUMENT;
    }
    snapshot->status = pwm_read_register(base, PWM_STATUS_OFFSET);
    snapshot->fault_status = pwm_read_register(base, PWM_FAULT_STATUS_OFFSET);
    snapshot->interrupt_state = pwm_read_register(base, PWM_INTR_STATE_OFFSET);
    snapshot->output_status = pwm_read_register(base, PWM_OUTPUT_STATUS_OFFSET);
    return PWM_STATUS_OK;
}
