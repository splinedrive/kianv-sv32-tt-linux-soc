/* SPDX-FileCopyrightText: © 2023 Uri Shaked <uri@wokwi.com>
   SPDX-FileCopyrightText: © 2023 Hirosh Dabui <hirosh@dabui.de>
   SPDX-License-Identifier: MIT */

.text
.global _start, timer_interrupt_handler

.equ IO_BASE,        0x10000000
.equ DIV_ADDR0,      0x1000000c   /* HI: SPI0 div, LO: UART div */
.equ DIV_ADDR1,      0x10000010   /* HI: SPI1 div, LO: CLINT div */
.equ CPU_FREQ_REG,   0x10000014

.equ FREQ,           10000000
.equ BAUDRATE,       115200

.equ UART_DIV,       (FREQ / BAUDRATE)   /* ~86 */
.equ SPI0_DIV,       2
.equ SPI1_DIV,       4
.equ CLINT_DIV,      1

.equ DIV_ADDR0_VAL,  ((SPI0_DIV << 16) | UART_DIV)
.equ DIV_ADDR1_VAL,  ((SPI1_DIV << 16) | CLINT_DIV)

.type _start, @function

_start:
   li   t0, CPU_FREQ_REG
    lw   t1, 0(t0)
    li   t2, 0xffff0000
    and  t1, t1, t2
    li   t2, 2560
    or   t1, t1, t2
    sw   t1, 0(t0)
    /* DIV_ADDR0: HI = SPI0, LO = UART */
    li t0, DIV_ADDR0
    li t1, DIV_ADDR0_VAL
    sw t1, 0(t0)

    /* DIV_ADDR1: HI = SPI1, LO = CLINT */
    li t0, DIV_ADDR1
    li t1, DIV_ADDR1_VAL
    sw t1, 0(t0)

    la sp, __stacktop

    la a0, _sbss
    la a1, _ebss
1:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, 1b

    la a0, _sidata
    la a1, _sdata
    la a2, _edata
2:
    lw a3, 0(a0)
    sw a3, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    blt a1, a2, 2b

    la a0, timer_interrupt_handler
    csrw mtvec, a0

    call main
3:
    j 3b

.balign 4
