 /*
 SPDX-FileCopyrightText: © 2023 Uri Shaked <uri@wokwi.com>
 SPDX-FileCopyrightText: © 2023 Hirosh Dabui <hirosh@dabui.de>
 SPDX-License-Identifier: MIT */

.section .text
.global _start
.extern main

.extern __stacktop
.extern _sidata
.extern _sdata
.extern _edata
.extern _sbss
.extern _ebss

_start:
    /* stack setup */
    la   sp, __stacktop

    /* psram fast mode */
    lui  t0, 0x10600
    sw   zero, 0(t0)

    /* copy initialized data from flash to RAM */
    la   a0, _sidata
    la   a1, _sdata
    la   a2, _edata
1:
    beq  a1, a2, 2f
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j    1b

    /* clear bss */
2:
    la   a0, _sbss
    la   a1, _ebss
3:
    beq  a0, a1, 4f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    3b

4:
    call main

5:
    j 5b
