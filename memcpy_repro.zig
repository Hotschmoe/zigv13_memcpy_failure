// memcpy_repro.zig
// Minimal reproduction of AArch64 memcpy alignment bug in Zig 0.13.0
const builtin = @import("builtin");

// We'll need some basic EL1 setup
export fn _start() callconv(.Naked) void {
    asm volatile (
        \\ // Set up vector table
        \\ adr x0, __vectors
        \\ msr vbar_el1, x0
        \\
        \\ // Enable alignment checking
        \\ mrs x0, sctlr_el1
        \\ orr x0, x0, #(1 << 1)  // Set A bit (alignment check)
        \\ msr sctlr_el1, x0
        \\
        \\ // Set up initial stack
        \\ ldr x0, =0x40100000    // Use a higher stack address
        \\ and x0, x0, #~15       // Ensure 16-byte alignment
        \\ mov sp, x0
        \\
        \\ // Jump to main
        \\ bl main
        \\
        \\ // Should not return, but if it does:
        \\ 0:
        \\ wfe
        \\ b 0b
        ::: "memory");
}

// Force 8-byte alignment but not 16-byte alignment
var source: [64]u8 align(8) = undefined;
var dest: [64]u8 align(8) = undefined;

// Simple memcpy implementation
fn my_memcpy(dst: [*]u8, src: [*]const u8, len: usize) void {
    for (0..len) |i| {
        dst[i] = src[i];
    }
}

export fn main() void {
    // Initialize UART first
    uart_init();

    // Print startup message
    printStr("Starting memcpy alignment test...\n");

    // Initialize source with some data
    for (0..64) |i| {
        source[i] = @as(u8, @truncate(i));
    }

    printStr("Source initialized\n");

    // This should trigger the SIMD path (len > 0x20)
    // and cause an alignment fault
    @memcpy(dest[0..40], source[0..40]);

    // We shouldn't reach here due to alignment fault
    printStr("memcpy completed (shouldn't see this)\n");
    while (true) {}
}

// Basic exception vector table
export fn __vectors() align(0x800) callconv(.Naked) void {
    asm volatile (
        \\ // Current EL with SP0
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
        \\
        \\ // Current EL with SPx
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
        \\ .align 7
        \\ b handle_exception
    );
}

// UART registers for QEMU virt machine (PL011)
const UART0_BASE: usize = 0x09000000;
const UART0_DR: *volatile u8 = @ptrFromInt(UART0_BASE + 0x00); // Data register as u8 for character writes
const UART0_FR: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x18);
const UART0_IBRD: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x24);
const UART0_FBRD: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x28);
const UART0_LCRH: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x2C);
const UART0_CR: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x30);
const UART0_ICR: *align(4) volatile u32 = @ptrFromInt(UART0_BASE + 0x44);

// Control register bits
const UART_LCRH_WLEN_8BIT: u32 = 3 << 5;
const UART_LCRH_FEN: u32 = 1 << 4;
const UART_CR_UARTEN: u32 = 1 << 0;
const UART_CR_TXE: u32 = 1 << 8;
const UART_CR_RXE: u32 = 1 << 9;
const UART_FR_TXFF: u32 = 1 << 5;

fn mmio_write(comptime T: type, reg: usize, value: T) void {
    const ptr = @as(*align(@alignOf(T)) volatile T, @ptrFromInt(reg));
    ptr.* = value;
}

fn mmio_read(comptime T: type, reg: usize) T {
    const ptr = @as(*align(@alignOf(T)) volatile T, @ptrFromInt(reg));
    return ptr.*;
}

fn uart_init() void {
    // Disable UART
    mmio_write(u32, UART0_BASE + 0x30, 0);

    // Set baud rate - 115200
    mmio_write(u32, UART0_BASE + 0x24, 13); // IBRD
    mmio_write(u32, UART0_BASE + 0x28, 1); // FBRD

    // 8 bits, 1 stop bit, no parity, FIFO enabled
    mmio_write(u32, UART0_BASE + 0x2C, 0x70);

    // Enable UART, RX, and TX
    mmio_write(u32, UART0_BASE + 0x30, 0x301);
}

fn uart_putc(c: u8) void {
    // Simple busy wait on the UART
    while ((mmio_read(u32, UART0_BASE + 0x18) & (1 << 5)) != 0) {}
    mmio_write(u8, UART0_BASE + 0x00, c);
}

fn printStr(str: []const u8) void {
    for (str) |c| {
        if (c == '\n') uart_putc('\r');
        uart_putc(c);
    }
}

fn printHex(value: u64) void {
    const hex_chars = "0123456789ABCDEF";
    var i: u6 = 60;
    while (true) {
        const digit = @as(u4, @truncate((value >> i) & 0xF));
        uart_putc(hex_chars[digit]);
        if (i == 0) break;
        i -= 4;
    }
}

export fn handle_exception() callconv(.C) noreturn {
    // Set up a known good stack pointer first
    asm volatile (
        \\ mov x16, #0x40200000  // Use a different stack area
        \\ mov sp, x16
    );

    // Get exception class from ESR_EL1
    var esr: u64 = undefined;
    asm volatile ("mrs %[esr], esr_el1"
        : [esr] "=r" (esr),
        :
        : "memory"
    );

    // Get ELR_EL1 (where exception occurred)
    var elr: u64 = undefined;
    asm volatile ("mrs %[elr], elr_el1"
        : [elr] "=r" (elr),
        :
        : "memory"
    );

    const ec = (esr >> 26) & 0x3f;
    const iss = esr & 0x1FFFFFF;

    // Print in exact same format as before
    const hex = "0123456789ABCDEF";
    uart_putc('E');
    uart_putc('C');
    uart_putc(':');
    uart_putc(' ');
    uart_putc(hex[(ec >> 4) & 0xF]);
    uart_putc(hex[ec & 0xF]);
    uart_putc('\n');

    uart_putc('E');
    uart_putc('L');
    uart_putc('R');
    uart_putc(':');
    uart_putc(' ');
    var i: u6 = 60;
    while (true) : (i -= 4) {
        uart_putc(hex[@as(u4, @truncate((elr >> i) & 0xF))]);
        if (i == 0) break;
    }
    uart_putc('\n');

    uart_putc('I');
    uart_putc('S');
    uart_putc('S');
    uart_putc(':');
    uart_putc(' ');
    i = 24; // ISS is 25 bits
    while (true) : (i -= 4) {
        uart_putc(hex[@as(u4, @truncate((iss >> i) & 0xF))]);
        if (i == 0) break;
    }
    uart_putc('\n');

    // Make sure we properly halt
    asm volatile (
        \\ // Disable all interrupts and debugging
        \\ msr daifset, #0xf
        \\ dsb sy
        \\ isb
        \\ // Halt the CPU
        \\ msr spsel, #1
        \\ wfi
        \\ // Should never get here
        \\ 1: b 1b
        ::: "memory");
    unreachable;
}
