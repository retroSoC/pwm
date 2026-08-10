// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "pwm_define.svh"

module pwm_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        module_enable_i,
    input  logic        debug_freeze_i,
    input  logic        debug_halted_i,
    input  logic        update_i,
    input  logic        software_sync_i,
    input  logic        stop_all_i,
    input  logic        fault_test_i,
    input  logic        fault_clear_i,
    input  logic [31:0] fault_ctrl_i,
    input  logic [31:0] fault_safe_i,
    input  logic [31:0] timer_ctrl_i          [0:`PWM_TIMER_COUNT-1],
    input  logic [23:0] timer_divider_i       [0:`PWM_TIMER_COUNT-1],
    input  logic [23:0] timer_period_i        [0:`PWM_TIMER_COUNT-1],
    input  logic [23:0] timer_phase_i         [0:`PWM_TIMER_COUNT-1],
    input  logic [31:0] channel_ctrl_i        [0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] channel_phase_i       [0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] channel_duty_i        [0:`PWM_CHANNEL_COUNT-1],
    input  logic [15:0] channel_action_i      [0:`PWM_CHANNEL_COUNT-1],
    input  logic [ 1:0] channel_force_i       [0:`PWM_CHANNEL_COUNT-1],
    input  logic [ 4:0] channel_fade_ctrl_i   [0:`PWM_CHANNEL_COUNT-1],
    input  logic [ 3:0] channel_fade_segments_i[0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] channel_fade_target_i [0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] channel_fade_step_i   [0:`PWM_CHANNEL_COUNT-1],
    input  logic [15:0] channel_fade_interval_i[0:`PWM_CHANNEL_COUNT-1],
    input  logic [ 3:0] gamma_write_target_i,
    input  logic [ 3:0] gamma_write_step_i,
    input  logic [ 3:0] gamma_write_interval_i,
    input  logic [ 2:0] gamma_index_i         [0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] gamma_target_i        [0:`PWM_CHANNEL_COUNT-1],
    input  logic [23:0] gamma_step_i          [0:`PWM_CHANNEL_COUNT-1],
    input  logic [15:0] gamma_interval_i      [0:`PWM_CHANNEL_COUNT-1],
    output logic [23:0] gamma_target_o        [0:`PWM_CHANNEL_COUNT-1],
    output logic [23:0] gamma_step_o          [0:`PWM_CHANNEL_COUNT-1],
    output logic [15:0] gamma_interval_o      [0:`PWM_CHANNEL_COUNT-1],
    input  logic [31:0] operator_ctrl_i       [0:`PWM_OPERATOR_COUNT-1],
    input  logic [31:0] operator_deadtime_i   [0:`PWM_OPERATOR_COUNT-1],
    input  logic [31:0] operator_carrier_i    [0:`PWM_OPERATOR_COUNT-1],
    input  logic        capture_enable_i,
    input  logic        capture_clear_i,
    input  logic [23:0] capture_divider_i,
    input  logic [31:0] capture_channel_ctrl_i[0:`PWM_CAPTURE_COUNT-1],
    input  logic [ 1:0] capture_pop_i,
    input  logic        fault_i,
    input  logic        sync_i,
    input  logic [ 1:0] capture_i,
    output logic [ 3:0] pwm_o,
    output logic [ 3:0] oe_o,
    output logic [31:0] event_o,
    output logic [31:0] status_o,
    output logic [31:0] fault_status_o,
    output logic [31:0] output_status_o,
    output logic [23:0] timer_counter_o       [0:`PWM_TIMER_COUNT-1],
    output logic [23:0] timer_active_divider_o[0:`PWM_TIMER_COUNT-1],
    output logic [23:0] timer_active_period_o [0:`PWM_TIMER_COUNT-1],
    output logic [31:0] timer_status_o        [0:`PWM_TIMER_COUNT-1],
    output logic [23:0] channel_active_phase_o[0:`PWM_CHANNEL_COUNT-1],
    output logic [23:0] channel_active_duty_o [0:`PWM_CHANNEL_COUNT-1],
    output logic [31:0] channel_status_o      [0:`PWM_CHANNEL_COUNT-1],
    output logic [31:0] operator_status_o     [0:`PWM_OPERATOR_COUNT-1],
    output logic [31:0] capture_counter_o,
    output logic [31:0] capture_data_o        [0:`PWM_CAPTURE_COUNT-1],
    output logic [31:0] capture_status_o,
    output logic [31:0] capture_channel_status_o[0:`PWM_CAPTURE_COUNT-1]
    // verilog_format: on
);

  logic s_freeze;
  logic s_sync_meta, s_sync_prev_d, s_sync_prev_q, s_external_sync_pulse;
  logic s_fault_meta;
  logic s_fault_raw;
  logic s_fault_sync_active;
  logic [3:0] s_fault_filter_count_d, s_fault_filter_count_q;
  logic s_fault_filtered_d, s_fault_filtered_q;
  logic s_fault_latched_d, s_fault_latched_q;
  logic        s_fault_event;
  logic        s_fault_kill;

  logic [23:0] s_timer_period           [  0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_phase            [  0:`PWM_TIMER_COUNT-1];
  logic [ 1:0] s_timer_direction;
  logic [ 1:0] s_timer_tick;
  logic [ 1:0] s_timer_zero;
  logic [ 1:0] s_timer_zero_q;
  logic [ 1:0] s_timer_period_event;
  logic [ 1:0] s_timer_sync;
  logic [ 1:0] s_timer_update_done;
  logic [ 1:0] s_timer_update_pending;
  logic [ 1:0] s_timer_running;

  logic [ 3:0] s_channel_raw;
  logic [ 3:0] s_channel_enabled;
  logic [ 3:0] s_channel_timer_select;
  logic [ 3:0] s_fade_running;
  logic [ 3:0] s_fade_paused;
  logic [ 2:0] s_fade_segment           [0:`PWM_CHANNEL_COUNT-1];
  logic [ 3:0] s_fade_done;
  logic [ 3:0] s_channel_update_pending;

  logic [ 3:0] s_deadtime_output;
  logic [ 3:0] s_carrier_output;
  logic [ 1:0] s_capture_empty;
  logic [ 1:0] s_capture_full;
  logic [ 2:0] s_capture_level          [0:`PWM_CAPTURE_COUNT-1];
  logic [ 1:0] s_capture_event;
  logic [ 1:0] s_capture_overflow;
  logic [ 1:0] s_capture_watermark;

  assign s_freeze    = debug_freeze_i && debug_halted_i;
  assign s_fault_raw = fault_ctrl_i[0] && (fault_ctrl_i[1] ? fault_i : ~fault_i);

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_control_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  ({sync_i, fault_i}),
      .dat_o  ({s_sync_meta, s_fault_meta})
  );

  assign s_external_sync_pulse = s_sync_meta && !s_sync_prev_q;
  assign s_sync_prev_d = s_sync_meta;
  assign s_fault_sync_active = fault_ctrl_i[0] && (fault_ctrl_i[1] ? s_fault_meta : ~s_fault_meta);

  always_comb begin
    s_fault_filter_count_d = s_fault_filter_count_q;
    s_fault_filtered_d     = s_fault_filtered_q;
    if (!fault_ctrl_i[0]) begin
      s_fault_filter_count_d = '0;
      s_fault_filtered_d     = 1'b0;
    end else if (s_fault_sync_active == s_fault_filtered_q) begin
      s_fault_filter_count_d = '0;
    end else if (s_fault_filter_count_q >= fault_ctrl_i[7:4]) begin
      s_fault_filter_count_d = '0;
      s_fault_filtered_d     = s_fault_sync_active;
    end else begin
      s_fault_filter_count_d = s_fault_filter_count_q + 1'b1;
    end
  end

  assign s_fault_event = fault_test_i || (s_fault_filtered_d && !s_fault_filtered_q);

  always_comb begin
    s_fault_latched_d = s_fault_latched_q;
    if (!fault_ctrl_i[0]) s_fault_latched_d = 1'b0;
    if (s_fault_event && fault_ctrl_i[2]) s_fault_latched_d = 1'b1;
    if (fault_clear_i && !s_fault_sync_active) s_fault_latched_d = 1'b0;
  end

  assign s_fault_kill = fault_ctrl_i[0] &&
      (s_fault_raw || s_fault_filtered_q || s_fault_latched_q || fault_test_i);

  for (genvar timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin : gen_timer
    localparam int PEER = timer ^ 1;
    pwm_timer u_pwm_timer (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .module_enable_i (module_enable_i),
        .freeze_i        (s_freeze),
        .update_i        (update_i),
        .software_sync_i (software_sync_i),
        .external_sync_i (s_external_sync_pulse),
        .peer_zero_i     (s_timer_zero_q[PEER]),
        .ctrl_shadow_i   (timer_ctrl_i[timer]),
        .divider_shadow_i(timer_divider_i[timer]),
        .period_shadow_i (timer_period_i[timer]),
        .phase_shadow_i  (timer_phase_i[timer]),
        .counter_o       (timer_counter_o[timer]),
        .divider_active_o(timer_active_divider_o[timer]),
        .period_active_o (s_timer_period[timer]),
        .phase_active_o  (s_timer_phase[timer]),
        .direction_down_o(s_timer_direction[timer]),
        .tick_o          (s_timer_tick[timer]),
        .zero_event_o    (s_timer_zero[timer]),
        .period_event_o  (s_timer_period_event[timer]),
        .sync_event_o    (s_timer_sync[timer]),
        .update_done_o   (s_timer_update_done[timer]),
        .update_pending_o(s_timer_update_pending[timer]),
        .running_o       (s_timer_running[timer])
    );

    assign timer_active_period_o[timer] = s_timer_period[timer];
    assign timer_status_o[timer] = {
      24'h000000,
      s_timer_phase[timer] != '0,
      s_timer_sync[timer],
      s_timer_period_event[timer],
      s_timer_zero[timer],
      s_timer_direction[timer],
      s_timer_update_pending[timer],
      s_timer_running[timer],
      timer_ctrl_i[timer][0]
    };
  end

  for (genvar channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin : gen_channel
    logic [23:0] s_selected_counter;
    logic [23:0] s_selected_period;
    logic        s_selected_direction;
    logic        s_selected_tick;
    logic        s_selected_zero;
    logic        s_selected_period_event;
    logic        s_selected_sync;

    assign s_selected_counter = s_channel_timer_select[channel] ?
        timer_counter_o[1] : timer_counter_o[0];
    assign s_selected_period = s_channel_timer_select[channel] ?
        s_timer_period[1] : s_timer_period[0];
    assign s_selected_direction = s_channel_timer_select[channel] ?
        s_timer_direction[1] : s_timer_direction[0];
    assign s_selected_tick = s_channel_timer_select[channel] ? s_timer_tick[1] : s_timer_tick[0];
    assign s_selected_zero = s_channel_timer_select[channel] ? s_timer_zero[1] : s_timer_zero[0];
    assign s_selected_period_event = s_channel_timer_select[channel] ?
        s_timer_period_event[1] : s_timer_period_event[0];
    assign s_selected_sync = s_channel_timer_select[channel] ? s_timer_sync[1] : s_timer_sync[0];

    pwm_channel u_pwm_channel (
        .clk_i                 (clk_i),
        .rst_n_i               (rst_n_i),
        .module_enable_i       (module_enable_i),
        .freeze_i              (s_freeze),
        .stop_i                (stop_all_i),
        .update_i              (update_i),
        .timer_commit_i        (s_timer_update_done),
        .ctrl_shadow_i         (channel_ctrl_i[channel]),
        .phase_shadow_i        (channel_phase_i[channel]),
        .duty_shadow_i         (channel_duty_i[channel]),
        .action_shadow_i       (channel_action_i[channel]),
        .force_shadow_i        (channel_force_i[channel]),
        .fade_ctrl_i           (channel_fade_ctrl_i[channel]),
        .fade_segments_i       (channel_fade_segments_i[channel]),
        .fade_target_i         (channel_fade_target_i[channel]),
        .fade_step_i           (channel_fade_step_i[channel]),
        .fade_interval_i       (channel_fade_interval_i[channel]),
        .gamma_write_target_i  (gamma_write_target_i[channel]),
        .gamma_write_step_i    (gamma_write_step_i[channel]),
        .gamma_write_interval_i(gamma_write_interval_i[channel]),
        .gamma_index_i         (gamma_index_i[channel]),
        .gamma_target_i        (gamma_target_i[channel]),
        .gamma_step_i          (gamma_step_i[channel]),
        .gamma_interval_i      (gamma_interval_i[channel]),
        .gamma_target_o        (gamma_target_o[channel]),
        .gamma_step_o          (gamma_step_o[channel]),
        .gamma_interval_o      (gamma_interval_o[channel]),
        .timer_counter_i       (s_selected_counter),
        .timer_period_i        (s_selected_period),
        .timer_direction_down_i(s_selected_direction),
        .timer_tick_i          (s_selected_tick),
        .timer_zero_i          (s_selected_zero),
        .timer_period_event_i  (s_selected_period_event),
        .timer_sync_i          (s_selected_sync),
        .raw_output_o          (s_channel_raw[channel]),
        .active_phase_o        (channel_active_phase_o[channel]),
        .active_duty_o         (channel_active_duty_o[channel]),
        .enabled_o             (s_channel_enabled[channel]),
        .timer_select_o        (s_channel_timer_select[channel]),
        .fade_running_o        (s_fade_running[channel]),
        .fade_paused_o         (s_fade_paused[channel]),
        .fade_segment_o        (s_fade_segment[channel]),
        .fade_done_o           (s_fade_done[channel]),
        .update_pending_o      (s_channel_update_pending[channel])
    );

    assign channel_status_o[channel] = {
      23'h000000,
      s_fade_segment[channel],
      s_channel_update_pending[channel],
      s_fade_paused[channel],
      s_fade_running[channel],
      s_channel_raw[channel],
      s_channel_timer_select[channel],
      s_channel_enabled[channel]
    };
  end

  for (genvar operator = 0; operator < `PWM_OPERATOR_COUNT; operator++) begin : gen_operator
    localparam int CHANNEL_A = operator * 2;
    localparam int CHANNEL_B = operator * 2 + 1;
    logic s_deadtime_a, s_deadtime_b;

    pwm_deadtime u_pwm_deadtime (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),
        .enable_i       (module_enable_i),
        .complementary_i(operator_ctrl_i[operator][0]),
        .rise_delay_i   (operator_deadtime_i[operator][15:0]),
        .fall_delay_i   (operator_deadtime_i[operator][31:16]),
        .input_a_i      (s_channel_raw[CHANNEL_A]),
        .input_b_i      (s_channel_raw[CHANNEL_B]),
        .output_a_o     (s_deadtime_a),
        .output_b_o     (s_deadtime_b)
    );

    pwm_carrier u_pwm_carrier (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .enable_i  (operator_ctrl_i[operator][1]),
        .period_i  (operator_carrier_i[operator][7:0]),
        .duty_i    (operator_carrier_i[operator][15:8]),
        .invert_i  (operator_carrier_i[operator][16]),
        .input_a_i (s_deadtime_a),
        .input_b_i (s_deadtime_b),
        .output_a_o(s_carrier_output[CHANNEL_A]),
        .output_b_o(s_carrier_output[CHANNEL_B])
    );

    assign s_deadtime_output[CHANNEL_A] = s_deadtime_a;
    assign s_deadtime_output[CHANNEL_B] = s_deadtime_b;
    assign operator_status_o[operator] = {
      24'h000000,
      s_carrier_output[CHANNEL_B],
      s_carrier_output[CHANNEL_A],
      s_deadtime_b,
      s_deadtime_a,
      operator_ctrl_i[operator][1:0],
      2'b00
    };
  end

  pwm_capture u_pwm_capture (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .enable_i        (capture_enable_i),
      .clear_i         (capture_clear_i),
      .divider_i       (capture_divider_i),
      .channel_ctrl_i  (capture_channel_ctrl_i),
      .capture_i       (capture_i),
      .pop_i           (capture_pop_i),
      .counter_o       (capture_counter_o),
      .data_o          (capture_data_o),
      .level_o         (s_capture_level),
      .empty_o         (s_capture_empty),
      .full_o          (s_capture_full),
      .capture_event_o (s_capture_event),
      .overflow_event_o(s_capture_overflow),
      .watermark_o     (s_capture_watermark)
  );

  always_comb begin
    for (int output_index = 0; output_index < `PWM_CHANNEL_COUNT; output_index++) begin
      if (!module_enable_i) begin
        pwm_o[output_index] = 1'b0;
        oe_o[output_index]  = 1'b0;
      end else if (s_fault_kill) begin
        unique case (fault_safe_i[output_index*2+:2])
          2'd1: begin
            pwm_o[output_index] = 1'b1;
            oe_o[output_index]  = 1'b1;
          end
          2'd2: begin
            pwm_o[output_index] = 1'b0;
            oe_o[output_index]  = 1'b0;
          end
          default: begin
            pwm_o[output_index] = 1'b0;
            oe_o[output_index]  = 1'b1;
          end
        endcase
      end else begin
        pwm_o[output_index] = s_carrier_output[output_index];
        if (operator_ctrl_i[output_index/2][0]) begin
          oe_o[output_index] = s_channel_enabled[(output_index/2)*2];
        end else begin
          oe_o[output_index] = s_channel_enabled[output_index];
        end
      end
    end
  end

  always_comb begin
    event_o                = '0;
    event_o[1:0]           = s_timer_zero;
    event_o[3:2]           = s_timer_period_event;
    event_o[5:4]           = s_timer_update_done;
    event_o[9:6]           = s_fade_done;
    event_o[10]            = s_fault_event;
    event_o[12:11]         = s_capture_event | s_capture_watermark;
    event_o[14:13]         = s_capture_overflow;

    status_o               = '0;
    status_o[0]            = module_enable_i;
    status_o[2:1]          = s_timer_running;
    status_o[6:3]          = s_channel_enabled;
    status_o[7]            = s_fault_kill;
    status_o[9:8]          = s_timer_update_pending;
    status_o[13:10]        = s_channel_update_pending;
    status_o[17:14]        = s_fade_running;
    status_o[18]           = capture_enable_i;

    fault_status_o         = '0;
    fault_status_o[0]      = s_fault_raw;
    fault_status_o[1]      = s_fault_sync_active;
    fault_status_o[2]      = s_fault_filtered_q;
    fault_status_o[3]      = s_fault_latched_q;
    fault_status_o[4]      = s_fault_kill;

    output_status_o        = '0;
    output_status_o[3:0]   = pwm_o;
    output_status_o[7:4]   = oe_o;
    output_status_o[11:8]  = s_channel_raw;
    output_status_o[15:12] = s_deadtime_output;

    capture_status_o       = '0;
    capture_status_o[0]    = capture_enable_i;
    capture_status_o[2:1]  = s_capture_empty;
    capture_status_o[4:3]  = s_capture_full;
    capture_status_o[6:5]  = s_capture_watermark;
    for (int capture_channel = 0; capture_channel < `PWM_CAPTURE_COUNT; capture_channel++) begin
      capture_channel_status_o[capture_channel]      = '0;
      capture_channel_status_o[capture_channel][2:0] = s_capture_level[capture_channel];
      capture_channel_status_o[capture_channel][3]   = s_capture_empty[capture_channel];
      capture_channel_status_o[capture_channel][4]   = s_capture_full[capture_channel];
      capture_channel_status_o[capture_channel][5]   = s_capture_watermark[capture_channel];
    end
  end

  dffr #(1) u_sync_previous_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sync_prev_d),
      .dat_o  (s_sync_prev_q)
  );

  dffr #(2) u_timer_zero_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timer_zero),
      .dat_o  (s_timer_zero_q)
  );

  dffr #(4) u_fault_filter_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_filter_count_d),
      .dat_o  (s_fault_filter_count_q)
  );

  dffr #(1) u_fault_filtered_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_filtered_d),
      .dat_o  (s_fault_filtered_q)
  );

  dffr #(1) u_fault_latched_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_latched_d),
      .dat_o  (s_fault_latched_q)
  );

endmodule
