// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// pwm is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "apb4_if.svh"
`include "pwm_define.svh"

module apb4_pwm (
`ifdef __VERILOG__
    `apb4_slave_if(apb4),
    output [3:0] pwm_pwm_o,
    output       pwm_irq_o
`else
    apb4_if.slave apb4,
    pwm_if.dut    pwm
`endif
);

`ifndef __VERILOG__
  `apb4_slave_if2wire(apb4, apb4);
  logic pwm_pwm_o;
  logic pwm_irq_o;
  assign pwm.pwm_o = pwm_pwm_o;
  assign pwm.irq_o = pwm_irq_o;
`endif

  logic [3:0] s_apb4_addr;
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic [`PWM_CTRL_WIDTH-1:0] s_pwm_ctrl_d, s_pwm_ctrl_q;
  logic s_pwm_ctrl_en;
  logic [`PWM_PSCR_WIDTH-1:0] s_pwm_pscr_d, s_pwm_pscr_q;
  logic s_pwm_pscr_en;
  logic [`PWM_CNT_WIDTH-1:0] s_pwm_cnt_d, s_pwm_cnt_q;
  logic s_pwm_cnt_en;
  logic [`PWM_CMP_WIDTH-1:0] s_pwm_cmp_d, s_pwm_cmp_q;
  logic s_pwm_cmp_en;
  logic [`PWM_CRX_WIDTH-1:0] s_pwm_cr0_d, s_pwm_cr0_q;
  logic s_pwm_cr0_en;
  logic [`PWM_CRX_WIDTH-1:0] s_pwm_cr1_d, s_pwm_cr1_q;
  logic s_pwm_cr1_en;
  logic [`PWM_CRX_WIDTH-1:0] s_pwm_cr2_d, s_pwm_cr2_q;
  logic s_pwm_cr2_en;
  logic [`PWM_CRX_WIDTH-1:0] s_pwm_cr3_d, s_pwm_cr3_q;
  logic s_pwm_cr3_en;
  logic [`PWM_STAT_WIDTH-1:0] s_pwm_stat_d, s_pwm_stat_q;
  logic s_pwm_stat_en;
  logic s_bit_ovie, s_bit_en, s_bit_clr, s_bit_ovif;
  logic s_valid, s_done, s_tc_trg, s_normal_mode, s_ov_irq_trg;

  assign s_apb4_addr     = apb4_paddr[5:2];
  assign s_apb4_wr_hdshk = apb4_psel && apb4_penable && apb4_pwrite;
  assign s_apb4_rd_hdshk = apb4_psel && apb4_penable && (~apb4_pwrite);
  assign apb4_pready     = 1'b1;
  assign apb4_pslverr    = 1'b0;

  assign s_bit_ovie      = s_pwm_ctrl_q[0];
  assign s_bit_en        = s_pwm_ctrl_q[1];
  assign s_bit_clr       = s_pwm_ctrl_q[2];
  assign s_bit_ovif      = s_pwm_stat_q[0];
  assign s_normal_mode   = s_bit_en & s_done;
  assign pwm_irq_o       = s_bit_ovif;

  assign s_pwm_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CTRL;
  assign s_pwm_ctrl_d    = apb4_pwdata[`PWM_CTRL_WIDTH-1:0];
  dffer #(`PWM_CTRL_WIDTH) u_pwm_ctrl_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_ctrl_en,
      s_pwm_ctrl_d,
      s_pwm_ctrl_q
  );

  assign s_pwm_pscr_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_PSCR;
  assign s_pwm_pscr_d  = apb4_pwdata[`PWM_PSCR_WIDTH-1:0];
  dffer #(`PWM_PSCR_WIDTH) u_pwm_pscr_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_pscr_en,
      s_pwm_pscr_d,
      s_pwm_pscr_q
  );

  assign s_valid = s_apb4_wr_hdshk && s_apb4_addr == `PWM_PSCR && s_done;
  clk_int_div_simple #(`PWM_PSCR_WIDTH) u_clk_int_div_simple (
      .clk_i        (apb4_pclk),
      .rst_n_i      (apb4_presetn),
      .div_i        (s_pwm_pscr_q),
      .clk_init_i   (1'b0),
      .div_valid_i  (s_valid),
      .div_ready_o  (),
      .div_done_o   (s_done),
      .clk_cnt_o    (),
      .clk_fir_trg_o(),
      .clk_sec_trg_o(s_tc_trg),
      .clk_o        ()
  );

  assign s_pwm_cnt_en = s_bit_clr || (s_normal_mode && s_tc_trg);
  always_comb begin
    s_pwm_cnt_d = s_pwm_cnt_q;
    if (s_bit_clr) begin
      s_pwm_cnt_d = '0;
    end else if (s_normal_mode) begin
      if (s_pwm_cnt_q >= s_pwm_cmp_q - 1) begin
        s_pwm_cnt_d = '0;
      end else begin
        s_pwm_cnt_d = s_pwm_cnt_q + 1'b1;
      end
    end
  end
  dffer #(`PWM_CNT_WIDTH) u_pwm_cnt_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cnt_en,
      s_pwm_cnt_d,
      s_pwm_cnt_q
  );

  assign s_pwm_cmp_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CMP;
  assign s_pwm_cmp_d  = apb4_pwdata[`PWM_CMP_WIDTH-1:0];
  dffer #(`PWM_CMP_WIDTH) u_pwm_cmp_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cmp_en,
      s_pwm_cmp_d,
      s_pwm_cmp_q
  );

  assign s_pwm_cr0_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR0;
  assign s_pwm_cr0_d  = apb4_pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr0_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cr0_en,
      s_pwm_cr0_d,
      s_pwm_cr0_q
  );

  assign s_pwm_cr1_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR1;
  assign s_pwm_cr1_d  = apb4_pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr1_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cr1_en,
      s_pwm_cr1_d,
      s_pwm_cr1_q
  );

  assign s_pwm_cr2_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR2;
  assign s_pwm_cr2_d  = apb4_pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr2_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cr2_en,
      s_pwm_cr2_d,
      s_pwm_cr2_q
  );

  assign s_pwm_cr3_en = s_apb4_wr_hdshk && s_apb4_addr == `PWM_CR3;
  assign s_pwm_cr3_d  = apb4_pwdata[`PWM_CRX_WIDTH-1:0];
  dffer #(`PWM_CRX_WIDTH) u_pwm_cr3_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cr3_en,
      s_pwm_cr3_d,
      s_pwm_cr3_q
  );

  // NOTE: need to assure the s_pwmcrrx_q less than s_pwmcmp_q
  assign pwm_pwm_o[0] = s_pwm_cnt_q >= s_pwm_cr0_q;
  assign pwm_pwm_o[1] = s_pwm_cnt_q >= s_pwm_cr1_q;
  assign pwm_pwm_o[2] = s_pwm_cnt_q >= s_pwm_cr2_q;
  assign pwm_pwm_o[3] = s_pwm_cnt_q >= s_pwm_cr3_q;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_irq_cdc_sync (
      apb4_pclk,
      apb4_presetn,
      s_pwm_cnt_q >= s_pwm_cmp_q - 1,
      s_ov_irq_trg
  );

  assign s_pwm_stat_en = (s_bit_ovif && s_apb4_rd_hdshk && s_apb4_addr == `PWM_STAT) || (~s_bit_ovif && s_bit_en && s_bit_ovie && s_ov_irq_trg);
  always_comb begin
    s_pwm_stat_d = s_pwm_stat_q;
    if (s_bit_ovif && s_apb4_rd_hdshk && s_apb4_addr == `PWM_STAT) begin
      s_pwm_stat_d = '0;
    end else if (~s_bit_ovif && s_bit_en && s_bit_ovie && s_ov_irq_trg) begin
      s_pwm_stat_d = '1;
    end
  end
  dffer #(`PWM_STAT_WIDTH) u_pwm_stat_dffer (
      apb4_pclk,
      apb4_presetn,
      s_pwm_stat_en,
      s_pwm_stat_d,
      s_pwm_stat_q
  );

  always_comb begin
    apb4_prdata = '0;
    if (s_apb4_rd_hdshk) begin
      unique case (s_apb4_addr)
        `PWM_CTRL: apb4_prdata[`PWM_CTRL_WIDTH-1:0] = s_pwm_ctrl_q;
        `PWM_PSCR: apb4_prdata[`PWM_PSCR_WIDTH-1:0] = s_pwm_pscr_q;
        `PWM_CMP:  apb4_prdata[`PWM_CMP_WIDTH-1:0] = s_pwm_cmp_q;
        `PWM_CR0:  apb4_prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr0_q;
        `PWM_CR1:  apb4_prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr1_q;
        `PWM_CR2:  apb4_prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr2_q;
        `PWM_CR3:  apb4_prdata[`PWM_CRX_WIDTH-1:0] = s_pwm_cr3_q;
        `PWM_STAT: apb4_prdata[`PWM_STAT_WIDTH-1:0] = s_pwm_stat_q;
        default:   apb4_prdata = '0;
      endcase
    end
  end
endmodule
