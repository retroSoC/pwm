// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "pwm_define.svh"

module pwm_channel (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        module_enable_i,
    input  logic        freeze_i,
    input  logic        stop_i,
    input  logic        update_i,
    input  logic [ 1:0] timer_commit_i,
    input  logic [ 2:0] ctrl_shadow_i,
    input  logic [23:0] phase_shadow_i,
    input  logic [23:0] duty_shadow_i,
    input  logic [15:0] action_shadow_i,
    input  logic [ 1:0] force_shadow_i,
    input  logic [ 4:0] fade_ctrl_i,
    input  logic [ 3:0] fade_segments_i,
    input  logic [23:0] fade_target_i,
    input  logic [23:0] fade_step_i,
    input  logic [15:0] fade_interval_i,
    input  logic        gamma_write_target_i,
    input  logic        gamma_write_step_i,
    input  logic        gamma_write_interval_i,
    input  logic [ 2:0] gamma_index_i,
    input  logic [23:0] gamma_target_i,
    input  logic [23:0] gamma_step_i,
    input  logic [15:0] gamma_interval_i,
    output logic [23:0] gamma_target_o,
    output logic [23:0] gamma_step_o,
    output logic [15:0] gamma_interval_o,
    input  logic [23:0] timer_counter_i,
    input  logic [23:0] timer_period_i,
    input  logic        timer_direction_down_i,
    input  logic        timer_tick_i,
    input  logic        timer_zero_i,
    input  logic        timer_period_event_i,
    input  logic        timer_sync_i,
    output logic        raw_output_o,
    output logic [23:0] active_phase_o,
    output logic [23:0] active_duty_o,
    output logic        enabled_o,
    output logic        timer_select_o,
    output logic        fade_running_o,
    output logic        fade_paused_o,
    output logic [ 2:0] fade_segment_o,
    output logic        fade_done_o,
    output logic        update_pending_o
    // verilog_format: on
);

  logic [ 2:0] s_ctrl_q;
  logic [23:0] s_phase_q;
  logic [23:0] s_duty_d, s_duty_q;
  logic [15:0] s_action_q;
  logic [ 1:0] s_force_q;
  logic s_update_pending_d, s_update_pending_q;
  logic s_commit;

  logic s_output_d, s_output_q;
  logic [23:0] s_duty_end;
  logic        s_phase_event;
  logic        s_duty_event;

  logic [23:0] s_gamma_target_q  [0:`PWM_GAMMA_SEGMENT_COUNT-1];
  logic [23:0] s_gamma_step_q    [0:`PWM_GAMMA_SEGMENT_COUNT-1];
  logic [15:0] s_gamma_interval_q[0:`PWM_GAMMA_SEGMENT_COUNT-1];
  logic s_fade_running_d, s_fade_running_q;
  logic s_fade_paused_d, s_fade_paused_q;
  logic s_fade_gamma_d, s_fade_gamma_q;
  logic [3:0] s_fade_segment_count_d, s_fade_segment_count_q;
  logic [2:0] s_fade_segment_d, s_fade_segment_q;
  logic [15:0] s_fade_interval_count_d, s_fade_interval_count_q;
  logic [23:0] s_fade_target;
  logic [23:0] s_fade_step;
  logic [15:0] s_fade_interval;
  logic        s_fade_cycle;
  logic        s_fade_step_event;

  function automatic logic apply_action(input logic value, input logic [1:0] action);
    unique case (action)
      `PWM_ACTION_LOW:    return 1'b0;
      `PWM_ACTION_HIGH:   return 1'b1;
      `PWM_ACTION_TOGGLE: return ~value;
      default:            return value;
    endcase
  endfunction

  assign enabled_o = s_ctrl_q[0];
  assign timer_select_o = s_ctrl_q[1];
  assign active_phase_o = s_phase_q;
  assign active_duty_o = s_duty_q;
  assign update_pending_o = s_update_pending_q;
  assign fade_running_o = s_fade_running_q;
  assign fade_paused_o = s_fade_paused_q;
  assign fade_segment_o = s_fade_segment_q;
  assign s_commit = (s_update_pending_q || update_i) &&
                    (!enabled_o || !module_enable_i || timer_commit_i[ctrl_shadow_i[1]]);

  always_comb begin
    s_update_pending_d = s_update_pending_q;
    if (update_i) s_update_pending_d = 1'b1;
    if (s_commit) s_update_pending_d = 1'b0;
  end

  assign gamma_target_o   = s_gamma_target_q[gamma_index_i];
  assign gamma_step_o     = s_gamma_step_q[gamma_index_i];
  assign gamma_interval_o = s_gamma_interval_q[gamma_index_i];

  for (genvar segment = 0; segment < `PWM_GAMMA_SEGMENT_COUNT; segment++) begin : gen_gamma
    dffer #(
        .DATA_WIDTH(24)
    ) u_gamma_target_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (gamma_write_target_i && (gamma_index_i == 3'(segment))),
        .dat_i  (gamma_target_i),
        .dat_o  (s_gamma_target_q[segment])
    );

    dffer #(
        .DATA_WIDTH(24)
    ) u_gamma_step_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (gamma_write_step_i && (gamma_index_i == 3'(segment))),
        .dat_i  (gamma_step_i),
        .dat_o  (s_gamma_step_q[segment])
    );

    dffer #(
        .DATA_WIDTH(16)
    ) u_gamma_interval_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (gamma_write_interval_i && (gamma_index_i == 3'(segment))),
        .dat_i  (gamma_interval_i),
        .dat_o  (s_gamma_interval_q[segment])
    );
  end

  always_comb begin
    if (s_fade_gamma_q) begin
      s_fade_target   = s_gamma_target_q[s_fade_segment_q];
      s_fade_step     = s_gamma_step_q[s_fade_segment_q];
      s_fade_interval = s_gamma_interval_q[s_fade_segment_q];
    end else begin
      s_fade_target   = fade_target_i;
      s_fade_step     = fade_step_i;
      s_fade_interval = fade_interval_i;
    end
  end

  assign s_fade_cycle = timer_zero_i && timer_tick_i;
  assign s_fade_step_event = s_fade_running_q && !s_fade_paused_q && s_fade_cycle &&
                             (s_fade_interval_count_q >=
                              ((s_fade_interval == 0) ? 16'd0 : s_fade_interval - 1'b1));

  always_comb begin
    s_duty_d                = s_duty_q;
    s_fade_running_d        = s_fade_running_q;
    s_fade_paused_d         = s_fade_paused_q;
    s_fade_gamma_d          = s_fade_gamma_q;
    s_fade_segment_count_d  = s_fade_segment_count_q;
    s_fade_segment_d        = s_fade_segment_q;
    s_fade_interval_count_d = s_fade_interval_count_q;
    fade_done_o             = 1'b0;

    if (s_commit) s_duty_d = duty_shadow_i;

    if (stop_i || !module_enable_i || !enabled_o) begin
      s_fade_running_d        = 1'b0;
      s_fade_paused_d         = 1'b0;
      s_fade_segment_d        = '0;
      s_fade_interval_count_d = '0;
    end else begin
      if (fade_ctrl_i[0]) begin
        s_fade_running_d        = 1'b1;
        s_fade_paused_d         = 1'b0;
        s_fade_gamma_d          = fade_ctrl_i[4];
        s_fade_segment_count_d  = fade_segments_i;
        s_fade_segment_d        = '0;
        s_fade_interval_count_d = '0;
      end
      if (fade_ctrl_i[1]) s_fade_paused_d = 1'b1;
      if (fade_ctrl_i[2]) s_fade_paused_d = 1'b0;
      if (fade_ctrl_i[3]) begin
        s_fade_running_d        = 1'b0;
        s_fade_paused_d         = 1'b0;
        s_fade_interval_count_d = '0;
      end

      if (s_fade_running_q && !s_fade_paused_q && s_fade_cycle) begin
        if (s_fade_step_event) begin
          s_fade_interval_count_d = '0;
          if (s_duty_q < s_fade_target) begin
            if ((s_fade_target - s_duty_q) <= s_fade_step) s_duty_d = s_fade_target;
            else s_duty_d = s_duty_q + s_fade_step;
          end else if (s_duty_q > s_fade_target) begin
            if ((s_duty_q - s_fade_target) <= s_fade_step) s_duty_d = s_fade_target;
            else s_duty_d = s_duty_q - s_fade_step;
          end

          if ((s_duty_q == s_fade_target) ||
              ((s_duty_q < s_fade_target) &&
               ((s_fade_target - s_duty_q) <= s_fade_step)) ||
              ((s_duty_q > s_fade_target) &&
               ((s_duty_q - s_fade_target) <= s_fade_step))) begin
            if (s_fade_gamma_q && ({1'b0, s_fade_segment_q} + 1'b1 < s_fade_segment_count_q)) begin
              s_fade_segment_d = s_fade_segment_q + 1'b1;
            end else begin
              s_fade_running_d = 1'b0;
              fade_done_o      = 1'b1;
            end
          end
        end else begin
          s_fade_interval_count_d = s_fade_interval_count_q + 1'b1;
        end
      end
    end
  end

  assign s_duty_end    = s_phase_q + s_duty_q;
  assign s_phase_event = timer_tick_i && (timer_counter_i == s_phase_q);
  assign s_duty_event  = timer_tick_i && (timer_counter_i == s_duty_end);

  always_comb begin
    s_output_d = s_output_q;
    if (!module_enable_i || !enabled_o || stop_i) begin
      s_output_d = 1'b0;
    end else if (!freeze_i) begin
      if (s_phase_event && !timer_direction_down_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[5:4]);
      end
      if (s_duty_event && !timer_direction_down_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[7:6]);
      end
      if (s_phase_event && timer_direction_down_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[9:8]);
      end
      if (s_duty_event && timer_direction_down_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[11:10]);
      end
      if (timer_period_event_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[3:2]);
      end
      if (timer_zero_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[1:0]);
      end
      if (timer_sync_i) begin
        s_output_d = apply_action(s_output_d, s_action_q[13:12]);
      end
      if (fade_done_o) begin
        s_output_d = apply_action(s_output_d, s_action_q[15:14]);
      end
    end

    if (s_duty_q == '0) s_output_d = 1'b0;
    else if (s_duty_q >= timer_period_i) s_output_d = 1'b1;
  end

  assign raw_output_o = s_force_q[0] ? s_force_q[1] : (s_output_q ^ s_ctrl_q[2]);

  dffer #(
      .DATA_WIDTH(3)
  ) u_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (ctrl_shadow_i),
      .dat_o  (s_ctrl_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_phase_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (phase_shadow_i),
      .dat_o  (s_phase_q)
  );

  dffr #(
      .DATA_WIDTH(24)
  ) u_duty_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_duty_d),
      .dat_o  (s_duty_q)
  );

  dffer #(
      .DATA_WIDTH(16)
  ) u_action_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (action_shadow_i),
      .dat_o  (s_action_q)
  );

  dffer #(
      .DATA_WIDTH(2)
  ) u_force_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (force_shadow_i),
      .dat_o  (s_force_q)
  );

  dffr #(1) u_output_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_d),
      .dat_o  (s_output_q)
  );

  dffr #(1) u_update_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_update_pending_d),
      .dat_o  (s_update_pending_q)
  );

  dffr #(1) u_fade_running_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_running_d),
      .dat_o  (s_fade_running_q)
  );

  dffr #(1) u_fade_paused_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_paused_d),
      .dat_o  (s_fade_paused_q)
  );

  dffr #(1) u_fade_gamma_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_gamma_d),
      .dat_o  (s_fade_gamma_q)
  );

  dffr #(4) u_fade_segment_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_segment_count_d),
      .dat_o  (s_fade_segment_count_q)
  );

  dffr #(3) u_fade_segment_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_segment_d),
      .dat_o  (s_fade_segment_q)
  );

  dffr #(16) u_fade_interval_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fade_interval_count_d),
      .dat_o  (s_fade_interval_count_q)
  );

endmodule
