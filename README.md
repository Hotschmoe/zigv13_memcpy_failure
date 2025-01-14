# Zig AArch64 memcpy Alignment Fault Reproduction

This repository demonstrates a bug in Zig 0.13.0's memcpy implementation on AArch64, where LLVM's auto-vectorization transforms a byte-by-byte copy into SIMD instructions without proper alignment checks. This causes alignment faults when copying between buffers that are 8-byte aligned but not 16-byte aligned.

## The Bug

While the Zig compiler_rt implementation in `compiler_rt/memcpy.zig` is a simple byte-by-byte copy, LLVM's auto-vectorization transforms this into SIMD instructions (ldp/stp with Q registers) for copies larger than 32 bytes (0x20). These instructions require 16-byte alignment, but no alignment verification is performed before the transformation.

### Technical Details
- The source implementation is a simple byte-by-byte copy in compiler_rt
- LLVM auto-vectorization transforms this into SIMD instructions
- The resulting assembly uses `ldp q0, q1, [x9, #-16]` which requires 16-byte alignment (attempting to load 32 bytes using two 128-bit SIMD registers)
- No alignment checks are performed before using SIMD instructions

### Impact
- Affects AArch64 bare metal code using memcpy with 8-byte aligned buffers
- Particularly problematic for kernel/OS development where hardware structures are often 8-byte aligned
- Results in alignment faults (EC=0x07) when copying > 32 bytes

## Reproduction

https://github.com/Hotschmoe/zigv13_memcpy_failure

The included code demonstrates the issue by:
1. Setting up buffers with 8-byte alignment
2. Enabling alignment checking in SCTLR_EL1
3. Attempting to memcpy 40 bytes (triggering SIMD path)
4. Capturing the resulting alignment fault

### Running the Test
1. Build with Zig 0.13.0
2. Run under QEMU (aarch64-virt)
3. Observe alignment fault with:
   - EC (Exception Class): 0x07
   - ISS: 0x1E00000

(in repo you can run ```zig build run``` to see the fault)

## Expected Behavior

The implementation should either:
1. Check buffer alignment before allowing SIMD optimization
2. Have LLVM's auto-vectorization respect the actual buffer alignment
3. Document that memcpy requires 16-byte alignment for optimal performance
4. Use unaligned SIMD loads/stores when alignment isn't guaranteed

## Actual Behavior

LLVM's auto-vectorization transforms the byte-by-byte implementation into SIMD instructions without alignment checks, causing alignment faults when buffers aren't 16-byte aligned.

## Environment
- Zig 0.13.0
- AArch64 bare metal (EL1)
- Tested on QEMU virt machine
