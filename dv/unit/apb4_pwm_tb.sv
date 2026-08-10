// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "pwm_define.svh"

module apb4_pwm_tb;

  logic clk_i;
  logic rst_n_i;
  logic debug_halted;
  logic last_error;
  int   high_cycles;
  int   low_cycles;

  apb4_if u_apb4_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  pwm_if u_pwm_if ();

  apb4_pwm #(
      .PCLK_HZ(1_000_000)
  ) u_apb4_pwm (
      .debug_halted_i(debug_halted),
      .apb4          (u_apb4_if),
      .pwm           (u_pwm_if)
  );

  always #5 clk_i = ~clk_i;

  task automatic apb_idle;
    u_apb4_if.paddr   = '0;
    u_apb4_if.pprot   = '0;
    u_apb4_if.psel    = 1'b0;
    u_apb4_if.penable = 1'b0;
    u_apb4_if.pwrite  = 1'b0;
    u_apb4_if.pwdata  = '0;
    u_apb4_if.pstrb   = '0;
  endtask

  task automatic apb_write(input logic [11:0] address, input logic [31:0] data,
                           input logic [3:0] strobe = 4'hF);
    @(negedge clk_i);
    u_apb4_if.paddr  = {20'h00000, address};
    u_apb4_if.psel   = 1'b1;
    u_apb4_if.pwrite = 1'b1;
    u_apb4_if.pwdata = data;
    u_apb4_if.pstrb  = strobe;
    @(negedge clk_i);
    u_apb4_if.penable = 1'b1;
    @(posedge clk_i);
    #1 last_error = u_apb4_if.pslverr;
    @(negedge clk_i);
    apb_idle();
  endtask

  task automatic apb_read(input logic [11:0] address, output logic [31:0] data);
    @(negedge clk_i);
    u_apb4_if.paddr  = {20'h00000, address};
    u_apb4_if.psel   = 1'b1;
    u_apb4_if.pwrite = 1'b0;
    u_apb4_if.pstrb  = '0;
    @(negedge clk_i);
    u_apb4_if.penable = 1'b1;
    @(posedge clk_i);
    data       = u_apb4_if.prdata;
    last_error = u_apb4_if.pslverr;
    @(negedge clk_i);
    apb_idle();
  endtask

  task automatic expect_read(input logic [11:0] address, input logic [31:0] expected);
    logic [31:0] value;
    apb_read(address, value);
    if (last_error || (value !== expected)) begin
      $fatal(1, "read mismatch address=%03h expected=%08h actual=%08h error=%0b", address,
             expected, value, last_error);
    end
  endtask

  task automatic configure_basic_pwm;
    apb_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_DIVIDER_OFFSET, 32'h0000_0100);
    apb_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_PERIOD_OFFSET, 32'd16);
    apb_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_PHASE_OFFSET, 32'd0);
    apb_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_CTRL_OFFSET, 32'h0000_0001);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_PHASE_OFFSET, 32'd0);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_DUTY_OFFSET, 32'd8);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_ACTION_OFFSET, 32'h0000_0042);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_CTRL_OFFSET, 32'h0000_0001);
    apb_write(`PWM_FAULT_CTRL_OFFSET, 32'h0000_0007);
    apb_write(`PWM_FAULT_SAFE_OFFSET, 32'h0000_0000);
    apb_write(`PWM_INTR_ENABLE_OFFSET,
              `PWM_INTR_TIMER0_ZERO_MASK | `PWM_INTR_FADE0_DONE_MASK | `PWM_INTR_FAULT_MASK |
                  `PWM_INTR_CAPTURE0_MASK);
    apb_write(`PWM_COMMAND_OFFSET, `PWM_COMMAND_UPDATE_MASK);
    repeat (4) @(posedge clk_i);
  endtask

  initial begin
    logic [31:0] value;

    clk_i              = 1'b0;
    rst_n_i            = 1'b0;
    debug_halted       = 1'b0;
    last_error         = 1'b0;
    u_pwm_if.fault_i   = 1'b0;
    u_pwm_if.sync_i    = 1'b0;
    u_pwm_if.capture_i = '0;
    high_cycles        = 0;
    low_cycles         = 0;
    apb_idle();

    repeat (5) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(posedge clk_i);

    expect_read(`PWM_IP_ID_OFFSET, `PWM_IP_ID_VALUE);
    expect_read(`PWM_IP_VERSION_OFFSET, `PWM_IP_VERSION_VALUE);
    apb_read(`PWM_CAPABILITY_OFFSET, value);
    if (last_error || (value[31:24] != `PWM_ABI_VERSION) || (value[15:12] != 4)) begin
      $fatal(1, "capability mismatch: %08h", value);
    end

    apb_read(12'h003, value);
    if (!last_error) $fatal(1, "unaligned APB access was accepted");
    apb_write(`PWM_STATUS_OFFSET, 32'h1);
    if (!last_error) $fatal(1, "read-only APB write was accepted");

    configure_basic_pwm();
    apb_write(`PWM_CTRL_OFFSET, `PWM_CTRL_ENABLE_MASK | `PWM_CTRL_DEBUG_FREEZE_MASK);
    repeat (40) begin
      @(posedge clk_i);
      if (u_pwm_if.pwm_o[0]) high_cycles++;
      else low_cycles++;
    end
    if ((high_cycles < 6) || (low_cycles < 6) || !u_pwm_if.oe_o[0]) begin
      $fatal(1, "basic PWM waveform invalid high=%0d low=%0d oe=%0b", high_cycles, low_cycles,
             u_pwm_if.oe_o[0]);
    end

    debug_halted = 1'b1;
    apb_read(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_COUNTER_OFFSET, value);
    repeat (8) @(posedge clk_i);
    begin
      logic [31:0] frozen_value;
      apb_read(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_COUNTER_OFFSET, frozen_value);
      if (frozen_value != value) $fatal(1, "debug freeze did not stop timer");
    end
    debug_halted     = 1'b0;

    u_pwm_if.fault_i = 1'b1;
    #1;
    if ((u_pwm_if.pwm_o != 0) || (u_pwm_if.oe_o == 0)) begin
      $fatal(1, "fault did not immediately force safe-low outputs");
    end
    repeat (5) @(posedge clk_i);
    apb_read(`PWM_FAULT_STATUS_OFFSET, value);
    if (last_error || !value[3] || !u_pwm_if.irq_o) $fatal(1, "fault was not latched");
    u_pwm_if.fault_i = 1'b0;
    repeat (4) @(posedge clk_i);
    apb_write(`PWM_FAULT_CLEAR_OFFSET, `PWM_FAULT_CLEAR_MASK);

    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_FADE_TARGET_OFFSET, 32'd4);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_FADE_STEP_OFFSET, 32'd2);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_FADE_INTERVAL_OFFSET, 32'd1);
    apb_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_FADE_CTRL_OFFSET, `PWM_FADE_CTRL_START_MASK);
    repeat (80) @(posedge clk_i);
    apb_read(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_ACTIVE_DUTY_OFFSET, value);
    if (last_error || (value != 4)) $fatal(1, "linear fade did not reach target: %0d", value);

    apb_write(`PWM_CTRL_OFFSET, 32'h0);
    apb_write(`PWM_OPERATOR_BASE_OFFSET + `PWM_OPERATOR_DEADTIME_OFFSET, 32'h0002_0002);
    apb_write(`PWM_OPERATOR_BASE_OFFSET + `PWM_OPERATOR_CTRL_OFFSET,
              `PWM_OPERATOR_CTRL_COMPLEMENT_MASK);
    apb_write(`PWM_COMMAND_OFFSET, `PWM_COMMAND_UPDATE_MASK);
    repeat (4) @(posedge clk_i);
    apb_write(`PWM_CTRL_OFFSET, `PWM_CTRL_ENABLE_MASK);
    repeat (80) begin
      @(posedge clk_i);
      if (&u_pwm_if.pwm_o[1:0]) $fatal(1, "complementary outputs overlapped");
    end

    apb_write(`PWM_CAPTURE_DIVIDER_OFFSET, 32'h0000_0100);
    apb_write(`PWM_CAPTURE0_CTRL_OFFSET,
              `PWM_CAPTURE_CH_ENABLE_MASK | `PWM_CAPTURE_CH_RISE_MASK |
                  (32'd1 << `PWM_CAPTURE_CH_WATERMARK_SHIFT));
    apb_write(`PWM_CAPTURE_CTRL_OFFSET,
              `PWM_CAPTURE_CTRL_ENABLE_MASK | `PWM_CAPTURE_CTRL_CLEAR_MASK);
    repeat (5) @(posedge clk_i);
    u_pwm_if.capture_i[0] = 1'b1;
    repeat (5) @(posedge clk_i);
    apb_read(`PWM_CAPTURE0_STATUS_OFFSET, value);
    if (last_error || value[3] || (value[2:0] == 0)) begin
      $fatal(1, "capture FIFO did not record the edge: %08h", value);
    end
    apb_read(`PWM_CAPTURE0_DATA_OFFSET, value);
    if (last_error || (value == 0)) $fatal(1, "capture timestamp missing: %0d", value);

    $display("APB4_PWM_TEST_PASS");
    $finish;
  end

endmodule
