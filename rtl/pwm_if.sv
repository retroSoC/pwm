// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

interface pwm_if ();
  logic [3:0] pwm_o;
  logic [3:0] oe_o;
  logic       fault_i;
  logic       sync_i;
  logic [1:0] capture_i;
  logic       irq_o;

  modport dut(
      output pwm_o,
      output oe_o,
      input fault_i,
      input sync_i,
      input capture_i,
      output irq_o
  );

  modport soc(
      input pwm_o,
      input oe_o,
      output fault_i,
      output sync_i,
      output capture_i,
      input irq_o
  );

  modport tb(input pwm_o, input oe_o, output fault_i, output sync_i, output capture_i, input irq_o);
endinterface
