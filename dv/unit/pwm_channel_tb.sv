// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "pwm_define.svh"

module pwm_channel_tb;

  logic        clk_i;
  logic        rst_n_i;
  logic        update_i;
  logic [ 1:0] timer_commit_i;
  logic [ 4:0] fade_ctrl_i;
  logic        timer_zero_i;
  logic        raw_output_o;
  logic [23:0] active_phase_o;
  logic [23:0] active_duty_o;
  logic        enabled_o;
  logic        timer_select_o;
  logic        fade_running_o;
  logic        fade_paused_o;
  logic [ 2:0] fade_segment_o;
  logic        fade_done_o;
  logic        fade_done_seen;
  logic        update_pending_o;
  logic [23:0] gamma_target_o;
  logic [23:0] gamma_step_o;
  logic [15:0] gamma_interval_o;

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) fade_done_seen <= 1'b0;
    else if (fade_done_o) fade_done_seen <= 1'b1;
  end

  pwm_channel u_pwm_channel (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .module_enable_i       (1'b1),
      .freeze_i              (1'b0),
      .stop_i                (1'b0),
      .update_i              (update_i),
      .timer_commit_i        (timer_commit_i),
      .ctrl_shadow_i         (3'b001),
      .phase_shadow_i        (24'd0),
      .duty_shadow_i         (24'd4),
      .action_shadow_i       (16'h8000),
      .force_shadow_i        (2'b00),
      .fade_ctrl_i           (fade_ctrl_i),
      .fade_segments_i       (4'd1),
      .fade_target_i         (24'd2),
      .fade_step_i           (24'd2),
      .fade_interval_i       (16'd1),
      .gamma_write_target_i  (1'b0),
      .gamma_write_step_i    (1'b0),
      .gamma_write_interval_i(1'b0),
      .gamma_index_i         (3'd0),
      .gamma_target_i        (24'd0),
      .gamma_step_i          (24'd0),
      .gamma_interval_i      (16'd0),
      .gamma_target_o        (gamma_target_o),
      .gamma_step_o          (gamma_step_o),
      .gamma_interval_o      (gamma_interval_o),
      .timer_counter_i       (24'd0),
      .timer_period_i        (24'd16),
      .timer_direction_down_i(1'b0),
      .timer_tick_i          (1'b1),
      .timer_zero_i          (timer_zero_i),
      .timer_period_event_i  (1'b0),
      .timer_sync_i          (1'b0),
      .raw_output_o          (raw_output_o),
      .active_phase_o        (active_phase_o),
      .active_duty_o         (active_duty_o),
      .enabled_o             (enabled_o),
      .timer_select_o        (timer_select_o),
      .fade_running_o        (fade_running_o),
      .fade_paused_o         (fade_paused_o),
      .fade_segment_o        (fade_segment_o),
      .fade_done_o           (fade_done_o),
      .update_pending_o      (update_pending_o)
  );

  initial begin
    clk_i          = 1'b0;
    rst_n_i        = 1'b0;
    update_i       = 1'b0;
    timer_commit_i = 2'b00;
    fade_ctrl_i    = '0;
    timer_zero_i   = 1'b0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    @(negedge clk_i);
    update_i       = 1'b1;
    timer_commit_i = 2'b01;
    @(negedge clk_i);
    update_i       = 1'b0;
    timer_commit_i = 2'b00;
    if (!enabled_o || (active_duty_o != 24'd4) || raw_output_o) begin
      $fatal(1, "channel shadow commit failed");
    end

    fade_ctrl_i[0] = 1'b1;
    @(negedge clk_i);
    fade_ctrl_i = '0;
    if (!fade_running_o) $fatal(1, "fade did not start");

    timer_zero_i = 1'b1;
    @(posedge clk_i);
    #1;
    if (!fade_done_seen || !raw_output_o || (active_duty_o != 24'd2)) begin
      $fatal(1, "fade-done action failed seen=%0b output=%0b duty=%0d", fade_done_seen,
             raw_output_o, active_duty_o);
    end
    timer_zero_i = 1'b0;

    $display("PWM_CHANNEL_TEST_PASS");
    $finish;
  end

endmodule
