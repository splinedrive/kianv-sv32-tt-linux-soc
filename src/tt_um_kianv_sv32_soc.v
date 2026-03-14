// SPDX-License-Identifier: Apache-2.0
/*
 * KianV RISC-V Linux/XV6 SoC
 * RISC-V SoC/ASIC Design
 *
 * Copyright (c) 2026 Hirosh Dabui <hirosh@dabui.de>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

`default_nettype none
/* verilator lint_off UNUSEDSIGNAL */
module tt_um_kianv_sv32_soc (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire       spi_miso = ui_in[2];
  wire       uart_rx = ui_in[7];

  wire       uart_tx;
  wire       gpio_out;
  wire       gpio_oe;

  wire [3:0] spi_cen;
  wire       spi_sclk0;
  wire       spi_mosi0;

  wire       kvsmem_sclk;
  wire       kvsmem_ss_n;
  wire [1:0] kvsmem_csn;
  wire       kvsmem_sio0_o;
  wire       kvsmem_sio1_o;
  wire       kvsmem_sio2_o;
  wire       kvsmem_sio3_o;
  wire       kvsmem_sio0_i;
  wire       kvsmem_sio1_i;
  wire       kvsmem_sio2_i;
  wire       kvsmem_sio3_i;
  wire [3:0] kvsmem_sio_oe;

  assign kvsmem_sio0_i = uio_in[1];
  assign kvsmem_sio1_i = uio_in[2];
  assign kvsmem_sio2_i = uio_in[4];
  assign kvsmem_sio3_i = uio_in[5];

  assign uio_out[0] = kvsmem_ss_n;
  assign uio_out[1] = kvsmem_sio0_o;
  assign uio_out[2] = kvsmem_sio1_o;
  assign uio_out[3] = kvsmem_sclk;
  assign uio_out[4] = kvsmem_sio2_o;
  assign uio_out[5] = kvsmem_sio3_o;
  assign uio_out[6] = kvsmem_csn[0];
  assign uio_out[7] = kvsmem_csn[1];

  assign uio_oe[0] = 1'b1;
  assign uio_oe[1] = kvsmem_sio_oe[0];
  assign uio_oe[2] = kvsmem_sio_oe[1];
  assign uio_oe[3] = 1'b1;
  assign uio_oe[4] = kvsmem_sio_oe[2];
  assign uio_oe[5] = kvsmem_sio_oe[3];
  assign uio_oe[6] = 1'b1;
  assign uio_oe[7] = 1'b1;

  assign uo_out[0] = uart_tx;
  assign uo_out[1] = gpio_out;
  assign uo_out[2] = spi_cen[1];
  assign uo_out[3] = spi_mosi0;
  assign uo_out[4] = spi_cen[0];
  assign uo_out[5] = spi_sclk0;
  assign uo_out[6] = spi_cen[2];
  assign uo_out[7] = spi_cen[3];

  wire resetn_core = rst_n;

  soc soc_I (
      .clk_osc   (clk),
      .ext_resetn(resetn_core),

      .uart_tx(uart_tx),
      .uart_rx(uart_rx),

      .kvsmem_sclk(kvsmem_sclk),
      .kvsmem_ss_n(kvsmem_ss_n),
      .kvsmem_csn (kvsmem_csn),

      .kvsmem_sio0_i(kvsmem_sio0_i),
      .kvsmem_sio1_i(kvsmem_sio1_i),
      .kvsmem_sio2_i(kvsmem_sio2_i),
      .kvsmem_sio3_i(kvsmem_sio3_i),

      .kvsmem_sio0_o(kvsmem_sio0_o),
      .kvsmem_sio1_o(kvsmem_sio1_o),
      .kvsmem_sio2_o(kvsmem_sio2_o),
      .kvsmem_sio3_o(kvsmem_sio3_o),
      .kvsmem_sio_oe(kvsmem_sio_oe),

      .spi_cen0         (spi_cen[0]),
      .spi_cen1         (spi_cen[1]),
      .spi_cen2         (spi_cen[2]),
      .spi_cen3         (spi_cen[3]),
      .spi_sclk0        (spi_sclk0),
      .spi_sio1_so_miso0(spi_miso),
      .spi_sio0_si_mosi0(spi_mosi0),

      .gpio_in (ui_in),
      .gpio_out(gpio_out),
      .gpio_oe (gpio_oe)
  );

  wire _unused = &{1'b0, ena, gpio_oe};

endmodule
/* verilator lint_on UNUSEDSIGNAL */

`default_nettype wire
