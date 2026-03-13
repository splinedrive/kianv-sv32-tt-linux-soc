/*
 SPDX-FileCopyrightText: © 2023 Uri Shaked <uri@wokwi.com>
 SPDX-FileCopyrightText: © 2023 Hirosh Dabui <hirosh@dabui.de>
 SPDX-License-Identifier: MIT
 */

#include <stdint.h>

extern uint32_t __stacktop;

#define UART_TX       ((volatile uint32_t*)0x10000000u)
#define UART_LSR      ((volatile uint8_t *)0x10000005u)
#define CPU_FREQ_REG  ((volatile uint32_t*)0x10000014u)

#define DIV_ADDR0     ((volatile uint32_t*)0x1000000cu) /* HI: SPI0 div, LO: UART div */
#define DIV_ADDR1     ((volatile uint32_t*)0x10000010u) /* HI: SPI1 div, LO: CLINT div */

#define LSR_READY_MASK 0x60u

#define UART_DIV      86u
#define SPI0_DIV      2u
#define SPI1_DIV      4u
#define CLINT_DIV     1u

#define DIV0_VAL      ((SPI0_DIV << 16) | UART_DIV)
#define DIV1_VAL      ((SPI1_DIV << 16) | CLINT_DIV)

static void uart_wait_ready(void)
{
    while (((*UART_LSR) & LSR_READY_MASK) == 0u) {
    }
}

static void uart_putc(uint32_t val)
{
    uart_wait_ready();
    *UART_TX = val;
}

int main(void)
{
    uint32_t t1;

    /* optional: low16 = Q8.8 CPU MHz, here 10.0 MHz = 10 << 8 */
    t1 = *CPU_FREQ_REG;
    t1 &= 0xffff0000u;
    t1 |= 2560u;
    *CPU_FREQ_REG = t1;

    *DIV_ADDR0 = DIV0_VAL;
    *DIV_ADDR1 = DIV1_VAL;

    uart_putc(48);       /* '0' */
    uart_putc(49);       /* '1' */
    uart_putc(50);       /* '2' */
    uart_putc(10);       /* '\n' */

    for (;;) {
    }
}
