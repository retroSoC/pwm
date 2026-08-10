// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module pwm_tickgen (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic [23:0] divider_i,
    output logic        tick_o
    // verilog_format: on
);

  logic [23:0] s_phase_d, s_phase_q;
  logic [24:0] s_phase_sum;

  assign s_phase_sum = {1'b0, s_phase_q} + 25'd256;
  assign tick_o      = enable_i && (divider_i >= 24'h000100) && (s_phase_sum >= {1'b0, divider_i});

  always_comb begin
    if (!enable_i || (divider_i < 24'h000100)) begin
      s_phase_d = '0;
    end else if (tick_o) begin
      s_phase_d = 24'(s_phase_sum - {1'b0, divider_i});
    end else begin
      s_phase_d = s_phase_sum[23:0];
    end
  end

  dffr #(
      .DATA_WIDTH(24)
  ) u_phase_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_d),
      .dat_o  (s_phase_q)
  );

endmodule
