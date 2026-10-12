// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "pwm_define.svh"

// Exercise the production APB wrapper in both reporting modes. A product-side
// register supplies the committed nominal rate; PWM does not implement CDC.
module pwm_clock_report_tb;
  logic        clk;
  logic        rst_n = 1'b0;
  logic [31:0] requested_hz = 32'd24_000_000;
  logic [31:0] committed_hz;
  logic [31:0] unused_hz = '0;

  apb4_if static_apb (
      .pclk   (clk),
      .presetn(rst_n)
  );
  apb4_if runtime_apb (
      .pclk   (clk),
      .presetn(rst_n)
  );
  pwm_if static_pwm ();
  pwm_if runtime_pwm ();

  apb4_pwm u_static (
      .debug_halted_i(1'b0),
      .apb4          (static_apb),
      .pwm           (static_pwm),
      .pclk_hz_i     (unused_hz)
  );
  apb4_pwm #(
      .UseRuntimeClockHz(1'b1)
  ) u_runtime (
      .debug_halted_i(1'b0),
      .apb4          (runtime_apb),
      .pwm           (runtime_pwm),
      .pclk_hz_i     (committed_hz)
  );

  assign runtime_apb.paddr     = static_apb.paddr;
  assign runtime_apb.pprot     = static_apb.pprot;
  assign runtime_apb.psel      = static_apb.psel;
  assign runtime_apb.penable   = static_apb.penable;
  assign runtime_apb.pwrite    = static_apb.pwrite;
  assign runtime_apb.pwdata    = static_apb.pwdata;
  assign runtime_apb.pstrb     = static_apb.pstrb;
  assign static_pwm.fault_i    = 1'b0;
  assign static_pwm.sync_i     = 1'b0;
  assign static_pwm.capture_i  = '0;
  assign runtime_pwm.fault_i   = 1'b0;
  assign runtime_pwm.sync_i    = 1'b0;
  assign runtime_pwm.capture_i = '0;

  always begin
    case (requested_hz)
      32'd24_000_000: #20.833333;
      32'd48_000_000: #10.416667;
      32'd60_000_000: #8.333333;
      default:        $fatal(1, "unsupported test clock rate");
    endcase
    clk = !clk;
  end
  always @(posedge clk) committed_hz <= requested_hz;
  always @(negedge clk) begin
    #0.001;
    if (rst_n && ({static_pwm.pwm_o, static_pwm.oe_o, static_pwm.irq_o} !==
                  {runtime_pwm.pwm_o, runtime_pwm.oe_o, runtime_pwm.irq_o}))
      $fatal(1, "clock reporting changed PWM behavior");
  end

  task automatic idle;
    static_apb.paddr   = '0;
    static_apb.pprot   = '0;
    static_apb.psel    = 1'b0;
    static_apb.penable = 1'b0;
    static_apb.pwrite  = 1'b0;
    static_apb.pwdata  = '0;
    static_apb.pstrb   = '0;
  endtask

  task automatic transfer(input bit write, input logic [11:0] address, input logic [31:0] data,
                          input logic [3:0] strobe, input logic [31:0] static_value,
                          input logic [31:0] runtime_value, input bit error_expected);
    @(negedge clk);
    static_apb.paddr  = {20'd0, address};
    static_apb.psel   = 1'b1;
    static_apb.pwrite = write;
    static_apb.pwdata = data;
    static_apb.pstrb  = strobe;
    @(negedge clk);
    static_apb.penable = 1'b1;
    @(posedge clk);
    if (static_apb.pready !== 1'b1 || runtime_apb.pready !== 1'b1 ||
        static_apb.pslverr !== error_expected || runtime_apb.pslverr !== error_expected)
      $fatal(1, "APB response mismatch at %03h", address);
    if (!write && !error_expected &&
        (static_apb.prdata !== static_value || runtime_apb.prdata !== runtime_value))
      $fatal(
          1,
          "read %03h: static=%08h runtime=%08h expected=%08h/%08h",
          address,
          static_apb.prdata,
          runtime_apb.prdata,
          static_value,
          runtime_value
      );
    @(negedge clk);
    idle();
  endtask

  task automatic write_reg(input logic [11:0] address, input logic [31:0] data);
    transfer(1'b1, address, data, 4'hf, '0, '0, 1'b0);
  endtask

  task automatic read_clock(input logic [31:0] expected_hz);
    transfer(1'b0, `PWM_CLOCK_HZ_OFFSET, '0, '0, 32'd72_000_000, expected_hz, 1'b0);
  endtask

  task automatic check_rate(input logic [31:0] rate, input realtime period_half);
    int      high_cycles;
    realtime edge_start;
    realtime elapsed;
    // Both controllers are disabled, with no APB request in flight.
    @(negedge clk);
    requested_hz = rate;
    unused_hz    = ~rate;
    repeat (4) @(posedge clk);
    read_clock(rate);
    @(negedge clk);
    unused_hz = 'x;  // The default mode must ignore even an unknown input.
    read_clock(rate);
    transfer(1'b1, `PWM_CLOCK_HZ_OFFSET, 32'hdead_beef, 4'hf, '0, '0, 1'b1);
    transfer(1'b1, `PWM_CLOCK_HZ_OFFSET, 32'h0000_1234, 4'h3, '0, '0, 1'b1);
    transfer(1'b0, `PWM_CLOCK_HZ_OFFSET + 12'd1, '0, '0, '0, '0, 1'b1);
    read_clock(rate);

    write_reg(`PWM_CTRL_OFFSET, `PWM_CTRL_ENABLE_MASK);
    repeat (32) @(posedge clk);
    high_cycles = 0;
    edge_start  = $realtime;
    repeat (64) begin
      @(posedge clk);
      if (runtime_pwm.pwm_o[0] === 1'b1) high_cycles++;
      else if (runtime_pwm.pwm_o[0] !== 1'b0) $fatal(1, "unknown PWM sample");
    end
    elapsed = $realtime - edge_start;
    if (high_cycles != 32 || runtime_pwm.oe_o[0] !== 1'b1)
      $fatal(1, "PWM duty changed at %0d Hz: high=%0d", rate, high_cycles);
    if (elapsed < (128.0 * period_half - 0.2) || elapsed > (128.0 * period_half + 0.2))
      $fatal(1, "test clock period does not match the supplied rate");
    read_clock(rate);
    transfer(1'b0, `PWM_TIMER_BASE_OFFSET + `PWM_TIMER_ACTIVE_PERIOD_OFFSET, '0, '0, 32'd16, 32'd16,
             1'b0);
    write_reg(`PWM_CTRL_OFFSET, '0);
    repeat (4) @(posedge clk);
  endtask

  initial begin
    clk          = 1'b0;
    committed_hz = 32'd24_000_000;
    idle();
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    read_clock(32'd24_000_000);
    transfer(1'b0, `PWM_IP_ID_OFFSET, '0, '0, `PWM_IP_ID_VALUE, `PWM_IP_ID_VALUE, 1'b0);
    transfer(1'b0, `PWM_IP_VERSION_OFFSET, '0, '0, `PWM_IP_VERSION_VALUE, `PWM_IP_VERSION_VALUE,
             1'b0);
    write_reg(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_DIVIDER_OFFSET, 32'h100);
    write_reg(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_PERIOD_OFFSET, 32'd16);
    write_reg(`PWM_TIMER_BASE_OFFSET + `PWM_TIMER_CTRL_OFFSET, 32'd1);
    write_reg(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_DUTY_OFFSET, 32'd8);
    // Phase-up at count 0 drives high; duty-up at count 8 drives low.
    // The zero/wrap event precedes phase-up by a clock and is not used here.
    write_reg(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_ACTION_OFFSET, 32'h60);
    write_reg(`PWM_CHANNEL_BASE_OFFSET + `PWM_CHANNEL_CTRL_OFFSET, 32'd1);
    write_reg(`PWM_COMMAND_OFFSET, `PWM_COMMAND_UPDATE_MASK);
    repeat (4) @(posedge clk);
    check_rate(32'd24_000_000, 20.833333);
    check_rate(32'd48_000_000, 10.416667);
    check_rate(32'd60_000_000, 8.333333);
    // A peripheral reset does not reset the product's committed frequency.
    @(negedge clk);
    rst_n = 1'b0;
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    read_clock(32'd60_000_000);
    transfer(1'b0, `PWM_CTRL_OFFSET, '0, '0, '0, '0, 1'b0);
    @(negedge clk);
    requested_hz = 32'd24_000_000;
    repeat (4) @(posedge clk);
    read_clock(32'd24_000_000);
    $display("PWM_CLOCK_REPORT_TEST_PASS rates=24/48/60/24 static=72 reset=60 readonly=1");
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "PWM clock-report timeout");
  end
endmodule
