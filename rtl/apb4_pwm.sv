// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apb4_pwm #(
    parameter int PCLK_HZ = 72_000_000
) (
    // verilog_format: off
    input  logic   debug_halted_i,
    apb4_if.slave  apb4,
    pwm_if.dut     pwm
    // verilog_format: on
);

  pwm_reg #(
      .PCLK_HZ(PCLK_HZ)
  ) u_pwm_reg (
      .clk_i         (apb4.pclk),
      .rst_n_i       (apb4.presetn),
      .debug_halted_i(debug_halted_i),
      .paddr_i       (apb4.paddr[11:0]),
      .psel_i        (apb4.psel),
      .penable_i     (apb4.penable),
      .pwrite_i      (apb4.pwrite),
      .pwdata_i      (apb4.pwdata),
      .pstrb_i       (apb4.pstrb),
      .pready_o      (apb4.pready),
      .prdata_o      (apb4.prdata),
      .pslverr_o     (apb4.pslverr),
      .fault_i       (pwm.fault_i),
      .sync_i        (pwm.sync_i),
      .capture_i     (pwm.capture_i),
      .pwm_o         (pwm.pwm_o),
      .oe_o          (pwm.oe_o),
      .irq_o         (pwm.irq_o)
  );

endmodule
