# zigv13_memcpy_failure
 The memcpy implementation in Zig 0.13.0 unconditionally uses SIMD instructions for lengths > 0x20 bytes on AArch64, without checking buffer alignment. This causes alignment faults when copying between buffers that are 8-byte aligned but not 16-byte aligned.
