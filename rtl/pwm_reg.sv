// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "pwm_define.svh"

module pwm_reg #(
    parameter int PCLK_HZ = 72_000_000
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        debug_halted_i,
    input  logic [11:0] paddr_i,
    input  logic        psel_i,
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] pwdata_i,
    input  logic [ 3:0] pstrb_i,
    output logic        pready_o,
    output logic [31:0] prdata_o,
    output logic        pslverr_o,
    input  logic        fault_i,
    input  logic        sync_i,
    input  logic [ 1:0] capture_i,
    output logic [ 3:0] pwm_o,
    output logic [ 3:0] oe_o,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [31:0] CAPABILITY_VALUE = {
    `PWM_ABI_VERSION,
    4'(`PWM_TIMER_COUNT),
    4'(`PWM_OPERATOR_COUNT),
    4'(`PWM_CHANNEL_COUNT),
    4'(`PWM_CAPTURE_COUNT),
    `PWM_CAPABILITY_FEATURES
  };
  localparam logic [11:0] TIMER_BASE_ADDRESS = `PWM_TIMER_BASE_OFFSET;
  localparam logic [11:0] CHANNEL_BASE_ADDRESS = `PWM_CHANNEL_BASE_OFFSET;
  localparam logic [11:0] OPERATOR_BASE_ADDRESS = `PWM_OPERATOR_BASE_OFFSET;
  localparam logic [11:0] TIMER_BLOCK_STRIDE = `PWM_TIMER_STRIDE;
  localparam logic [11:0] CHANNEL_BLOCK_STRIDE = `PWM_CHANNEL_STRIDE;
  localparam logic [11:0] OPERATOR_BLOCK_STRIDE = `PWM_OPERATOR_STRIDE;

  logic s_transfer, s_read, s_write, s_access_legal;
  logic [31:0] s_write_mask, s_masked_wdata;
  logic [31:0] s_merged_word;
  logic        s_enable_config_valid;

  logic [31:0] s_ctrl_d, s_ctrl_q;
  logic s_safety_lock_d, s_safety_lock_q;
  logic [7:0] s_fault_ctrl_d, s_fault_ctrl_q;
  logic [7:0] s_fault_safe_d, s_fault_safe_q;
  logic [14:0] s_intr_state_d, s_intr_state_q;
  logic [14:0] s_intr_enable_d, s_intr_enable_q;

  logic [ 5:0] s_timer_ctrl_d           [   0:`PWM_TIMER_COUNT-1];
  logic [ 5:0] s_timer_ctrl_q           [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_divider_d        [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_divider_q        [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_period_d         [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_period_q         [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_phase_d          [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_phase_q          [   0:`PWM_TIMER_COUNT-1];

  logic [ 2:0] s_channel_ctrl_d         [ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 2:0] s_channel_ctrl_q         [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_phase_d        [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_phase_q        [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_duty_d         [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_duty_q         [ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_channel_action_d       [ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_channel_action_q       [ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 1:0] s_channel_force_d        [ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 1:0] s_channel_force_q        [ 0:`PWM_CHANNEL_COUNT-1];
  logic        s_channel_fade_gamma_d   [ 0:`PWM_CHANNEL_COUNT-1];
  logic        s_channel_fade_gamma_q   [ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 3:0] s_channel_fade_segments_d[ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 3:0] s_channel_fade_segments_q[ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_fade_target_d  [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_fade_target_q  [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_fade_step_d    [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_fade_step_q    [ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_channel_fade_interval_d[ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_channel_fade_interval_q[ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 2:0] s_gamma_index_d          [ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 2:0] s_gamma_index_q          [ 0:`PWM_CHANNEL_COUNT-1];

  logic [ 1:0] s_operator_ctrl_d        [0:`PWM_OPERATOR_COUNT-1];
  logic [ 1:0] s_operator_ctrl_q        [0:`PWM_OPERATOR_COUNT-1];
  logic [31:0] s_operator_deadtime_d    [0:`PWM_OPERATOR_COUNT-1];
  logic [31:0] s_operator_deadtime_q    [0:`PWM_OPERATOR_COUNT-1];
  logic [31:0] s_operator_carrier_d     [0:`PWM_OPERATOR_COUNT-1];
  logic [31:0] s_operator_carrier_q     [0:`PWM_OPERATOR_COUNT-1];

  logic s_capture_enable_d, s_capture_enable_q;
  logic [23:0] s_capture_divider_d, s_capture_divider_q;
  logic [31:0] s_capture_channel_ctrl_d[0:`PWM_CAPTURE_COUNT-1];
  logic [31:0] s_capture_channel_ctrl_q[0:`PWM_CAPTURE_COUNT-1];

  logic [5:0] s_command_d, s_command_q;
  logic [4:0] s_fade_command_d[0:`PWM_CHANNEL_COUNT-1];
  logic [4:0] s_fade_command_q[0:`PWM_CHANNEL_COUNT-1];
  logic [3:0] s_gamma_write_target_d, s_gamma_write_target_q;
  logic [3:0] s_gamma_write_step_d, s_gamma_write_step_q;
  logic [3:0] s_gamma_write_interval_d, s_gamma_write_interval_q;
  logic [23:0] s_gamma_target_write_d  [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_gamma_target_write_q  [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_gamma_step_write_d    [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_gamma_step_write_q    [ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_gamma_interval_write_d[ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_gamma_interval_write_q[ 0:`PWM_CHANNEL_COUNT-1];
  logic [ 1:0] s_capture_pop;

  logic [14:0] s_event;
  logic [31:0] s_status;
  logic [31:0] s_fault_status;
  logic [31:0] s_output_status;
  logic [23:0] s_timer_counter         [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_active_divider  [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_timer_active_period   [   0:`PWM_TIMER_COUNT-1];
  logic [31:0] s_timer_status          [   0:`PWM_TIMER_COUNT-1];
  logic [23:0] s_channel_active_phase  [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_channel_active_duty   [ 0:`PWM_CHANNEL_COUNT-1];
  logic [31:0] s_channel_status        [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_gamma_target_read     [ 0:`PWM_CHANNEL_COUNT-1];
  logic [23:0] s_gamma_step_read       [ 0:`PWM_CHANNEL_COUNT-1];
  logic [15:0] s_gamma_interval_read   [ 0:`PWM_CHANNEL_COUNT-1];
  logic [31:0] s_operator_status       [0:`PWM_OPERATOR_COUNT-1];
  logic [31:0] s_capture_counter;
  logic [31:0] s_capture_data          [ 0:`PWM_CAPTURE_COUNT-1];
  logic [31:0] s_capture_status;
  logic [31:0] s_capture_channel_status[ 0:`PWM_CAPTURE_COUNT-1];

  function automatic logic [31:0] merge_write(input logic [31:0] current, input logic [31:0] value,
                                              input logic [31:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [23:0] merge_write24(input logic [23:0] current,
                                                input logic [23:0] value, input logic [23:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [15:0] merge_write16(input logic [15:0] current,
                                                input logic [15:0] value, input logic [15:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [14:0] merge_write15(input logic [14:0] current,
                                                input logic [14:0] value, input logic [14:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [7:0] merge_write8(input logic [7:0] current, input logic [7:0] value,
                                              input logic [7:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [5:0] merge_write6(input logic [5:0] current, input logic [5:0] value,
                                              input logic [5:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [3:0] merge_write4(input logic [3:0] current, input logic [3:0] value,
                                              input logic [3:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [2:0] merge_write3(input logic [2:0] current, input logic [2:0] value,
                                              input logic [2:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic [1:0] merge_write2(input logic [1:0] current, input logic [1:0] value,
                                              input logic [1:0] mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic merge_write1(input logic current, input logic value, input logic mask);
    return (current & ~mask) | (value & mask);
  endfunction

  function automatic logic address_in_block(
      input logic [11:0] address, input logic [11:0] base_address, input int unsigned block_index,
      input logic [11:0] block_stride);
    int unsigned address_value;
    int unsigned block_start;
    begin
      address_value = int'(address);
      block_start   = int'(base_address) + (block_index * int'(block_stride));
      return (address_value >= block_start) && (address_value < (block_start + int'(block_stride)));
    end
  endfunction

  assign s_transfer     = psel_i && penable_i;
  assign s_read         = s_transfer && !pwrite_i;
  assign s_write        = s_transfer && pwrite_i;
  assign s_write_mask   = {{8{pstrb_i[3]}}, {8{pstrb_i[2]}}, {8{pstrb_i[1]}}, {8{pstrb_i[0]}}};
  assign s_masked_wdata = pwdata_i & s_write_mask;
  assign pready_o       = 1'b1;
  assign irq_o          = |(s_intr_state_q & s_intr_enable_q);

  always_comb begin
    s_enable_config_valid = 1'b1;
    for (int timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin
      if (s_timer_ctrl_q[timer][0] &&
          ((s_timer_divider_q[timer] < 24'(`PWM_TIMER_DIVIDER_MIN)) ||
           (s_timer_period_q[timer] < 24'(`PWM_TIMER_PERIOD_MIN)) ||
           (s_timer_phase_q[timer] >= s_timer_period_q[timer]))) begin
        s_enable_config_valid = 1'b0;
      end
    end
    for (int channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin
      if (s_channel_ctrl_q[channel][0] &&
          (!s_timer_ctrl_q[s_channel_ctrl_q[channel][1]][0] ||
           (s_channel_phase_q[channel] >= s_timer_period_q[s_channel_ctrl_q[channel][1]]) ||
           (s_channel_duty_q[channel] >
            (s_timer_period_q[s_channel_ctrl_q[channel][1]] - s_channel_phase_q[channel])))) begin
        s_enable_config_valid = 1'b0;
      end
    end
  end

  always_comb begin
    prdata_o       = '0;
    s_access_legal = (paddr_i[1:0] == 2'b00);
    s_merged_word  = '0;

    if (s_read && s_access_legal) begin
      s_access_legal = 1'b1;
      unique case (paddr_i)
        `PWM_CTRL_OFFSET:            prdata_o = s_ctrl_q;
        `PWM_STATUS_OFFSET:          prdata_o = s_status | {27'h0, s_safety_lock_q, 4'h0};
        `PWM_SAFETY_LOCK_OFFSET:     prdata_o = {31'h0, s_safety_lock_q};
        `PWM_FAULT_CTRL_OFFSET:      prdata_o = {24'h000000, s_fault_ctrl_q};
        `PWM_FAULT_SAFE_OFFSET:      prdata_o = {24'h000000, s_fault_safe_q};
        `PWM_FAULT_STATUS_OFFSET:    prdata_o = s_fault_status;
        `PWM_INTR_STATE_OFFSET:      prdata_o = {17'h0, s_intr_state_q};
        `PWM_INTR_ENABLE_OFFSET:     prdata_o = {17'h0, s_intr_enable_q};
        `PWM_OUTPUT_STATUS_OFFSET:   prdata_o = s_output_status;
        `PWM_CLOCK_HZ_OFFSET:        prdata_o = 32'(PCLK_HZ);
        `PWM_CAPTURE_CTRL_OFFSET:    prdata_o = {31'h0, s_capture_enable_q};
        `PWM_CAPTURE_DIVIDER_OFFSET: prdata_o = {8'h00, s_capture_divider_q};
        `PWM_CAPTURE_COUNTER_OFFSET: prdata_o = s_capture_counter;
        `PWM_CAPTURE_STATUS_OFFSET:  prdata_o = s_capture_status;
        `PWM_CAPTURE0_CTRL_OFFSET:   prdata_o = s_capture_channel_ctrl_q[0];
        `PWM_CAPTURE0_STATUS_OFFSET: prdata_o = s_capture_channel_status[0];
        `PWM_CAPTURE0_DATA_OFFSET: begin
          prdata_o       = s_capture_data[0];
          s_access_legal = !s_capture_channel_status[0][3];
        end
        `PWM_CAPTURE1_CTRL_OFFSET:   prdata_o = s_capture_channel_ctrl_q[1];
        `PWM_CAPTURE1_STATUS_OFFSET: prdata_o = s_capture_channel_status[1];
        `PWM_CAPTURE1_DATA_OFFSET: begin
          prdata_o       = s_capture_data[1];
          s_access_legal = !s_capture_channel_status[1][3];
        end
        `PWM_IP_ID_OFFSET:           prdata_o = `PWM_IP_ID_VALUE;
        `PWM_IP_VERSION_OFFSET:      prdata_o = `PWM_IP_VERSION_VALUE;
        `PWM_CAPABILITY_OFFSET:      prdata_o = CAPABILITY_VALUE;
        default: begin
          s_access_legal = 1'b0;
          for (int timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin
            if (address_in_block(paddr_i, TIMER_BASE_ADDRESS, timer, TIMER_BLOCK_STRIDE)) begin
              s_access_legal = 1'b1;
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_TIMER_CTRL_OFFSET: prdata_o = {26'h0000000, s_timer_ctrl_q[timer]};
                `PWM_TIMER_DIVIDER_OFFSET: prdata_o = {8'h00, s_timer_divider_q[timer]};
                `PWM_TIMER_PERIOD_OFFSET: prdata_o = {8'h00, s_timer_period_q[timer]};
                `PWM_TIMER_PHASE_OFFSET: prdata_o = {8'h00, s_timer_phase_q[timer]};
                `PWM_TIMER_COUNTER_OFFSET: prdata_o = {8'h00, s_timer_counter[timer]};
                `PWM_TIMER_ACTIVE_DIVIDER_OFFSET: prdata_o = {8'h00, s_timer_active_divider[timer]};
                `PWM_TIMER_ACTIVE_PERIOD_OFFSET: prdata_o = {8'h00, s_timer_active_period[timer]};
                `PWM_TIMER_STATUS_OFFSET: prdata_o = s_timer_status[timer];
                default: s_access_legal = 1'b0;
              endcase
            end
          end
          for (int channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin
            if (address_in_block(
                    paddr_i, CHANNEL_BASE_ADDRESS, channel, CHANNEL_BLOCK_STRIDE
                )) begin
              s_access_legal = 1'b1;
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_CHANNEL_CTRL_OFFSET: prdata_o = {29'h00000000, s_channel_ctrl_q[channel]};
                `PWM_CHANNEL_PHASE_OFFSET: prdata_o = {8'h00, s_channel_phase_q[channel]};
                `PWM_CHANNEL_DUTY_OFFSET: prdata_o = {8'h00, s_channel_duty_q[channel]};
                `PWM_CHANNEL_ACTION_OFFSET: prdata_o = {16'h0000, s_channel_action_q[channel]};
                `PWM_CHANNEL_FORCE_OFFSET: prdata_o = {30'h0, s_channel_force_q[channel]};
                `PWM_CHANNEL_FADE_CTRL_OFFSET: begin
                  prdata_o = {
                    20'h00000,
                    s_channel_fade_segments_q[channel],
                    3'h0,
                    s_channel_fade_gamma_q[channel],
                    4'h0
                  };
                end
                `PWM_CHANNEL_FADE_TARGET_OFFSET:
                prdata_o = {8'h00, s_channel_fade_target_q[channel]};
                `PWM_CHANNEL_FADE_STEP_OFFSET: prdata_o = {8'h00, s_channel_fade_step_q[channel]};
                `PWM_CHANNEL_FADE_INTERVAL_OFFSET:
                prdata_o = {16'h0000, s_channel_fade_interval_q[channel]};
                `PWM_CHANNEL_FADE_STATUS_OFFSET: prdata_o = s_channel_status[channel];
                `PWM_CHANNEL_ACTIVE_PHASE_OFFSET:
                prdata_o = {8'h00, s_channel_active_phase[channel]};
                `PWM_CHANNEL_ACTIVE_DUTY_OFFSET: prdata_o = {8'h00, s_channel_active_duty[channel]};
                `PWM_CHANNEL_GAMMA_INDEX_OFFSET: prdata_o = {29'h0, s_gamma_index_q[channel]};
                `PWM_CHANNEL_GAMMA_TARGET_OFFSET: prdata_o = {8'h00, s_gamma_target_read[channel]};
                `PWM_CHANNEL_GAMMA_STEP_OFFSET: prdata_o = {8'h00, s_gamma_step_read[channel]};
                `PWM_CHANNEL_GAMMA_INTERVAL_OFFSET:
                prdata_o = {16'h0000, s_gamma_interval_read[channel]};
                default: s_access_legal = 1'b0;
              endcase
            end
          end
          for (int operator = 0; operator < `PWM_OPERATOR_COUNT; operator++) begin
            if (address_in_block(
                    paddr_i, OPERATOR_BASE_ADDRESS, operator, OPERATOR_BLOCK_STRIDE
                )) begin
              s_access_legal = 1'b1;
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_OPERATOR_CTRL_OFFSET: prdata_o = {30'h00000000, s_operator_ctrl_q[operator]};
                `PWM_OPERATOR_DEADTIME_OFFSET: prdata_o = s_operator_deadtime_q[operator];
                `PWM_OPERATOR_CARRIER_OFFSET: prdata_o = s_operator_carrier_q[operator];
                `PWM_OPERATOR_STATUS_OFFSET: prdata_o = s_operator_status[operator];
                default: s_access_legal = 1'b0;
              endcase
            end
          end
        end
      endcase
    end else if (s_write && s_access_legal) begin
      s_access_legal = 1'b1;
      unique case (paddr_i)
        `PWM_CTRL_OFFSET: begin
          s_merged_word = merge_write(s_ctrl_q, pwdata_i, s_write_mask);
          s_access_legal = ((s_merged_word & ~`PWM_CTRL_VALID_MASK) == 0) &&
                           (!s_merged_word[0] || s_enable_config_valid);
        end
        `PWM_COMMAND_OFFSET: s_access_legal = (s_masked_wdata & ~`PWM_COMMAND_VALID_MASK) == 0;
        `PWM_SAFETY_LOCK_OFFSET:
        s_access_legal = !s_ctrl_q[0] && ((s_masked_wdata & ~`PWM_SAFETY_LOCK_MASK) == 0);
        `PWM_FAULT_CTRL_OFFSET: begin
          s_merged_word = merge_write({24'h000000, s_fault_ctrl_q}, pwdata_i, s_write_mask);
          s_access_legal = !s_ctrl_q[0] && !s_safety_lock_q &&
              ((s_merged_word & ~`PWM_FAULT_CTRL_VALID_MASK) == 0);
        end
        `PWM_FAULT_SAFE_OFFSET: begin
          s_merged_word = merge_write({24'h000000, s_fault_safe_q}, pwdata_i, s_write_mask);
          s_access_legal = !s_ctrl_q[0] && !s_safety_lock_q &&
              ((s_merged_word & ~`PWM_FAULT_SAFE_VALID_MASK) == 0);
        end
        `PWM_FAULT_CLEAR_OFFSET: s_access_legal = (s_masked_wdata & ~`PWM_FAULT_CLEAR_MASK) == 0;
        `PWM_INTR_STATE_OFFSET: s_access_legal = (s_masked_wdata & ~`PWM_INTR_VALID_MASK) == 0;
        `PWM_INTR_ENABLE_OFFSET: begin
          s_merged_word  = merge_write({17'h0, s_intr_enable_q}, pwdata_i, s_write_mask);
          s_access_legal = (s_merged_word & ~`PWM_INTR_VALID_MASK) == 0;
        end
        `PWM_INTR_TEST_OFFSET: s_access_legal = (s_masked_wdata & ~`PWM_INTR_VALID_MASK) == 0;
        `PWM_CAPTURE_CTRL_OFFSET: begin
          s_merged_word  = merge_write({31'h0, s_capture_enable_q}, pwdata_i, s_write_mask);
          s_access_legal = (s_merged_word & ~`PWM_CAPTURE_CTRL_VALID_MASK) == 0;
        end
        `PWM_CAPTURE_DIVIDER_OFFSET: begin
          s_merged_word = merge_write({8'h00, s_capture_divider_q}, pwdata_i, s_write_mask);
          s_access_legal = !s_capture_enable_q &&
              ((s_merged_word & ~`PWM_TIMER_DIVIDER_VALID_MASK) == 0) &&
              (s_merged_word >= `PWM_TIMER_DIVIDER_MIN);
        end
        `PWM_CAPTURE0_CTRL_OFFSET, `PWM_CAPTURE1_CTRL_OFFSET: begin
          if (paddr_i == `PWM_CAPTURE0_CTRL_OFFSET)
            s_merged_word = merge_write(s_capture_channel_ctrl_q[0], pwdata_i, s_write_mask);
          else s_merged_word = merge_write(s_capture_channel_ctrl_q[1], pwdata_i, s_write_mask);
          s_access_legal = !s_capture_enable_q &&
              ((s_merged_word & ~`PWM_CAPTURE_CH_VALID_MASK) == 0) &&
              (!s_merged_word[0] || (s_merged_word[2:1] != 0)) &&
              (s_merged_word[10:8] <= `PWM_CAPTURE_FIFO_DEPTH);
        end
        default: begin
          s_access_legal = 1'b0;
          for (int timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin
            if (address_in_block(paddr_i, TIMER_BASE_ADDRESS, timer, TIMER_BLOCK_STRIDE)) begin
              s_access_legal = !s_timer_status[timer][2];
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_TIMER_CTRL_OFFSET: begin
                  s_merged_word =
                      merge_write({26'h0000000, s_timer_ctrl_q[timer]}, pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_TIMER_CTRL_VALID_MASK) == 0;
                end
                `PWM_TIMER_DIVIDER_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_timer_divider_q[timer]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_TIMER_DIVIDER_VALID_MASK) == 0) &&
                                    (s_merged_word >= `PWM_TIMER_DIVIDER_MIN);
                end
                `PWM_TIMER_PERIOD_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_timer_period_q[timer]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_TIMER_PERIOD_VALID_MASK) == 0) &&
                                    (s_merged_word >= `PWM_TIMER_PERIOD_MIN) &&
                                    (s_merged_word > {8'h00, s_timer_phase_q[timer]});
                end
                `PWM_TIMER_PHASE_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_timer_phase_q[timer]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_TIMER_PHASE_VALID_MASK) == 0) &&
                                    (s_merged_word < {8'h00, s_timer_period_q[timer]});
                end
                default: s_access_legal = 1'b0;
              endcase
            end
          end
          for (int channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin
            if (address_in_block(
                    paddr_i, CHANNEL_BASE_ADDRESS, channel, CHANNEL_BLOCK_STRIDE
                )) begin
              s_access_legal = !s_channel_status[channel][5];
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_CHANNEL_CTRL_OFFSET: begin
                  s_merged_word = merge_write({29'h00000000, s_channel_ctrl_q[channel]}, pwdata_i,
                                              s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_CHANNEL_CTRL_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_PHASE_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_channel_phase_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_CHANNEL_VALUE_VALID_MASK) == 0) &&
                      (s_merged_word[23:0] < s_timer_period_q[s_channel_ctrl_q[channel][1]]) &&
                      (s_channel_duty_q[channel] <=
                       (s_timer_period_q[s_channel_ctrl_q[channel][1]] - s_merged_word[23:0]));
                end
                `PWM_CHANNEL_DUTY_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_channel_duty_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= !s_channel_status[channel][3] &&
                      ((s_merged_word & ~`PWM_CHANNEL_VALUE_VALID_MASK) == 0) &&
                      (s_merged_word[23:0] <=
                       (s_timer_period_q[s_channel_ctrl_q[channel][1]] -
                        s_channel_phase_q[channel]));
                end
                `PWM_CHANNEL_ACTION_OFFSET: begin
                  s_merged_word =
                      merge_write({16'h0000, s_channel_action_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_CHANNEL_ACTION_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_FORCE_OFFSET: begin
                  s_merged_word =
                      merge_write({30'h0, s_channel_force_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_CHANNEL_FORCE_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_FADE_CTRL_OFFSET: begin
                  s_merged_word = merge_write(
                    {
                      20'h00000,
                      s_channel_fade_segments_q[channel],
                      3'h0,
                      s_channel_fade_gamma_q[channel],
                      4'h0
                    },
                    pwdata_i,
                    s_write_mask
                  );
                  s_access_legal &= ((s_merged_word & ~`PWM_FADE_CTRL_VALID_MASK) == 0) &&
                      (!s_merged_word[0] ||
                       ((s_channel_fade_step_q[channel] != 0) &&
                        (!s_merged_word[4] || ((s_merged_word[11:8] >= 1) &&
                                               (s_merged_word[11:8] <=
                                                `PWM_GAMMA_SEGMENT_COUNT)))));
                end
                `PWM_CHANNEL_FADE_TARGET_OFFSET: begin
                  s_merged_word = merge_write({8'h00, s_channel_fade_target_q[channel]}, pwdata_i,
                                              s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_CHANNEL_VALUE_VALID_MASK) == 0) &&
                      (s_merged_word[23:0] <=
                       (s_timer_period_q[s_channel_ctrl_q[channel][1]] -
                        s_channel_phase_q[channel]));
                end
                `PWM_CHANNEL_FADE_STEP_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_channel_fade_step_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_FADE_STEP_VALID_MASK) == 0);
                end
                `PWM_CHANNEL_FADE_INTERVAL_OFFSET: begin
                  s_merged_word = merge_write({16'h0000, s_channel_fade_interval_q[channel]},
                                              pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_FADE_INTERVAL_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_GAMMA_INDEX_OFFSET: begin
                  s_merged_word =
                      merge_write({29'h0, s_gamma_index_q[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_GAMMA_INDEX_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_GAMMA_TARGET_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_gamma_target_read[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= ((s_merged_word & ~`PWM_CHANNEL_VALUE_VALID_MASK) == 0) &&
                      (s_merged_word[23:0] <=
                       (s_timer_period_q[s_channel_ctrl_q[channel][1]] -
                        s_channel_phase_q[channel]));
                end
                `PWM_CHANNEL_GAMMA_STEP_OFFSET: begin
                  s_merged_word =
                      merge_write({8'h00, s_gamma_step_read[channel]}, pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_FADE_STEP_VALID_MASK) == 0;
                end
                `PWM_CHANNEL_GAMMA_INTERVAL_OFFSET: begin
                  s_merged_word = merge_write({16'h0000, s_gamma_interval_read[channel]}, pwdata_i,
                                              s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_FADE_INTERVAL_VALID_MASK) == 0;
                end
                default: s_access_legal = 1'b0;
              endcase
            end
          end
          for (int operator = 0; operator < `PWM_OPERATOR_COUNT; operator++) begin
            if (address_in_block(
                    paddr_i, OPERATOR_BASE_ADDRESS, operator, OPERATOR_BLOCK_STRIDE
                )) begin
              s_access_legal = !s_ctrl_q[0] && !s_safety_lock_q;
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_OPERATOR_CTRL_OFFSET: begin
                  s_merged_word = merge_write({30'h00000000, s_operator_ctrl_q[operator]}, pwdata_i,
                                              s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_OPERATOR_CTRL_VALID_MASK) == 0;
                end
                `PWM_OPERATOR_DEADTIME_OFFSET:
                s_merged_word =
                    merge_write(s_operator_deadtime_q[operator], pwdata_i, s_write_mask);
                `PWM_OPERATOR_CARRIER_OFFSET: begin
                  s_merged_word =
                      merge_write(s_operator_carrier_q[operator], pwdata_i, s_write_mask);
                  s_access_legal &= (s_merged_word & ~`PWM_OPERATOR_CARRIER_VALID_MASK) == 0;
                  if (s_operator_ctrl_q[operator][1]) begin
                    s_access_legal &= (s_merged_word[7:0] >= 2) &&
                                      (s_merged_word[15:8] <= s_merged_word[7:0]);
                  end
                end
                default: s_access_legal = 1'b0;
              endcase
            end
          end
        end
      endcase
    end else if (s_transfer) begin
      s_access_legal = 1'b0;
    end
  end

  assign pslverr_o        = s_transfer && !s_access_legal;
  assign s_capture_pop[0] = s_read && s_access_legal && (paddr_i == `PWM_CAPTURE0_DATA_OFFSET);
  assign s_capture_pop[1] = s_read && s_access_legal && (paddr_i == `PWM_CAPTURE1_DATA_OFFSET);

  always_comb begin
    s_ctrl_d                 = s_ctrl_q;
    s_safety_lock_d          = s_safety_lock_q;
    s_fault_ctrl_d           = s_fault_ctrl_q;
    s_fault_safe_d           = s_fault_safe_q;
    s_intr_state_d           = s_intr_state_q;
    s_intr_enable_d          = s_intr_enable_q;
    s_capture_enable_d       = s_capture_enable_q;
    s_capture_divider_d      = s_capture_divider_q;
    s_command_d              = '0;
    s_gamma_write_target_d   = '0;
    s_gamma_write_step_d     = '0;
    s_gamma_write_interval_d = '0;

    for (int timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin
      s_timer_ctrl_d[timer]    = s_timer_ctrl_q[timer];
      s_timer_divider_d[timer] = s_timer_divider_q[timer];
      s_timer_period_d[timer]  = s_timer_period_q[timer];
      s_timer_phase_d[timer]   = s_timer_phase_q[timer];
    end
    for (int channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin
      s_channel_ctrl_d[channel]          = s_channel_ctrl_q[channel];
      s_channel_phase_d[channel]         = s_channel_phase_q[channel];
      s_channel_duty_d[channel]          = s_channel_duty_q[channel];
      s_channel_action_d[channel]        = s_channel_action_q[channel];
      s_channel_force_d[channel]         = s_channel_force_q[channel];
      s_channel_fade_gamma_d[channel]    = s_channel_fade_gamma_q[channel];
      s_channel_fade_segments_d[channel] = s_channel_fade_segments_q[channel];
      s_channel_fade_target_d[channel]   = s_channel_fade_target_q[channel];
      s_channel_fade_step_d[channel]     = s_channel_fade_step_q[channel];
      s_channel_fade_interval_d[channel] = s_channel_fade_interval_q[channel];
      s_gamma_index_d[channel]           = s_gamma_index_q[channel];
      s_fade_command_d[channel]          = '0;
      s_gamma_target_write_d[channel]    = s_gamma_target_write_q[channel];
      s_gamma_step_write_d[channel]      = s_gamma_step_write_q[channel];
      s_gamma_interval_write_d[channel]  = s_gamma_interval_write_q[channel];
    end
    for (int operator = 0; operator < `PWM_OPERATOR_COUNT; operator++) begin
      s_operator_ctrl_d[operator]     = s_operator_ctrl_q[operator];
      s_operator_deadtime_d[operator] = s_operator_deadtime_q[operator];
      s_operator_carrier_d[operator]  = s_operator_carrier_q[operator];
    end
    for (int capture_channel = 0; capture_channel < `PWM_CAPTURE_COUNT; capture_channel++) begin
      s_capture_channel_ctrl_d[capture_channel] = s_capture_channel_ctrl_q[capture_channel];
    end

    if (s_write && s_access_legal) begin
      unique case (paddr_i)
        `PWM_CTRL_OFFSET: s_ctrl_d = merge_write(s_ctrl_q, pwdata_i, s_write_mask);
        `PWM_COMMAND_OFFSET: begin
          s_command_d[0] = s_masked_wdata[0];
          s_command_d[1] = s_masked_wdata[1];
          s_command_d[2] = s_masked_wdata[2];
          s_command_d[3] = s_masked_wdata[3];
        end
        `PWM_SAFETY_LOCK_OFFSET: s_safety_lock_d = s_safety_lock_q | s_masked_wdata[0];
        `PWM_FAULT_CTRL_OFFSET:
        s_fault_ctrl_d = merge_write8(s_fault_ctrl_q, pwdata_i[7:0], s_write_mask[7:0]);
        `PWM_FAULT_SAFE_OFFSET:
        s_fault_safe_d = merge_write8(s_fault_safe_q, pwdata_i[7:0], s_write_mask[7:0]);
        `PWM_FAULT_CLEAR_OFFSET: s_command_d[4] = s_masked_wdata[0];
        `PWM_INTR_STATE_OFFSET: s_intr_state_d = s_intr_state_q & ~s_masked_wdata[14:0];
        `PWM_INTR_ENABLE_OFFSET:
        s_intr_enable_d = merge_write15(s_intr_enable_q, pwdata_i[14:0], s_write_mask[14:0]);
        `PWM_INTR_TEST_OFFSET: s_intr_state_d = s_intr_state_q | s_masked_wdata[14:0];
        `PWM_CAPTURE_CTRL_OFFSET: begin
          s_capture_enable_d = merge_write1(s_capture_enable_q, pwdata_i[0], s_write_mask[0]);
          s_command_d[5]     = s_masked_wdata[1];
        end
        `PWM_CAPTURE_DIVIDER_OFFSET:
        s_capture_divider_d =
            merge_write24(s_capture_divider_q, pwdata_i[23:0], s_write_mask[23:0]);
        `PWM_CAPTURE0_CTRL_OFFSET:
        s_capture_channel_ctrl_d[0] =
            merge_write(s_capture_channel_ctrl_q[0], pwdata_i, s_write_mask);
        `PWM_CAPTURE1_CTRL_OFFSET:
        s_capture_channel_ctrl_d[1] =
            merge_write(s_capture_channel_ctrl_q[1], pwdata_i, s_write_mask);
        default: begin
          for (int timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin
            if (address_in_block(paddr_i, TIMER_BASE_ADDRESS, timer, TIMER_BLOCK_STRIDE)) begin
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_TIMER_CTRL_OFFSET:
                s_timer_ctrl_d[timer] =
                    merge_write6(s_timer_ctrl_q[timer], pwdata_i[5:0], s_write_mask[5:0]);
                `PWM_TIMER_DIVIDER_OFFSET:
                s_timer_divider_d[timer] =
                    merge_write24(s_timer_divider_q[timer], pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_TIMER_PERIOD_OFFSET:
                s_timer_period_d[timer] =
                    merge_write24(s_timer_period_q[timer], pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_TIMER_PHASE_OFFSET:
                s_timer_phase_d[timer] =
                    merge_write24(s_timer_phase_q[timer], pwdata_i[23:0], s_write_mask[23:0]);
                default: begin
                end
              endcase
            end
          end
          for (int channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin
            if (address_in_block(
                    paddr_i, CHANNEL_BASE_ADDRESS, channel, CHANNEL_BLOCK_STRIDE
                )) begin
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_CHANNEL_CTRL_OFFSET:
                s_channel_ctrl_d[channel] =
                    merge_write3(s_channel_ctrl_q[channel], pwdata_i[2:0], s_write_mask[2:0]);
                `PWM_CHANNEL_PHASE_OFFSET:
                s_channel_phase_d[channel] =
                    merge_write24(s_channel_phase_q[channel], pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_CHANNEL_DUTY_OFFSET:
                s_channel_duty_d[channel] =
                    merge_write24(s_channel_duty_q[channel], pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_CHANNEL_ACTION_OFFSET:
                s_channel_action_d[channel] =
                    merge_write16(s_channel_action_q[channel], pwdata_i[15:0], s_write_mask[15:0]);
                `PWM_CHANNEL_FORCE_OFFSET:
                s_channel_force_d[channel] =
                    merge_write2(s_channel_force_q[channel], pwdata_i[1:0], s_write_mask[1:0]);
                `PWM_CHANNEL_FADE_CTRL_OFFSET: begin
                  s_fade_command_d[channel] = s_masked_wdata[4:0];
                  s_channel_fade_gamma_d[channel] =
                      merge_write1(s_channel_fade_gamma_q[channel], pwdata_i[4], s_write_mask[4]);
                  s_channel_fade_segments_d[channel] = merge_write4(
                      s_channel_fade_segments_q[channel], pwdata_i[11:8], s_write_mask[11:8]);
                end
                `PWM_CHANNEL_FADE_TARGET_OFFSET:
                s_channel_fade_target_d[channel] = merge_write24(
                    s_channel_fade_target_q[channel], pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_CHANNEL_FADE_STEP_OFFSET:
                s_channel_fade_step_d[channel] = merge_write24(s_channel_fade_step_q[channel],
                                                               pwdata_i[23:0], s_write_mask[23:0]);
                `PWM_CHANNEL_FADE_INTERVAL_OFFSET:
                s_channel_fade_interval_d[channel] = merge_write16(
                    s_channel_fade_interval_q[channel], pwdata_i[15:0], s_write_mask[15:0]);
                `PWM_CHANNEL_GAMMA_INDEX_OFFSET:
                s_gamma_index_d[channel] =
                    merge_write3(s_gamma_index_q[channel], pwdata_i[2:0], s_write_mask[2:0]);
                `PWM_CHANNEL_GAMMA_TARGET_OFFSET: begin
                  s_gamma_target_write_d[channel] = merge_write24(
                      s_gamma_target_read[channel], pwdata_i[23:0], s_write_mask[23:0]);
                  s_gamma_write_target_d[channel] = 1'b1;
                end
                `PWM_CHANNEL_GAMMA_STEP_OFFSET: begin
                  s_gamma_step_write_d[channel] =
                      merge_write24(s_gamma_step_read[channel], pwdata_i[23:0], s_write_mask[23:0]);
                  s_gamma_write_step_d[channel] = 1'b1;
                end
                `PWM_CHANNEL_GAMMA_INTERVAL_OFFSET: begin
                  s_gamma_interval_write_d[channel] = merge_write16(
                      s_gamma_interval_read[channel], pwdata_i[15:0], s_write_mask[15:0]);
                  s_gamma_write_interval_d[channel] = 1'b1;
                end
                default: begin
                end
              endcase
            end
          end
          for (int operator = 0; operator < `PWM_OPERATOR_COUNT; operator++) begin
            if (address_in_block(
                    paddr_i, OPERATOR_BASE_ADDRESS, operator, OPERATOR_BLOCK_STRIDE
                )) begin
              unique case ({
                6'h00, paddr_i[5:0]
              })
                `PWM_OPERATOR_CTRL_OFFSET:
                s_operator_ctrl_d[operator] =
                    merge_write2(s_operator_ctrl_q[operator], pwdata_i[1:0], s_write_mask[1:0]);
                `PWM_OPERATOR_DEADTIME_OFFSET:
                s_operator_deadtime_d[operator] =
                    merge_write(s_operator_deadtime_q[operator], pwdata_i, s_write_mask);
                `PWM_OPERATOR_CARRIER_OFFSET:
                s_operator_carrier_d[operator] =
                    merge_write(s_operator_carrier_q[operator], pwdata_i, s_write_mask);
                default: begin
                end
              endcase
            end
          end
        end
      endcase
    end

    s_intr_state_d = s_intr_state_d | s_event;
  end

  pwm_core u_pwm_core (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .module_enable_i         (s_ctrl_q[0]),
      .debug_freeze_i          (s_ctrl_q[1]),
      .debug_halted_i          (debug_halted_i),
      .update_i                (s_command_q[0]),
      .software_sync_i         (s_command_q[1]),
      .stop_all_i              (s_command_q[3]),
      .fault_test_i            (s_command_q[2]),
      .fault_clear_i           (s_command_q[4]),
      .fault_enable_i          (s_fault_ctrl_q[0]),
      .fault_active_high_i     (s_fault_ctrl_q[1]),
      .fault_one_shot_i        (s_fault_ctrl_q[2]),
      .fault_filter_i          (s_fault_ctrl_q[7:4]),
      .fault_safe_i            (s_fault_safe_q),
      .timer_ctrl_i            (s_timer_ctrl_q),
      .timer_divider_i         (s_timer_divider_q),
      .timer_period_i          (s_timer_period_q),
      .timer_phase_i           (s_timer_phase_q),
      .channel_ctrl_i          (s_channel_ctrl_q),
      .channel_phase_i         (s_channel_phase_q),
      .channel_duty_i          (s_channel_duty_q),
      .channel_action_i        (s_channel_action_q),
      .channel_force_i         (s_channel_force_q),
      .channel_fade_ctrl_i     (s_fade_command_q),
      .channel_fade_segments_i (s_channel_fade_segments_q),
      .channel_fade_target_i   (s_channel_fade_target_q),
      .channel_fade_step_i     (s_channel_fade_step_q),
      .channel_fade_interval_i (s_channel_fade_interval_q),
      .gamma_write_target_i    (s_gamma_write_target_q),
      .gamma_write_step_i      (s_gamma_write_step_q),
      .gamma_write_interval_i  (s_gamma_write_interval_q),
      .gamma_index_i           (s_gamma_index_q),
      .gamma_target_i          (s_gamma_target_write_q),
      .gamma_step_i            (s_gamma_step_write_q),
      .gamma_interval_i        (s_gamma_interval_write_q),
      .gamma_target_o          (s_gamma_target_read),
      .gamma_step_o            (s_gamma_step_read),
      .gamma_interval_o        (s_gamma_interval_read),
      .operator_ctrl_i         (s_operator_ctrl_q),
      .operator_deadtime_i     (s_operator_deadtime_q),
      .operator_carrier_i      (s_operator_carrier_q),
      .capture_enable_i        (s_capture_enable_q),
      .capture_clear_i         (s_command_q[5]),
      .capture_divider_i       (s_capture_divider_q),
      .capture_channel_ctrl_i  (s_capture_channel_ctrl_q),
      .capture_pop_i           (s_capture_pop),
      .fault_i                 (fault_i),
      .sync_i                  (sync_i),
      .capture_i               (capture_i),
      .pwm_o                   (pwm_o),
      .oe_o                    (oe_o),
      .event_o                 (s_event),
      .status_o                (s_status),
      .fault_status_o          (s_fault_status),
      .output_status_o         (s_output_status),
      .timer_counter_o         (s_timer_counter),
      .timer_active_divider_o  (s_timer_active_divider),
      .timer_active_period_o   (s_timer_active_period),
      .timer_status_o          (s_timer_status),
      .channel_active_phase_o  (s_channel_active_phase),
      .channel_active_duty_o   (s_channel_active_duty),
      .channel_status_o        (s_channel_status),
      .operator_status_o       (s_operator_status),
      .capture_counter_o       (s_capture_counter),
      .capture_data_o          (s_capture_data),
      .capture_status_o        (s_capture_status),
      .capture_channel_status_o(s_capture_channel_status)
  );

  dffr #(32) u_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dffr #(1) u_safety_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_safety_lock_d),
      .dat_o  (s_safety_lock_q)
  );
  dffr #(8) u_fault_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_ctrl_d),
      .dat_o  (s_fault_ctrl_q)
  );
  dffr #(8) u_fault_safe_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_safe_d),
      .dat_o  (s_fault_safe_q)
  );
  dffr #(15) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );
  dffr #(15) u_intr_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_enable_d),
      .dat_o  (s_intr_enable_q)
  );

  dffr #(6) u_command_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_command_d),
      .dat_o  (s_command_q)
  );

  dffr #(4) u_gamma_write_target_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_gamma_write_target_d),
      .dat_o  (s_gamma_write_target_q)
  );

  dffr #(4) u_gamma_write_step_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_gamma_write_step_d),
      .dat_o  (s_gamma_write_step_q)
  );

  dffr #(4) u_gamma_write_interval_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_gamma_write_interval_d),
      .dat_o  (s_gamma_write_interval_q)
  );

  for (genvar timer = 0; timer < `PWM_TIMER_COUNT; timer++) begin : gen_timer_registers
    dffr #(6) u_timer_ctrl_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_timer_ctrl_d[timer]),
        .dat_o  (s_timer_ctrl_q[timer])
    );
    dffr #(24) u_timer_divider_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_timer_divider_d[timer]),
        .dat_o  (s_timer_divider_q[timer])
    );
    dffr #(24) u_timer_period_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_timer_period_d[timer]),
        .dat_o  (s_timer_period_q[timer])
    );
    dffr #(24) u_timer_phase_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_timer_phase_d[timer]),
        .dat_o  (s_timer_phase_q[timer])
    );
  end

  for (genvar channel = 0; channel < `PWM_CHANNEL_COUNT; channel++) begin : gen_channel_registers
    dffr #(3) u_channel_ctrl_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_ctrl_d[channel]),
        .dat_o  (s_channel_ctrl_q[channel])
    );
    dffr #(24) u_channel_phase_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_phase_d[channel]),
        .dat_o  (s_channel_phase_q[channel])
    );
    dffr #(24) u_channel_duty_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_duty_d[channel]),
        .dat_o  (s_channel_duty_q[channel])
    );
    dffr #(16) u_channel_action_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_action_d[channel]),
        .dat_o  (s_channel_action_q[channel])
    );
    dffr #(2) u_channel_force_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_force_d[channel]),
        .dat_o  (s_channel_force_q[channel])
    );
    dffr #(1) u_channel_fade_gamma_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_fade_gamma_d[channel]),
        .dat_o  (s_channel_fade_gamma_q[channel])
    );
    dffr #(4) u_channel_fade_segments_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_fade_segments_d[channel]),
        .dat_o  (s_channel_fade_segments_q[channel])
    );
    dffr #(24) u_channel_fade_target_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_fade_target_d[channel]),
        .dat_o  (s_channel_fade_target_q[channel])
    );
    dffr #(24) u_channel_fade_step_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_fade_step_d[channel]),
        .dat_o  (s_channel_fade_step_q[channel])
    );
    dffr #(16) u_channel_fade_interval_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_fade_interval_d[channel]),
        .dat_o  (s_channel_fade_interval_q[channel])
    );
    dffr #(3) u_gamma_index_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_gamma_index_d[channel]),
        .dat_o  (s_gamma_index_q[channel])
    );
    dffr #(5) u_fade_command_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_fade_command_d[channel]),
        .dat_o  (s_fade_command_q[channel])
    );
    dffr #(24) u_gamma_target_write_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_gamma_target_write_d[channel]),
        .dat_o  (s_gamma_target_write_q[channel])
    );
    dffr #(24) u_gamma_step_write_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_gamma_step_write_d[channel]),
        .dat_o  (s_gamma_step_write_q[channel])
    );
    dffr #(16) u_gamma_interval_write_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_gamma_interval_write_d[channel]),
        .dat_o  (s_gamma_interval_write_q[channel])
    );
  end

  for (
      genvar operator = 0; operator < `PWM_OPERATOR_COUNT; operator++
  ) begin : gen_operator_registers
    dffr #(2) u_operator_ctrl_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_operator_ctrl_d[operator]),
        .dat_o  (s_operator_ctrl_q[operator])
    );
    dffr #(32) u_operator_deadtime_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_operator_deadtime_d[operator]),
        .dat_o  (s_operator_deadtime_q[operator])
    );
    dffr #(32) u_operator_carrier_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_operator_carrier_d[operator]),
        .dat_o  (s_operator_carrier_q[operator])
    );
  end

  dffr #(1) u_capture_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_capture_enable_d),
      .dat_o  (s_capture_enable_q)
  );
  dffr #(24) u_capture_divider_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_capture_divider_d),
      .dat_o  (s_capture_divider_q)
  );
  for (
      genvar capture_channel = 0; capture_channel < `PWM_CAPTURE_COUNT; capture_channel++
  ) begin : gen_capture_registers
    dffr #(32) u_capture_channel_ctrl_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_capture_channel_ctrl_d[capture_channel]),
        .dat_o  (s_capture_channel_ctrl_q[capture_channel])
    );
  end

endmodule
