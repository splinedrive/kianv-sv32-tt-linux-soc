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

  // ---------------------------------------------------------------------------
  // TinyTapeout conventions:
  // - clk is the provided user clock
  // - rst_n is active-low reset
  // - ena is "design enabled" (often tied high on silicon, but keep it sane)
  // ---------------------------------------------------------------------------

  // Inputs (per your pinout)
  wire igpio2  = ui_in[0];
  wire igpio0  = ui_in[1];
  wire spi_miso= ui_in[2];
  wire igpio3  = ui_in[3];
  wire igpio4  = ui_in[4];
  wire igpio5  = ui_in[5];
  wire igpio1  = ui_in[6];
  wire uart_rx = ui_in[7];

  // GPIO wiring into your SoC (soc has 1-bit gpio_in/out/oe)
  // -> hier nehme ich IGPIO0 als gpio_in (du kannst das easy umbiegen)
  wire gpio_in = igpio0;

  wire uart_tx;
  wire gpio_out;
  wire gpio_oe;

  // SPI (shared SPI / NOR) wiring from soc
  wire [3:0] spi_cen;       // soc exposes spi_cen0..3
  wire       spi_sclk0;
  wire       spi_mosi0;

  // KVSMEM wiring from soc
  wire       kvsmem_sclk;
  wire       kvsmem_ss_n;      // active-low
  wire [1:0] kvsmem_csn;       // active-low chip selects
  wire       kvsmem_sio0_o, kvsmem_sio1_o, kvsmem_sio2_o, kvsmem_sio3_o;
  wire       kvsmem_sio0_i, kvsmem_sio1_i, kvsmem_sio2_i, kvsmem_sio3_i;
  wire [3:0] kvsmem_sio_oe;

  // ---------------------------------------------------------------------------
  // Map uio lines (Bidirectional pins)
  //
  // uio[0]: KVSMEM_SS      (we drive it)
  // uio[1]: KVSMEM_MOSI    (SIO0)
  // uio[2]: KVSMEM_MISO    (SIO1)
  // uio[3]: KVSMEM_SCLK    (we drive it)
  // uio[4]: KVSMEM_SIO2
  // uio[5]: KVSMEM_SIO3
  // uio[6]: KVSMEM_SPICS0  (CSN[0])
  // uio[7]: KVSMEM_SPICS1  (CSN[1])
  //
  // Note: kvsmem_ss_n is separate from csn[] in your core; both are active-low.
  // ---------------------------------------------------------------------------

  // Read from pads into core
  assign kvsmem_sio0_i = uio_in[1];
  assign kvsmem_sio1_i = uio_in[2];
  assign kvsmem_sio2_i = uio_in[4];
  assign kvsmem_sio3_i = uio_in[5];

  // Drive outputs to pads
  assign uio_out[0] = kvsmem_ss_n;
  assign uio_out[1] = kvsmem_sio0_o;
  assign uio_out[2] = kvsmem_sio1_o;
  assign uio_out[3] = kvsmem_sclk;
  assign uio_out[4] = kvsmem_sio2_o;
  assign uio_out[5] = kvsmem_sio3_o;
  assign uio_out[6] = kvsmem_csn[0];
  assign uio_out[7] = kvsmem_csn[1];

  // Output-enable:
  // - SS, SCLK, CS pins are always outputs from our design
  // - SIO0..3 use kvsmem_sio_oe from the core
  assign uio_oe[0] = 1'b1;              // KVSMEM_SS
  assign uio_oe[1] = kvsmem_sio_oe[0];  // KVSMEM_MOSI (SIO0)
  assign uio_oe[2] = kvsmem_sio_oe[1];  // KVSMEM_MISO (SIO1) - may be input often
  assign uio_oe[3] = 1'b1;              // KVSMEM_SCLK
  assign uio_oe[4] = kvsmem_sio_oe[2];  // KVSMEM_SIO2
  assign uio_oe[5] = kvsmem_sio_oe[3];  // KVSMEM_SIO3
  assign uio_oe[6] = 1'b1;              // KVSMEM_SPICS0
  assign uio_oe[7] = 1'b1;              // KVSMEM_SPICS1

  // ---------------------------------------------------------------------------
  // Map uo lines (Outputs) per your pinout
  //
  // uo[0]: UART TX
  // uo[1]: OGPIO0
  // uo[2]: SPI CS1
  // uo[3]: SPI MOSI
  // uo[4]: SPI CS0
  // uo[5]: SPI SCK
  // uo[6]: SPI CS2
  // uo[7]: SPI CS3
  // ---------------------------------------------------------------------------

  assign uo_out[0] = uart_tx;
  assign uo_out[1] = gpio_out;

  // spi_cenX are typically active-low enables (CEN = chip enable not), in your design:
  // soc outputs are spi_cen0..3 already coming from spi_nor_spi_if.cen[]
  // We'll expose them directly as "CSx" (active-low) as your pinout suggests.
  assign uo_out[4] = spi_cen[0]; // SPI CS0
  assign uo_out[2] = spi_cen[1]; // SPI CS1
  assign uo_out[6] = spi_cen[2]; // SPI CS2
  assign uo_out[7] = spi_cen[3]; // SPI CS3

  assign uo_out[5] = spi_sclk0;  // SPI SCK
  assign uo_out[3] = spi_mosi0;  // SPI MOSI

  // ---------------------------------------------------------------------------
  // Tie-offs / unused ui pins handling
  // (ena is optional; if you want: gate reset or clock)
  // ---------------------------------------------------------------------------

  wire resetn_core = rst_n;// & ena;

  // ---------------------------------------------------------------------------
  // Instantiate your SoC
  // ---------------------------------------------------------------------------

  soc soc_I (
      .clk_osc        (clk),
      .ext_resetn     (resetn_core),

      .uart_tx        (uart_tx),
      .uart_rx        (uart_rx),

      .kvsmem_sclk    (kvsmem_sclk),
      .kvsmem_ss_n    (kvsmem_ss_n),
      .kvsmem_csn     (kvsmem_csn),

      .kvsmem_sio0_i  (kvsmem_sio0_i),
      .kvsmem_sio1_i  (kvsmem_sio1_i),
      .kvsmem_sio2_i  (kvsmem_sio2_i),
      .kvsmem_sio3_i  (kvsmem_sio3_i),

      .kvsmem_sio0_o  (kvsmem_sio0_o),
      .kvsmem_sio1_o  (kvsmem_sio1_o),
      .kvsmem_sio2_o  (kvsmem_sio2_o),
      .kvsmem_sio3_o  (kvsmem_sio3_o),
      .kvsmem_sio_oe  (kvsmem_sio_oe),

      .spi_cen0       (spi_cen[0]),
      .spi_cen1       (spi_cen[1]),
      .spi_cen2       (spi_cen[2]),
      .spi_cen3       (spi_cen[3]),
      .spi_sclk0      (spi_sclk0),
      .spi_sio1_so_miso0 (spi_miso),
      .spi_sio0_si_mosi0 (spi_mosi0),

      .gpio_in        (gpio_in),
      .gpio_out       (gpio_out),
      .gpio_oe        (gpio_oe)
  );

  // Optional: if you want OGPIO0 to be tri-stated depending on gpio_oe,
  // you can expose gpio_oe on some pin or gate output here. But uo_out are always driven.
  // If you really want "OGPIO0" to reflect OE, you could do:
  // assign uo_out[1] = gpio_oe ? gpio_out : 1'b0;

  // Silence unused warnings for other IGPIOs (they’re available on ui_in per your pinout)
  wire _unused = &{1'b0, igpio1, igpio2, igpio3, igpio4, igpio5};

endmodule

`default_nettype wire
