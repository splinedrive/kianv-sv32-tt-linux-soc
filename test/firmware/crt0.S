 /*
 SPDX-FileCopyrightText: © 2023 Uri Shaked <uri@wokwi.com>
 SPDX-FileCopyrightText: © 2023 Hirosh Dabui <hirosh@dabui.de>
 SPDX-License-Identifier: MIT */

.text
.global _start

.equ UART_TX,         0x10000000
.equ UART_LSR,        0x10000005
.equ CPU_FREQ_REG,    0x10000014

.equ DIV_ADDR0,       0x1000000c   /* HI: SPI0 div, LO: UART div */
.equ DIV_ADDR1,       0x10000010   /* HI: SPI1 div, LO: CLINT div */

.equ LSR_READY_MASK,  0x60

/* match your FPGA helper values */
.equ UART_DIV,        86           /* 10 MHz / 115200 ≈ 86 */
.equ SPI0_DIV,        2
.equ SPI1_DIV,        4
.equ CLINT_DIV,       1

.equ DIV0_VAL,        ((SPI0_DIV << 16) | UART_DIV)
.equ DIV1_VAL,        ((SPI1_DIV << 16) | CLINT_DIV)

.macro UART_WAIT_READY
1:
    li   t0, UART_LSR
    lbu  t1, 0(t0)
    andi t1, t1, LSR_READY_MASK
    beqz t1, 1b
.endm

.macro UART_PUTC val
    UART_WAIT_READY
    li   t0, UART_TX
    li   t1, \val
    sw   t1, 0(t0)
.endm

_start:
    /* optional: low16 = Q8.8 CPU MHz, here 10.0 MHz = 10 << 8 */
    li   t0, CPU_FREQ_REG
    lw   t1, 0(t0)
    li   t2, 0xffff0000
    and  t1, t1, t2
    li   t2, 2560
    or   t1, t1, t2
    sw   t1, 0(t0)

    /* packed divider programming like original bootloader */
    li   t0, DIV_ADDR0
    li   t1, DIV0_VAL
    sw   t1, 0(t0)

    li   t0, DIV_ADDR1
    li   t1, DIV1_VAL
    sw   t1, 0(t0)

    UART_PUTC 48      /* '0' */
    UART_PUTC 49      /* '1' */
    UART_PUTC 50      /* '2' */
    UART_PUTC 10      /* '\n' */

1:
    j 1b
