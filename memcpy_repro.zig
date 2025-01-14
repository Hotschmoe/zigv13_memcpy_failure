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
        \\ mov sp, x0
        \\
        \\ // Initialize UART first
        \\ mov x0, #0              // Disable UART
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x0030       // UART0_CR
        \\ str w0, [x1]
        \\
        \\ mov w0, #13            // IBRD
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x0024
        \\ str w0, [x1]
        \\
        \\ mov w0, #1             // FBRD
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x0028
        \\ str w0, [x1]
        \\
        \\ mov w0, #0x70          // LCRH (8-bit, FIFO)
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x002C
        \\ str w0, [x1]
        \\
        \\ mov w0, #0x7FF         // Clear interrupts
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x0044
        \\ str w0, [x1]
        \\
        \\ mov w0, #0x301         // Enable UART
        \\ movz x1, #0x0900, lsl #16
        \\ movk x1, #0x0030
        \\ str w0, [x1]
        \\
        \\ // Jump to main
        \\ bl main
        \\
        \\ // Should not return, but if it does:
        \\ 0:
        \\ wfe
        \\ b 0b
        ::: "memory"
    );
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
    // Print startup message
    printStr("Starting memcpy alignment test...\n");

    // Print our current location
    var pc: u64 = undefined;
    asm volatile ("adr %[pc], ."
        : [pc] "=r" (pc)
    );
    printStr("PC: 0x");
    printHex(pc);
    printStr("\n");

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
const UART0_DR: usize = UART0_BASE + 0x00;
const UART0_FR: usize = UART0_BASE + 0x18;
const UART0_IBRD: usize = UART0_BASE + 0x24;
const UART0_FBRD: usize = UART0_BASE + 0x28;
const UART0_LCRH: usize = UART0_BASE + 0x2C;
const UART0_CR: usize = UART0_BASE + 0x30;
const UART0_ICR: usize = UART0_BASE + 0x44;

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
    // Disable UART before configuration
    mmio_write(u32, UART0_CR, 0);

    // Configure for 115200 baud
    mmio_write(u32, UART0_IBRD, 13);
    mmio_write(u32, UART0_FBRD, 1);

    // Enable FIFO & 8-bit data transmission
    mmio_write(u32, UART0_LCRH, UART_LCRH_WLEN_8BIT | UART_LCRH_FEN);

    // Clear pending interrupts
    mmio_write(u32, UART0_ICR, 0x7FF);

    // Enable UART, receive & transfer
    mmio_write(u32, UART0_CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE);
}

fn uart_putc(c: u8) void {
    // Wait until UART is ready
    while ((mmio_read(u32, UART0_FR) & UART_FR_TXFF) != 0) {
        asm volatile ("" ::: "memory");
    }
    // Write the character
    mmio_write(u32, UART0_DR, c);
}

fn printStr(str: []const u8) void {
    // Save registers we'll use
    asm volatile ("stp x29, x30, [sp, #-16]!");

    for (str) |c| {
        if (c == '\n') uart_putc('\r');
        uart_putc(c);
    }

    // Restore registers
    asm volatile ("ldp x29, x30, [sp], #16");
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
        : [esr] "=r" (esr)
        :
        : "memory"
    );

    // Get ELR_EL1 (where exception occurred)
    var elr: u64 = undefined;
    asm volatile ("mrs %[elr], elr_el1"
        : [elr] "=r" (elr)
        :
        : "memory"
    );

    const ec = (esr >> 26) & 0x3f;
    const iss = esr & 0x1FFFFFF;

    // Print directly to UART
    const uart = @as(*volatile u32, @ptrFromInt(UART0_DR));
    
    // Print "EC: "
    uart.* = 'E';
    uart.* = 'C';
    uart.* = ':';
    uart.* = ' ';
    
    const hex = "0123456789ABCDEF";
    uart.* = hex[(ec >> 4) & 0xF];
    uart.* = hex[ec & 0xF];
    uart.* = '\r';
    uart.* = '\n';

    // Print "ELR: "
    uart.* = 'E';
    uart.* = 'L';
    uart.* = 'R';
    uart.* = ':';
    uart.* = ' ';
    
    var i: u6 = 60;
    while (true) : (i -= 4) {
        uart.* = hex[@as(u4, @truncate((elr >> i) & 0xF))];
        if (i == 0) break;
    }
    uart.* = '\r';
    uart.* = '\n';

    // Print "ISS: "
    uart.* = 'I';
    uart.* = 'S';
    uart.* = 'S';
    uart.* = ':';
    uart.* = ' ';

    i = 24;  // ISS is 25 bits
    while (true) : (i -= 4) {
        uart.* = hex[@as(u4, @truncate((iss >> i) & 0xF))];
        if (i == 0) break;
    }
    uart.* = '\r';
    uart.* = '\n';

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
        ::: "memory"
    );
    unreachable;
}