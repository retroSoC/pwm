// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "pwm_define.svh"

module pwm_tb;

  logic        clk_i;
  logic        rst_n_i;
  logic        debug_halted_i;
  logic [11:0] paddr_i;
  logic        psel_i;
  logic        penable_i;
  logic        pwrite_i;
  logic [31:0] pwdata_i;
  logic [ 3:0] pstrb_i;
  logic        pready_o;
  logic [31:0] prdata_o;
  logic        pslverr_o;
  logic        fault_i;
  logic        sync_i;
  logic [ 1:0] capture_i;
  logic [ 3:0] pwm_o;
  logic [ 3:0] oe_o;
  logic        irq_o;
  logic        last_error;

  always #5 clk_i = ~clk_i;

  pwm_reg #(
      .PCLK_HZ(1_000_000)
  ) u_pwm_reg (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(debug_halted_i),
      .paddr_i       (paddr_i),
      .psel_i        (psel_i),
      .penable_i     (penable_i),
      .pwrite_i      (pwrite_i),
      .pwdata_i      (pwdata_i),
      .pstrb_i       (pstrb_i),
      .pready_o      (pready_o),
      .prdata_o      (prdata_o),
      .pslverr_o     (pslverr_o),
      .fault_i       (fault_i),
      .sync_i        (sync_i),
      .capture_i     (capture_i),
      .pwm_o         (pwm_o),
      .oe_o          (oe_o),
      .irq_o         (irq_o)
  );

  task automatic bus_idle;
    paddr_i   = '0;
    psel_i    = 1'b0;
    penable_i = 1'b0;
    pwrite_i  = 1'b0;
    pwdata_i  = '0;
    pstrb_i   = '0;
  endtask

  task automatic bus_write(input logic [11:0] address, input logic [31:0] data);
    @(negedge clk_i);
    paddr_i  = address;
    psel_i   = 1'b1;
    pwrite_i = 1'b1;
    pwdata_i = data;
    pstrb_i  = 4'hF;
    @(negedge clk_i);
    penable_i = 1'b1;
    @(posedge clk_i);
    #1 last_error = pslverr_o;
    @(negedge clk_i);
    bus_idle();
  endtask

  task automatic bus_read(input logic [11:0] address, output logic [31:0] data);
    @(negedge clk_i);
    paddr_i  = address;
    psel_i   = 1'b1;
    pwrite_i = 1'b0;
    @(negedge clk_i);
    penable_i = 1'b1;
    @(posedge clk_i);
    #1 begin
      data       = prdata_o;
      last_error = pslverr_o;
    end
    @(negedge clk_i);
    bus_idle();
  endtask

  initial begin
    logic [31:0] value;
    int          high_count;
    int          low_count;

    clk_i          = 1'b0;
    rst_n_i        = 1'b0;
    debug_halted_i = 1'b0;
    fault_i        = 1'b0;
    sync_i         = 1'b0;
    capture_i      = '0;
    last_error     = 1'b0;
    high_count     = 0;
    low_count      = 0;
    bus_idle();
    repeat (5) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(posedge clk_i);

    bus_read(`PWM_IP_ID_OFFSET, value);
    if (last_error || (value != `PWM_IP_ID_VALUE)) $fatal(1, "PWM ID mismatch");
    bus_read(12'h003, value);
    if (!last_error) $fatal(1, "unaligned access accepted");

    bus_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_DIVIDER_OFFSET, 32'h0000_0100);
    bus_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_PERIOD_OFFSET, 32'd16);
    bus_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_PHASE_OFFSET, 32'd0);
    bus_write(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_CTRL_OFFSET, 32'h0000_0001);
    bus_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_PHASE_OFFSET, 32'd0);
    bus_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_DUTY_OFFSET, 32'd8);
    bus_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_ACTION_OFFSET, 32'h0000_0042);
    bus_write(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_CTRL_OFFSET, 32'h0000_0001);
    bus_write(`PWM_FAULT_CTRL_OFFSET, 32'h0000_0007);
    bus_write(`PWM_INTR_ENABLE_OFFSET, `PWM_INTR_FAULT_MASK);
    bus_write(`PWM_COMMAND_OFFSET, `PWM_COMMAND_UPDATE_MASK);
    repeat (4) @(posedge clk_i);
    bus_write(`PWM_CTRL_OFFSET, `PWM_CTRL_ENABLE_MASK);

    repeat (48) begin
      @(posedge clk_i);
      if (pwm_o[0]) high_count++;
      else low_count++;
    end
    if ((high_count < 8) || (low_count < 8) || !oe_o[0]) begin
      $fatal(1, "PWM waveform invalid high=%0d low=%0d", high_count, low_count);
    end

    fault_i = 1'b1;
    #1;
    if (pwm_o != 0) $fatal(1, "fault safety override failed");
    repeat (5) @(posedge clk_i);
    bus_read(`PWM_FAULT_STATUS_OFFSET, value);
    if (!value[3] || !irq_o) $fatal(1, "fault did not latch or interrupt");

    $display("PWM_TEST_PASS");
    $finish;
  end

endmodule
