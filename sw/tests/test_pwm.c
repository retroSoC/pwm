/* Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn> */
/* SPDX-License-Identifier: MulanPSL-2.0 */

#include "pwm.h"

#include <assert.h>
#include <stdint.h>

int main(void) {
    uint32_t registers[272] = {0U};
    const uintptr_t base = (uintptr_t)&registers[0];
    const pwm_timer_config_t timer = {
        .divider_q16_8 = UINT32_C(0x100),
        .period = 1000U,
        .phase = 0U,
        .count_mode = PWM_COUNT_MODE_UP,
        .load_mode = PWM_LOAD_ON_ZERO,
        .sync_enable = true,
        .enable = true,
    };
    const pwm_channel_config_t channel = {
        .phase = 0U,
        .duty = 500U,
        .action = UINT16_C(0x0021),
        .timer = 0U,
        .invert = false,
        .enable = true,
    };
    const pwm_operator_config_t operator_config = {
        .rising_deadtime = 3U,
        .falling_deadtime = 4U,
        .carrier_period = 8U,
        .carrier_duty = 4U,
        .carrier_invert = false,
        .complementary = true,
        .carrier_enable = true,
    };
    pwm_snapshot_t snapshot;

    registers[PWM_IP_ID_OFFSET / 4U] = PWM_IP_ID_VALUE;
    registers[PWM_IP_VERSION_OFFSET / 4U] = PWM_IP_VERSION_VALUE;
    registers[PWM_CAPABILITY_OFFSET / 4U] = PWM_ABI_VERSION << PWM_CAPABILITY_ABI_SHIFT;

    assert(pwm_probe(base) == PWM_STATUS_OK);
    assert(pwm_timer_configure(base, 0U, &timer) == PWM_STATUS_OK);
    assert(registers[PWM_TIMER_REG(0U, PWM_TIMER_PERIOD_OFFSET) / 4U] == 1000U);
    assert(pwm_channel_configure(base, 0U, &channel) == PWM_STATUS_OK);
    assert(registers[PWM_CHANNEL_REG(0U, PWM_CHANNEL_DUTY_OFFSET) / 4U] == 500U);
    assert(pwm_operator_configure(base, 0U, &operator_config) == PWM_STATUS_OK);
    assert(registers[PWM_OPERATOR_REG(0U, PWM_OPERATOR_DEADTIME_OFFSET) / 4U] ==
           UINT32_C(0x00040003));
    assert(pwm_enable(base, true) == PWM_STATUS_OK);
    assert(registers[PWM_CTRL_OFFSET / 4U] == (PWM_CTRL_ENABLE_MASK | PWM_CTRL_DEBUG_FREEZE_MASK));
    assert(pwm_operator_configure(base, 0U, &operator_config) == PWM_STATUS_BUSY);
    assert(pwm_set_duty(base, 0U, 250U, 1U) == PWM_STATUS_OK);
    assert(pwm_interrupt_enable(base, UINT32_C(0x8000)) == PWM_STATUS_INVALID_ARGUMENT);
    assert(pwm_capture_read(base, 2U, &registers[0], 1U) == PWM_STATUS_INVALID_ARGUMENT);
    assert(pwm_get_status(base, &snapshot) == PWM_STATUS_OK);
    assert(pwm_probe((uintptr_t)0U) == PWM_STATUS_INVALID_ARGUMENT);

    return 0;
}
