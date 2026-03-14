## How it works
This design integrates a **KianV RV32IMA RISC-V processor** with an SV32 MMU and hardware caches (icache + dcache). The system is capable of booting **Linux, µLinux (uClinux), and xv6**, providing a compact Linux-capable SoC platform.
The processor supports virtual memory through the SV32 MMU with two-level page table translation and separate instruction and data TLBs (8 entries each). The cache hierarchy uses a 512-set direct-mapped icache and dcache backed by IHP SG13G2 SRAM macros.
The SoC includes **32 MiB of external QSPI PSRAM (4 × 8 MiB banks)**, **16 MiB of external SPI NOR flash**, and memory-mapped peripherals such as **UART, SPI, and GPIO**.

## System Memory Map

| Address      | Size   | Purpose                  |
| ------------ | ------ | ------------------------ |
| 0x02000000   | 64 KiB | CLINT (timer/interrupts) |
| 0x10000000   | 0x06   | UART Peripheral          |
| 0x1000000C   | 0x0C   | UART Divider / CPU info  |
| 0x10000700   | 0x0C   | GPIO Peripheral          |
| 0x10500000   | 0x08   | SPI Peripheral           |
| 0x10600000   | 0x04   | QSPI PSRAM Control       |
| 0x11100000   | 0x04   | Reset / HALT control     |
| 0x20000000   | 16 MiB | SPI NOR Flash            |
| 0x80000000   | 32 MiB | QSPI PSRAM               |

The system boots from SPI NOR flash. After reset, the CPU starts executing code from 0x20000000.

### UART Peripheral registers

| Address    | Name      | Description                        |
| ---------- | --------- | ---------------------------------- |
| 0x10000000 | UART_DATA | Write to transmit, read to receive |
| 0x10000005 | UART_LSR  | UART line status register          |
| 0x1000000C | UART_DIV0 | Clock divider for UART baud rate   |
| 0x10000010 | UART_DIV1 | Clock divider (alternate)          |
| 0x10000014 | CPU_FREQ  | CPU frequency register (Q8.8 MHz)  |
| 0x10000018 | MEMSIZE   | Memory size register               |

### SPI Peripheral registers

| Address    | Name      | Description        |
| ---------- | --------- | ------------------ |
| 0x10500000 | SPI_CTRL0 | SPI control        |
| 0x10500004 | SPI_DATA0 | SPI data           |

### GPIO Peripheral registers

| Address    | Name     | Description                                   |
| ---------- | -------- | --------------------------------------------- |
| 0x10000700 | GPIO_OE  | Output enable (bits [15:8] for uo_out [7:0])  |
| 0x10000704 | GPIO_OUT | Output value (bits [15:8] for uo_out [7:0])   |
| 0x10000708 | GPIO_IN  | Input value (bits [7:0] from ui_in [7:0])     |

Input pins (`ui_in`) occupy bits [7:0], output pins (`uo_out`) occupy bits [15:8]. These are physically separate pins, mapped at separate bit positions so there is no overlap. This gives 16 GPIO pins total (0-7 input, 8-15 output).

**Bits [7:0]: inputs** (always readable via GPIO_IN)

| Pin      | Bit | Also used by |
| -------- | --- | ------------ |
| ui_in[0] | 0   |              |
| ui_in[1] | 1   |              |
| ui_in[2] | 2   | SPI MISO     |
| ui_in[3] | 3   |              |
| ui_in[4] | 4   |              |
| ui_in[5] | 5   |              |
| ui_in[6] | 6   |              |
| ui_in[7] | 7   | UART RX      |

**Bits [15:8]: outputs** (GPIO_OE switches uo_out from peripheral to GPIO_OUT)

| Pin       | Bit | OE=0 (default) | OE=1       |
| --------- | --- | -------------- | ---------- |
| uo_out[0] | 8   | UART TX        | GPIO OUT 0 |
| uo_out[1] | 9   | low            | GPIO OUT 1 |
| uo_out[2] | 10  | SPI CS1        | GPIO OUT 2 |
| uo_out[4] | 12  | SPI CS0        | GPIO OUT 4 |
| uo_out[7] | 15  | SPI CS3        | GPIO OUT 7 |

Bits 11 (SPI MOSI), 13 (SPI SCLK), 14 (SPI CS2/NOR flash) are not muxable and always driven by their peripheral.

### QSPI PSRAM Control register

| Address    | Name         | Description                                         |
| ---------- | ------------ | --------------------------------------------------- |
| 0x10600000 | QSPI_CTRL   | Bit 0: half_clock (1=div4 slow, 0=div2 fast clock)  |

### CPU control register

| Address    | Name      | Description                                             |
| ---------- | --------- | ------------------------------------------------------- |
| 0x11100000 | CPU_RESET | Write 0x7777 to reset the CPU, 0x5555 to halt the CPU  |

## How to test

We will provide a pre-built system image + instructions how to build your own image.

## External hardware

- [Machdyne QSPI Pmod](https://machdyne.com/product/qqspi-psram32/) (4 x 8 MiB PSRAM banks)
- [SPI NOR flash Pmod](https://machdyne.com/product/mmod/)
- SD Card Pmod
- Ethernet Pmod (optional)
