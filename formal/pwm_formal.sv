// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module pwm_formal;

  (* gclk *)logic        clk;
  (* anyseq *)logic        rst_n;
  (* anyseq *)logic        enable;
  (* anyseq *)logic        input_a;
  (* anyseq *)logic        input_b;
  (* anyconst *)logic [15:0] rise_delay;
  (* anyconst *)logic [15:0] fall_delay;

  logic        output_a;
  logic        output_b;
  logic        f_past_valid;

  pwm_deadtime u_dut (
      .clk_i          (clk),
      .rst_n_i        (rst_n),
      .enable_i       (enable),
      .complementary_i(1'b1),
      .rise_delay_i   (rise_delay),
      .fall_delay_i   (fall_delay),
      .input_a_i      (input_a),
      .input_b_i      (input_b),
      .output_a_o     (output_a),
      .output_b_o     (output_b)
  );

  initial begin
    f_past_valid = 1'b0;
    assume (!rst_n);
    assume (rise_delay < 16);
    assume (fall_delay < 16);
  end

  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    assert (!(output_a && output_b));
    if (rst_n && !enable) begin
      assert (!output_a);
      assert (!output_b);
    end
    if (f_past_valid && !$past(rst_n)) begin
      assert (!output_a);
      assert (!output_b);
    end
    cover (rst_n && output_a);
    cover (rst_n && output_b);
  end

endmodule
