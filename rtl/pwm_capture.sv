// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "pwm_define.svh"

module pwm_capture (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        clear_i,
    input  logic [23:0] divider_i,
    input  logic [31:0] channel_ctrl_i [0:`PWM_CAPTURE_COUNT-1],
    input  logic [ 1:0] capture_i,
    input  logic [ 1:0] pop_i,
    output logic [31:0] counter_o,
    output logic [31:0] data_o         [0:`PWM_CAPTURE_COUNT-1],
    output logic [ 2:0] level_o        [0:`PWM_CAPTURE_COUNT-1],
    output logic [ 1:0] empty_o,
    output logic [ 1:0] full_o,
    output logic [ 1:0] capture_event_o,
    output logic [ 1:0] overflow_event_o,
    output logic [ 1:0] watermark_o
    // verilog_format: on
);

  logic s_tick;
  logic [31:0] s_counter_d, s_counter_q;
  logic [1:0] s_capture_sync;
  logic [1:0] s_filtered_d, s_filtered_q;
  logic [1:0] s_candidate_d, s_candidate_q;
  logic [3:0] s_stable_count_d[0:`PWM_CAPTURE_COUNT-1];
  logic [3:0] s_stable_count_q[0:`PWM_CAPTURE_COUNT-1];
  logic [1:0] s_rise_event, s_fall_event, s_push;
  logic [2:0] s_fifo_count[0:`PWM_CAPTURE_COUNT-1];

  pwm_tickgen u_capture_tickgen (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .enable_i (enable_i),
      .divider_i(divider_i),
      .tick_o   (s_tick)
  );

  always_comb begin
    if (!enable_i || clear_i) s_counter_d = '0;
    else if (s_tick) s_counter_d = s_counter_q + 1'b1;
    else s_counter_d = s_counter_q;
  end

  dffr #(32) u_counter_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_counter_d),
      .dat_o  (s_counter_q)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_capture_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (capture_i),
      .dat_o  (s_capture_sync)
  );

  for (genvar channel = 0; channel < `PWM_CAPTURE_COUNT; channel++) begin : gen_capture
    always_comb begin
      s_filtered_d[channel]     = s_filtered_q[channel];
      s_candidate_d[channel]    = s_candidate_q[channel];
      s_stable_count_d[channel] = s_stable_count_q[channel];

      if (!enable_i || clear_i || !channel_ctrl_i[channel][0]) begin
        s_filtered_d[channel]     = s_capture_sync[channel];
        s_candidate_d[channel]    = s_capture_sync[channel];
        s_stable_count_d[channel] = '0;
      end else if (s_capture_sync[channel] != s_candidate_q[channel]) begin
        s_candidate_d[channel]    = s_capture_sync[channel];
        s_stable_count_d[channel] = '0;
      end else if (s_capture_sync[channel] != s_filtered_q[channel]) begin
        if (s_stable_count_q[channel] >= channel_ctrl_i[channel][7:4]) begin
          s_filtered_d[channel]     = s_capture_sync[channel];
          s_stable_count_d[channel] = '0;
        end else begin
          s_stable_count_d[channel] = s_stable_count_q[channel] + 1'b1;
        end
      end else begin
        s_stable_count_d[channel] = '0;
      end
    end

    assign s_rise_event[channel] = s_filtered_d[channel] && !s_filtered_q[channel];
    assign s_fall_event[channel] = !s_filtered_d[channel] && s_filtered_q[channel];
    assign s_push[channel] = enable_i && channel_ctrl_i[channel][0] &&
        ((channel_ctrl_i[channel][1] && s_rise_event[channel]) ||
         (channel_ctrl_i[channel][2] && s_fall_event[channel]));
    assign capture_event_o[channel] = s_push[channel] && !full_o[channel];
    assign overflow_event_o[channel] = s_push[channel] && full_o[channel];
    assign level_o[channel] = s_fifo_count[channel];
    assign watermark_o[channel] = channel_ctrl_i[channel][0] && !empty_o[channel] &&
        (s_fifo_count[channel] >=
         ((channel_ctrl_i[channel][10:8] == 0) ? 3'd1 : channel_ctrl_i[channel][10:8]));

    fifo #(
        .DATA_WIDTH      (32),
        .BUFFER_DEPTH    (`PWM_CAPTURE_FIFO_DEPTH),
        .LOG_BUFFER_DEPTH($clog2(`PWM_CAPTURE_FIFO_DEPTH))
    ) u_capture_fifo (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .flush_i(clear_i || !enable_i || !channel_ctrl_i[channel][0]),
        .push_i (s_push[channel] && !full_o[channel]),
        .full_o (full_o[channel]),
        .dat_i  (s_counter_q),
        .pop_i  (pop_i[channel] && !empty_o[channel]),
        .empty_o(empty_o[channel]),
        .dat_o  (data_o[channel]),
        .cnt_o  (s_fifo_count[channel])
    );

    dffr #(4) u_stable_count_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_stable_count_d[channel]),
        .dat_o  (s_stable_count_q[channel])
    );
  end

  dffr #(2) u_filtered_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_filtered_d),
      .dat_o  (s_filtered_q)
  );

  dffr #(2) u_candidate_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_candidate_d),
      .dat_o  (s_candidate_q)
  );

  assign counter_o = s_counter_q;

endmodule
