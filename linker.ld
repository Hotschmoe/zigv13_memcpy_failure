ENTRY(_start)

MEMORY
{
    /* Device memory region for UART and other peripherals */
    DEVICE (rw) : ORIGIN = 0x09000000, LENGTH = 0x1000

    /* Kernel memory region where our code/data lives */
    KERNEL (rwx) : ORIGIN = 0x40080000, LENGTH = 0x40000000
}

SECTIONS
{
    . = ORIGIN(KERNEL);

    .text : {
        KEEP(*(.text._start))
        *(.text.boot)
        /* Vector table must be 2048-byte aligned */
        . = ALIGN(2048);
        KEEP(*(.vectors))
        *(.text)
        *(.text.*)
    } > KERNEL

    /* Read-only data */
    .rodata ALIGN(64) : {
        *(.rodata)
        *(.rodata.*)
    } > KERNEL

    /* Read-write data (initialized) */
    .data ALIGN(64) : {
        *(.data)
        *(.data.*)
    } > KERNEL

    /* Read-write data (uninitialized) */
    .bss ALIGN(64) : {
        bss_begin = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(64);
        bss_end = .;
    } > KERNEL

    /* Stack */
    .stack ALIGN(64) : {
        . = . + 0x4000;  /* 16KB stack */
    } > KERNEL

    /* Device memory section */
    .device (NOLOAD) : {
        *(.device)
    } > DEVICE

    /* Debugging information */
    .debug_info     0 : { *(.debug_info) }
    .debug_abbrev   0 : { *(.debug_abbrev) }
    .debug_aranges  0 : { *(.debug_aranges) }
    .debug_ranges   0 : { *(.debug_ranges) }
    .debug_str      0 : { *(.debug_str) }
    .debug_pubnames 0 : { *(.debug_pubnames) }
    .debug_pubtypes 0 : { *(.debug_pubtypes) }
    .debug_frame    0 : { *(.debug_frame) }
    .debug_line     0 : { *(.debug_line) }
    .debug_loc      0 : { *(.debug_loc) }
    .comment        0 : { *(.comment) }
}