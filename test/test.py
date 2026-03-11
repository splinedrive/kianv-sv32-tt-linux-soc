# SPDX-FileCopyrightText: © 2026 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotbext.uart import UartSink


@cocotb.test()
async def test_uart_simple(dut):
    dut._log.info("start simple uart test")

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    uart_sink = UartSink(dut.uart_tx, baud=115200, bits=8)

    dut.test_sel.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    expected = b"012\n"

    for _ in range(20):
        await ClockCycles(dut.clk, 100000)
        if uart_sink.count() >= len(expected):
            break

    available = uart_sink.count()
    dut._log.info(f"UART bytes available: {available}")

    data = uart_sink.read_nowait(min(available, len(expected)))
    dut._log.info(f"UART data: {data!r}")

    assert data == expected, f"Expected {expected!r}, got {data!r}"
