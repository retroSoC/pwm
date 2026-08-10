// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "pwm_define.svh"

module pwm_timer (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        module_enable_i,
    input  logic        freeze_i,
    input  logic        update_i,
    input  logic        software_sync_i,
    input  logic        external_sync_i,
    input  logic        peer_zero_i,
    input  logic [ 5:0] ctrl_shadow_i,
    input  logic [23:0] divider_shadow_i,
    input  logic [23:0] period_shadow_i,
    input  logic [23:0] phase_shadow_i,
    output logic [23:0] counter_o,
    output logic [23:0] divider_active_o,
    output logic [23:0] period_active_o,
    output logic [23:0] phase_active_o,
    output logic        direction_down_o,
    output logic        tick_o,
    output logic        zero_event_o,
    output logic        period_event_o,
    output logic        sync_event_o,
    output logic        update_done_o,
    output logic        update_pending_o,
    output logic        running_o
    // verilog_format: on
);

  logic [5:0] s_ctrl_q;
  logic [23:0] s_divider_q, s_period_q, s_phase_q;
  logic [23:0] s_counter_d, s_counter_q;
  logic s_direction_d, s_direction_q;
  logic s_update_pending_d, s_update_pending_q;
  logic       s_timer_enable;
  logic [1:0] s_count_mode;
  logic [1:0] s_load_mode;
  logic       s_sync_enable;
  logic       s_sync_request;
  logic       s_update_request;
  logic       s_commit;
  logic       s_load_event;

  assign s_timer_enable   = s_ctrl_q[0];
  assign s_count_mode     = s_ctrl_q[2:1];
  assign s_load_mode      = s_ctrl_q[4:3];
  assign s_sync_enable    = s_ctrl_q[5];
  assign s_sync_request   = software_sync_i || external_sync_i || peer_zero_i;
  assign sync_event_o     = s_sync_enable && s_sync_request;
  assign s_update_request = s_update_pending_q || update_i;
  assign running_o        = module_enable_i && s_timer_enable && !freeze_i;
  assign update_pending_o = s_update_pending_q;

  always_comb begin
    unique case (s_load_mode)
      2'd0:    s_load_event = zero_event_o;
      2'd1:    s_load_event = period_event_o;
      2'd2:    s_load_event = zero_event_o || sync_event_o;
      default: s_load_event = sync_event_o;
    endcase
  end

  assign s_commit      = s_update_request && (!s_timer_enable || !module_enable_i || s_load_event);
  assign update_done_o = s_commit;

  always_comb begin
    s_update_pending_d = s_update_pending_q;
    if (update_i) s_update_pending_d = 1'b1;
    if (s_commit) s_update_pending_d = 1'b0;
  end

  pwm_tickgen u_pwm_tickgen (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .enable_i (running_o),
      .divider_i(s_divider_q),
      .tick_o   (tick_o)
  );

  always_comb begin
    zero_event_o   = 1'b0;
    period_event_o = 1'b0;
    s_counter_d    = s_counter_q;
    s_direction_d  = s_direction_q;

    if (!module_enable_i || !s_timer_enable) begin
      s_counter_d   = '0;
      s_direction_d = s_count_mode == 2'd1;
    end else if (sync_event_o) begin
      s_counter_d   = s_update_request ? phase_shadow_i : s_phase_q;
      s_direction_d = s_count_mode == 2'd1;
    end else if (tick_o) begin
      unique case (s_count_mode)
        2'd0: begin
          if (s_counter_q >= s_period_q - 1'b1) begin
            s_counter_d    = '0;
            zero_event_o   = 1'b1;
            period_event_o = 1'b1;
          end else begin
            s_counter_d = s_counter_q + 1'b1;
          end
        end
        2'd1: begin
          if (s_counter_q == '0) begin
            s_counter_d    = s_period_q - 1'b1;
            zero_event_o   = 1'b1;
            period_event_o = 1'b1;
          end else begin
            s_counter_d = s_counter_q - 1'b1;
          end
        end
        default: begin
          if (!s_direction_q) begin
            if (s_counter_q >= s_period_q - 1'b1) begin
              s_counter_d    = s_period_q;
              s_direction_d  = 1'b1;
              period_event_o = 1'b1;
            end else begin
              s_counter_d = s_counter_q + 1'b1;
            end
          end else if (s_counter_q <= 1) begin
            s_counter_d   = '0;
            s_direction_d = 1'b0;
            zero_event_o  = 1'b1;
          end else begin
            s_counter_d = s_counter_q - 1'b1;
          end
        end
      endcase
    end
  end

  dffer #(
      .DATA_WIDTH(6)
  ) u_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (ctrl_shadow_i),
      .dat_o  (s_ctrl_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_divider_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (divider_shadow_i),
      .dat_o  (s_divider_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_period_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_commit),
      .dat_i  (period_shadow_i),
      .dat_o  (s_period_q)
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
  ) u_counter_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_counter_d),
      .dat_o  (s_counter_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_direction_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_direction_d),
      .dat_o  (s_direction_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_update_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_update_pending_d),
      .dat_o  (s_update_pending_q)
  );

  assign counter_o        = s_counter_q;
  assign divider_active_o = s_divider_q;
  assign period_active_o  = s_period_q;
  assign phase_active_o   = s_phase_q;
  assign direction_down_o = s_direction_q;

endmodule
