// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module pwm_deadtime (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        complementary_i,
    input  logic [15:0] rise_delay_i,
    input  logic [15:0] fall_delay_i,
    input  logic        input_a_i,
    input  logic        input_b_i,
    output logic        output_a_o,
    output logic        output_b_o
    // verilog_format: on
);

  logic s_output_a_d, s_output_a_q;
  logic s_output_b_d, s_output_b_q;
  logic [15:0] s_counter_a_d, s_counter_a_q;
  logic [15:0] s_counter_b_d, s_counter_b_q;
  logic s_desired_a, s_desired_b;

  assign s_desired_a = enable_i && input_a_i;
  assign s_desired_b = enable_i && (complementary_i ? ~input_a_i : input_b_i);

  always_comb begin
    s_output_a_d  = s_output_a_q;
    s_output_b_d  = s_output_b_q;
    s_counter_a_d = s_counter_a_q;
    s_counter_b_d = s_counter_b_q;

    if (!enable_i) begin
      s_output_a_d  = 1'b0;
      s_output_b_d  = 1'b0;
      s_counter_a_d = '0;
      s_counter_b_d = '0;
    end else if (!complementary_i) begin
      s_output_a_d  = input_a_i;
      s_output_b_d  = input_b_i;
      s_counter_a_d = '0;
      s_counter_b_d = '0;
    end else begin
      if (!s_desired_a) begin
        s_output_a_d  = 1'b0;
        s_counter_a_d = '0;
      end else if (!s_output_b_q && !s_output_a_q) begin
        if (s_counter_a_q >= rise_delay_i) begin
          s_output_a_d = 1'b1;
        end else begin
          s_counter_a_d = s_counter_a_q + 1'b1;
        end
      end

      if (!s_desired_b) begin
        s_output_b_d  = 1'b0;
        s_counter_b_d = '0;
      end else if (!s_output_a_q && !s_output_b_q) begin
        if (s_counter_b_q >= fall_delay_i) begin
          s_output_b_d = 1'b1;
        end else begin
          s_counter_b_d = s_counter_b_q + 1'b1;
        end
      end
    end
  end

  dffr #(1) u_output_a_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_a_d),
      .dat_o  (s_output_a_q)
  );

  dffr #(1) u_output_b_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_b_d),
      .dat_o  (s_output_b_q)
  );

  dffr #(16) u_counter_a_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_counter_a_d),
      .dat_o  (s_counter_a_q)
  );

  dffr #(16) u_counter_b_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_counter_b_d),
      .dat_o  (s_counter_b_q)
  );

  assign output_a_o = s_output_a_q;
  assign output_b_o = s_output_b_q;

endmodule
