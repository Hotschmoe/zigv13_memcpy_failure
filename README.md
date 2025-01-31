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

(in repo you can run ```C:\zig-dev-3008\zig.exe build run``` to see the fault)

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

## Additional Notes

In my actualy project, I get an EC = 0x25, which is a data abort from a misalgined memory read. But gdp points me to the memcpy implementation. The above test is the simplest way to reproduce the issue but we get a different EC than the actual project.

regardless I *believe* this is the same issue. but I could be wrong. this is my first foray into kernel development.

here is my total output from my own project: (I was testing fatal faults to verify we are in a good EL1 state, but this permission fault always throws a alignment fault. I tested alignment fault before this and handle it as expected)

```
Building for target CPU architecture: Target.Cpu.Arch.aarch64
EL2 Init Complete
Starting EL2 setup...
Current EL: 00000002 (EL00000002)
Setting up HCR_EL2...
HCR_EL2 = 0x0000000080000038

=== Testing EL2 Exception Handling ===
VBAR_EL2 = 0x0000000040000000 - OK!
HCR_EL2 = 0x0000000080000038
Testing SVC in EL2:
EL2 Exception:
Type: Synchronous
Source: EL2h
ESR: 0x0000000056000000
OK! (Returned from handler)
=== EL2 Exception Test Complete ===

Setting up translation tables...
Translation tables configured.

Kernel start address: 0x40000000
  .text:  0x40004000 - 0x4002C070
  .data:  0x4002C070 - 0x40030000
  .bss:   0x40030000 - 0x40063000
Kernel end address: 0x40063000

Verifying translation tables:
TTBR0 first 4 entries:
  [00000000]: 0x0060000000000601
  [00000001]: 0x0000000040000705
  [00000002]: 0x0000000080000745
  [00000003]: 0x0000000000000000
TTBR1 first 4 entries:
  [00000000]: 0x0000000000000000
  [00000001]: 0x0000000000000000
  [00000002]: 0x0000000000000000
  [00000003]: 0x0000000000000000
Configuring MMU registers...
CPACR_EL1 = 0x0000000000300000 (SIMD/FP enabled)
MAIR_EL1 = 0x0000FF00
TCR_EL1 = 0xB5603520
TTBR0_EL1 = 0x40043000
TTBR1_EL1 = 0x40053000
Ready to enable MMU and transition to EL1
Calling enable_mmu() - Next stop kernel_main in EL1!

ReclaimerOS Kernel Starting in EL1...
If you see this, we've successfully transitioned to EL1!

  Testing Fatal Permission Fault:
  Triggering permission fault at 0x000000004002BF70...
FATAL: Data abort (alignment fault) during read at 0x0000000040028889

Exception Frame Dump:
General Purpose Registers:
x0: 0x000000004003AFB8
x1: 0x0000000040028888
x2: 0x0000000000000028
x3: 0x0000000000000000
x4: 0x0000000000000000
x5: 0x0000000000000000
x6: 0x0000000000000000
x7: 0x0000000000000000
x8: 0x0000000000000027
x9: 0x0000000040028899
x10: 0x0000000000000020
x11: 0x000000004003AFC9
x12: 0x0000000000000020
x13: 0x0000000000000000
x14: 0x0000000000000000
x15: 0x0000000000000000
x16: 0x0000000000000000
x17: 0x0000000000000000
x18: 0x0000000000000000
x19: 0x0000000000000000
x20: 0x0000000000000000
x21: 0x0000000000000000
x22: 0x0000000000000000
x23: 0x0000000000000000
x24: 0x0000000000000000
x25: 0x0000000000000000
x26: 0x0000000000000000
x27: 0x0000000000000000
x28: 0x0000000000000000
x29: 0x000000004003AF40
Special Registers:
SP_EL0: 0x0000000000000000
SP: 0x000000004003AF40
ELR: 0x0000000040026DF4
SPSR: 0x00000000200003C5
FAR: 0x0000000040028889
ESR: 0x0000000096000021

System halted. Power cycle required.
QEMU: Terminated
```