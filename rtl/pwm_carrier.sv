// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module pwm_carrier (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       enable_i,
    input  logic [7:0] period_i,
    input  logic [7:0] duty_i,
    input  logic       invert_i,
    input  logic       input_a_i,
    input  logic       input_b_i,
    output logic       output_a_o,
    output logic       output_b_o
    // verilog_format: on
);

  logic [7:0] s_counter_d, s_counter_q;
  logic s_gate;

  always_comb begin
    if (!enable_i || (period_i < 2)) begin
      s_counter_d = '0;
    end else if (s_counter_q >= period_i - 1'b1) begin
      s_counter_d = '0;
    end else begin
      s_counter_d = s_counter_q + 1'b1;
    end
  end

  dffr #(8) u_counter_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_counter_d),
      .dat_o  (s_counter_q)
  );

  assign s_gate     = !enable_i || ((s_counter_q < duty_i) ^ invert_i);
  assign output_a_o = input_a_i && s_gate;
  assign output_b_o = input_b_i && s_gate;

endmodule
