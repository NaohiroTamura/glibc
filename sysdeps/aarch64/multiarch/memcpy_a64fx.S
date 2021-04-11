/* Optimized memcpy for Fujitsu A64FX processor.
   Copyright (C) 2012-2021 Free Software Foundation, Inc.

   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library.  If not, see
   <https://www.gnu.org/licenses/>.  */

#include <sysdep.h>

#if HAVE_SVE_ASM_SUPPORT
#if IS_IN (libc)
# define MEMCPY __memcpy_a64fx
# define MEMMOVE __memmove_a64fx

/* Assumptions:
 *
 * ARMv8.2-a, AArch64, unaligned accesses, sve
 *
 */

#define L1_SIZE         (64*1024)/2     // L1 64KB/2
#define L2_SIZE         (8*1024*1024)/2 // L2 8MB/2
#define CACHE_LINE_SIZE 256
#define PF_DIST_L1      (CACHE_LINE_SIZE * 16)  // Prefetch distance L1
#define PF_DIST_L2      (CACHE_LINE_SIZE * 64)  // Prefetch distance L2
#define ZF_DIST         (CACHE_LINE_SIZE * 18)  // Zerofill distance
#define dest            x0
#define src             x1
#define n               x2      // size
#define tmp1            x3
#define tmp2            x4
#define rest            x5
#define dest_ptr        x6
#define src_ptr         x7
#define vector_length   x8
#define vl_remainder    x9      // vector_length remainder
#define cl_remainder    x10     // CACHE_LINE_SIZE remainder

    .arch armv8.2-a+sve

    .macro dc_zva times
    dc          zva, tmp1
    add         tmp1, tmp1, CACHE_LINE_SIZE
    .if \times-1
    dc_zva "(\times-1)"
    .endif
    .endm

    .macro ld1b_unroll2
     ld1b        z0.b, p0/z, [src_ptr, #0, mul vl]
     ld1b        z1.b, p0/z, [src_ptr, #1, mul vl]
    .endm

    .macro ld1b_unroll4
    ld1b_unroll2
     ld1b        z2.b, p0/z, [src_ptr, #2, mul vl]
     ld1b        z3.b, p0/z, [src_ptr, #3, mul vl]
    .endm

    .macro ld1b_unroll8
    ld1b_unroll4
    ld1b        z4.b, p0/z, [src_ptr,  #4, mul vl]
    ld1b        z5.b, p0/z, [src_ptr,  #5, mul vl]
    ld1b        z6.b, p0/z, [src_ptr,  #6, mul vl]
    ld1b        z7.b, p0/z, [src_ptr,  #7, mul vl]
    .endm

    .macro ld1b_unroll16
    ld1b        z16.b, p0/z, [src_ptr, #-8, mul vl]
    ld1b        z17.b, p0/z, [src_ptr, #-7, mul vl]
    ld1b        z18.b, p0/z, [src_ptr, #-6, mul vl]
    ld1b        z19.b, p0/z, [src_ptr, #-5, mul vl]
    ld1b        z20.b, p0/z, [src_ptr, #-4, mul vl]
    ld1b        z21.b, p0/z, [src_ptr, #-3, mul vl]
    ld1b        z22.b, p0/z, [src_ptr, #-2, mul vl]
    ld1b        z23.b, p0/z, [src_ptr, #-1, mul vl]
    ld1b_unroll8
    .endm

    .macro stld1b_unroll2
    st1b        z0.b, p0,   [dest_ptr, #0, mul vl]
    st1b        z1.b, p0,   [dest_ptr, #1, mul vl]
    ld1b        z0.b, p0/z, [src_ptr,  #0, mul vl]
    ld1b        z1.b, p0/z, [src_ptr,  #1, mul vl]
    .endm

    .macro stld1b_unroll4a
    stld1b_unroll2
    st1b        z2.b, p0,   [dest_ptr, #2, mul vl]
    st1b        z3.b, p0,   [dest_ptr, #3, mul vl]
    ld1b        z2.b, p0/z, [src_ptr,  #2, mul vl]
    ld1b        z3.b, p0/z, [src_ptr,  #3, mul vl]
    .endm

    .macro stld1b_unroll4b
    st1b        z4.b, p0,   [dest_ptr, #4, mul vl]
    st1b        z5.b, p0,   [dest_ptr, #5, mul vl]
    ld1b        z4.b, p0/z, [src_ptr,  #4, mul vl]
    ld1b        z5.b, p0/z, [src_ptr,  #5, mul vl]
    st1b        z6.b, p0,   [dest_ptr, #6, mul vl]
    st1b        z7.b, p0,   [dest_ptr, #7, mul vl]
    ld1b        z6.b, p0/z, [src_ptr,  #6, mul vl]
    ld1b        z7.b, p0/z, [src_ptr,  #7, mul vl]
    .endm

    .macro stld1b_unroll8
    stld1b_unroll4a
    stld1b_unroll4b
    .endm

    .macro stld1b_unroll16
    st1b        z16.b, p0,   [dest_ptr, #-8, mul vl]
    st1b        z17.b, p0,   [dest_ptr, #-7, mul vl]
    ld1b        z16.b, p0/z, [src_ptr,  #-8, mul vl]
    ld1b        z17.b, p0/z, [src_ptr,  #-7, mul vl]
    st1b        z18.b, p0,   [dest_ptr, #-6, mul vl]
    st1b        z19.b, p0,   [dest_ptr, #-5, mul vl]
    ld1b        z18.b, p0/z, [src_ptr,  #-6, mul vl]
    ld1b        z19.b, p0/z, [src_ptr,  #-5, mul vl]
    st1b        z20.b, p0,   [dest_ptr, #-4, mul vl]
    st1b        z21.b, p0,   [dest_ptr, #-3, mul vl]
    ld1b        z20.b, p0/z, [src_ptr,  #-4, mul vl]
    ld1b        z21.b, p0/z, [src_ptr,  #-3, mul vl]
    st1b        z22.b, p0,   [dest_ptr, #-2, mul vl]
    st1b        z23.b, p0,   [dest_ptr, #-1, mul vl]
    ld1b        z22.b, p0/z, [src_ptr,  #-2, mul vl]
    ld1b        z23.b, p0/z, [src_ptr,  #-1, mul vl]
    stld1b_unroll8
    .endm

    .macro st1b_unroll2
    st1b        z0.b, p0,   [dest_ptr, #0, mul vl]
    st1b        z1.b, p0,   [dest_ptr, #1, mul vl]
    .endm

    .macro st1b_unroll4
    st1b_unroll2
    st1b        z2.b, p0,   [dest_ptr, #2, mul vl]
    st1b        z3.b, p0,   [dest_ptr, #3, mul vl]
    .endm

    .macro st1b_unroll8
    st1b_unroll4
    st1b        z4.b, p0,   [dest_ptr, #4, mul vl]
    st1b        z5.b, p0,   [dest_ptr, #5, mul vl]
    st1b        z6.b, p0,   [dest_ptr, #6, mul vl]
    st1b        z7.b, p0,   [dest_ptr, #7, mul vl]
    .endm

    .macro st1b_unroll16
    st1b        z16.b, p0, [dest_ptr, #-8, mul vl]
    st1b        z17.b, p0, [dest_ptr, #-7, mul vl]
    st1b        z18.b, p0, [dest_ptr, #-6, mul vl]
    st1b        z19.b, p0, [dest_ptr, #-5, mul vl]
    st1b        z20.b, p0, [dest_ptr, #-4, mul vl]
    st1b        z21.b, p0, [dest_ptr, #-3, mul vl]
    st1b        z22.b, p0, [dest_ptr, #-2, mul vl]
    st1b        z23.b, p0, [dest_ptr, #-1, mul vl]
    st1b_unroll8
    .endm

ENTRY_ALIGN (MEMCPY, 6)

    PTR_ARG (0)
    PTR_ARG (1)
    SIZE_ARG (2)

L(memcpy):
    cbz         n, 3f
    // shortcut for less than CACHE_LINE_SIZE 256B
    cmp         n, CACHE_LINE_SIZE
    b.cs        1f
    mov         tmp1, 0
2:  whilelt     p1.b, tmp1, n
    b.none      3f
    ld1b        z0.b, p1/z, [src, tmp1]
    st1b        z0.b, p1, [dest, tmp1]
    incb        tmp1
    b           2b
3:  ret
    // equal to or more than CACHE_LINE_SIZE 256B
1:  mov         rest, n
    mov         dest_ptr, dest
    mov         src_ptr, src
    cntb        vector_length
    ptrue       p0.b

L(L2):
    // if rest >= L2_SIZE
    cmp         rest, L2_SIZE
    b.cc        L(L1_prefetch)

    // align dest address at vector_length byte boundary
    sub         tmp1, vector_length, 1
    and         tmp2, dest_ptr, tmp1
    // if vl_remainder == 0
    cmp         tmp2, 0
    b.eq        1f
    sub         vl_remainder, vector_length, tmp2
    // process remainder until the first vector_length boundary
    whilelt     p2.b, xzr, vl_remainder
    ld1b        z0.b, p2/z, [src_ptr]
    st1b        z0.b, p2, [dest_ptr]
    add         dest_ptr, dest_ptr, vl_remainder
    add         src_ptr, src_ptr, vl_remainder
    sub         rest, rest, vl_remainder
    // align dest address at CACHE_LINE_SIZE byte boundary
1:  mov         tmp1, CACHE_LINE_SIZE
    and         tmp2, dest_ptr, CACHE_LINE_SIZE - 1
    // if cl_remainder == 0
    cmp         tmp2, 0
    b.eq        L(L2_dc_zva)
    sub         cl_remainder, tmp1, tmp2
    // process remainder until the first CACHE_LINE_SIZE boundary
    mov         tmp1, xzr       // index
2:  whilelt     p2.b, tmp1, cl_remainder
    ld1b        z0.b, p2/z, [src_ptr, tmp1]
    st1b        z0.b, p2, [dest_ptr, tmp1]
    incb        tmp1
    cmp         tmp1, cl_remainder
    b.lo        2b
    add         dest_ptr, dest_ptr, cl_remainder
    add         src_ptr, src_ptr, cl_remainder
    sub         rest, rest, cl_remainder

L(L2_dc_zva): // unroll zero fill
    and         tmp1, dest, 0xffffffffffffff
    and         tmp2, src, 0xffffffffffffff
    sub         tmp1, tmp2, tmp1        // diff
    mov         tmp2, CACHE_LINE_SIZE * 20
    cmp         tmp1, tmp2
    b.lo        L(L1_prefetch)
    mov         tmp1, dest_ptr
    dc_zva      (ZF_DIST / CACHE_LINE_SIZE) - 1

L(L2_vl_64): // VL64 unroll8
    cmp         vector_length, 64
    b.ne        L(L2_vl_32)
    .p2align 3
    ld1b_unroll8
    add         src_ptr, src_ptr, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    .p2align 3
1:  stld1b_unroll4a
    mov         tmp1, PF_DIST_L1
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pldl2keep, [src_ptr, tmp1]
    mov         tmp2, ZF_DIST
    add         tmp2, dest_ptr, tmp2
    dc          zva, tmp2
    stld1b_unroll4b
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pldl2keep, [src_ptr, tmp1]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b
    st1b_unroll8
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2

L(L2_vl_32): // VL32 unroll6
    cmp         vector_length, 32
    b.ne        L(L2_vl_16)
    .p2align 3
    ld1b_unroll8
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE
    .p2align 3
1:  stld1b_unroll8
    mov         tmp1, PF_DIST_L1
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pldl2keep, [src_ptr, tmp1]
    mov         tmp2, ZF_DIST
    add         tmp2, dest_ptr, tmp2
    dc          zva, tmp2
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    stld1b_unroll8
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pldl2keep, [src_ptr, tmp1]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b
    st1b_unroll8
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE

L(L2_vl_16): // VL16 unroll32
    cmp         vector_length, 16
    b.ne        L(L1_prefetch)
    .p2align 3
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    ld1b_unroll16
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE
    .p2align 3
1:  add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    stld1b_unroll16
    mov         tmp1, PF_DIST_L1
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pldl2keep, [src_ptr, tmp1]
    mov         tmp2, ZF_DIST
    add         tmp2, dest_ptr, tmp2
    dc          zva, tmp2
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    stld1b_unroll16
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pldl2keep, [src_ptr, tmp1]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
    st1b_unroll16
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2

L(L1_prefetch): // if rest >= L1_SIZE
    cmp         rest, L1_SIZE
    b.cc        L(vl_agnostic)
L(L1_vl_64):
    cmp         vector_length, 64
    b.ne        L(L1_vl_32)
    .p2align 3
    ld1b_unroll8
    add         src_ptr, src_ptr, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.cc        2f
    .p2align 3
1:  stld1b_unroll4a
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    stld1b_unroll4b
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b
2:  st1b_unroll8
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2

L(L1_vl_32):
    cmp         vector_length, 32
    b.ne        L(L1_vl_16)
    .p2align 3
    ld1b_unroll8
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE
    cmp         rest, CACHE_LINE_SIZE * 2
    b.cc        2f
    .p2align 3
1:  stld1b_unroll8
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    stld1b_unroll8
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b
2:  st1b_unroll8
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE

L(L1_vl_16):
    cmp         vector_length, 16
    b.ne        L(vl_agnostic)
    .p2align 3
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    ld1b_unroll16
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE
    cmp         rest, CACHE_LINE_SIZE * 2
    b.cc        2f
    .p2align 3
1:  add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    stld1b_unroll16
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE
    add         src_ptr, src_ptr, CACHE_LINE_SIZE
    stld1b_unroll16
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dest_ptr, tmp1]
    prfm        pldl1keep, [src_ptr, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dest_ptr, tmp1]
    prfm        pldl2keep, [src_ptr, tmp1]
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
    add         src_ptr, src_ptr, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2
2:  st1b_unroll16
    add         dest_ptr, dest_ptr, CACHE_LINE_SIZE / 2

L(vl_agnostic): // VL Agnostic

L(unroll8): // unrolling and software pipeline
    lsl         tmp1, vector_length, 3  // vector_length * 8
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(unroll4)
    ld1b_unroll8
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  stld1b_unroll8
    add         dest_ptr, dest_ptr, tmp1
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  st1b_unroll8
    add         dest_ptr, dest_ptr, tmp1

L(unroll4):
    lsl         tmp1, vector_length, 2  // vector_length * 4
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(unroll2)
    ld1b_unroll4
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  stld1b_unroll4a
    add         dest_ptr, dest_ptr, tmp1
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  st1b_unroll4
    add         dest_ptr, dest_ptr, tmp1

L(unroll2):
    lsl         tmp1, vector_length, 1  // vector_length * 2
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(unroll1)
    ld1b_unroll2
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  stld1b_unroll2
    add         dest_ptr, dest_ptr, tmp1
    add         src_ptr, src_ptr, tmp1
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  st1b_unroll2
    add         dest_ptr, dest_ptr, tmp1

L(unroll1):
    .p2align 3
1:  cmp         rest, vector_length
    b.cc        L(last)
    ld1b        z0.b, p0/z, [src_ptr]
    st1b        z0.b, p0,   [dest_ptr]
    add         dest_ptr, dest_ptr, vector_length
    add         src_ptr, src_ptr, vector_length
    sub         rest, rest, vector_length
    b           1b

    .p2align 3
L(last):
    cmp         rest, 0
    b.eq        1f
    whilelt     p2.b, xzr, rest
    ld1b        z0.b, p2/z, [src_ptr]
    st1b        z0.b, p2, [dest_ptr]
1:  ret

END (MEMCPY)
libc_hidden_builtin_def (MEMCPY)


ENTRY_ALIGN (MEMMOVE, 6)

    PTR_ARG (0)
    PTR_ARG (1)
    SIZE_ARG (2)

    // remove tag address
    and         dest_ptr, dest, 0xffffffffffffff
    and         src_ptr, src, 0xffffffffffffff
    cmp         n, 0
    ccmp        dest_ptr, src_ptr, 4, ne
    b.ne        1f
    ret
1:  mov         rest, n
    cntb        vector_length
    ptrue       p0.b
    // shortcut for less than vector_length * 4
    cmp         rest, vector_length
    b.hi        1f
    whilelt     p1.b, xzr, rest
    ld1b        z1.b, p1/z, [src]
    st1b        z1.b, p1, [dest]
    ret
1:  lsl         tmp1, vector_length, 1          // vector_length * 2
    cmp         rest, tmp1
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    sub         rest, rest, vector_length
    whilelt     p1.b, xzr, rest
    ld1b        z1.b, p1/z, [src, #1, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p1, [dest, #1, mul vl]
    ret
1:  add         tmp2, tmp1, vector_length       // vector_length * 3
    cmp         rest, tmp2
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    sub         rest, rest, tmp1                // sub vector_length * 2
    whilelt     p1.b, xzr, rest
    ld1b        z2.b, p1/z, [src, #2, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p1, [dest, #2, mul vl]
    ret
1:  add         tmp1, tmp2, vector_length       // vector_length * 4
    cmp         rest, tmp1
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    ld1b        z2.b, p0/z, [src, #2, mul vl]
    sub         rest, rest, tmp2                // sub vector_length * 3
    whilelt     p1.b, xzr, rest
    ld1b        z3.b, p1/z, [src, #3, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p0, [dest, #2, mul vl]
    st1b        z3.b, p1, [dest, #3, mul vl]
    ret
1:  add         tmp2, tmp1, vector_length       // vector_length * 5
    cmp         rest, tmp2
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    ld1b        z2.b, p0/z, [src, #2, mul vl]
    ld1b        z3.b, p0/z, [src, #3, mul vl]
    sub         rest, rest, tmp1                // sub vector_length * 4
    whilelt     p1.b, xzr, rest
    ld1b        z4.b, p1/z, [src, #4, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p0, [dest, #2, mul vl]
    st1b        z3.b, p0, [dest, #3, mul vl]
    st1b        z4.b, p1, [dest, #4, mul vl]
    ret
1:  add         tmp1, tmp2, vector_length       // vector_length * 6
    cmp         rest, tmp1
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    ld1b        z2.b, p0/z, [src, #2, mul vl]
    ld1b        z3.b, p0/z, [src, #3, mul vl]
    ld1b        z4.b, p0/z, [src, #4, mul vl]
    sub         rest, rest, tmp2                // sub vector_length * 5
    whilelt     p1.b, xzr, rest
    ld1b        z5.b, p1/z, [src, #5, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p0, [dest, #2, mul vl]
    st1b        z3.b, p0, [dest, #3, mul vl]
    st1b        z4.b, p0, [dest, #4, mul vl]
    st1b        z5.b, p1, [dest, #5, mul vl]
    ret
1:  add         tmp2, tmp1, vector_length       // vector_length * 7
    cmp         rest, tmp2
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    ld1b        z2.b, p0/z, [src, #2, mul vl]
    ld1b        z3.b, p0/z, [src, #3, mul vl]
    ld1b        z4.b, p0/z, [src, #4, mul vl]
    ld1b        z5.b, p0/z, [src, #5, mul vl]
    sub         rest, rest, tmp1                // sub vector_length * 6
    whilelt     p1.b, xzr, rest
    ld1b        z6.b, p1/z, [src, #6, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p0, [dest, #2, mul vl]
    st1b        z3.b, p0, [dest, #3, mul vl]
    st1b        z4.b, p0, [dest, #4, mul vl]
    st1b        z5.b, p0, [dest, #5, mul vl]
    st1b        z6.b, p1, [dest, #6, mul vl]
    ret
1:  add         tmp1, tmp2, vector_length       // vector_length * 8
    cmp         rest, tmp1
    b.hi        1f
    ld1b        z0.b, p0/z, [src, #0, mul vl]
    ld1b        z1.b, p0/z, [src, #1, mul vl]
    ld1b        z2.b, p0/z, [src, #2, mul vl]
    ld1b        z3.b, p0/z, [src, #3, mul vl]
    ld1b        z4.b, p0/z, [src, #4, mul vl]
    ld1b        z5.b, p0/z, [src, #5, mul vl]
    ld1b        z6.b, p0/z, [src, #6, mul vl]
    sub         rest, rest, tmp2                // sub vector_length * 7
    whilelt     p1.b, xzr, rest
    ld1b        z7.b, p1/z, [src, #7, mul vl]
    st1b        z0.b, p0, [dest, #0, mul vl]
    st1b        z1.b, p0, [dest, #1, mul vl]
    st1b        z2.b, p0, [dest, #2, mul vl]
    st1b        z3.b, p0, [dest, #3, mul vl]
    st1b        z4.b, p0, [dest, #4, mul vl]
    st1b        z5.b, p0, [dest, #5, mul vl]
    st1b        z6.b, p0, [dest, #6, mul vl]
    st1b        z7.b, p1, [dest, #7, mul vl]
    ret
    // end of shortcut

    // tmp1 = dest - src
1:  sub         tmp1, dest_ptr, src_ptr
    // tmp2 = src - dest
    neg         tmp2, tmp1
    cmp         tmp1, 0
    b.gt        1f
    // if src - dest > 0 and
    // if src - dest >= n then memcpy else L(fwd_start)
    cmp         tmp2, n
    b.cs        L(memcpy)
    b           L(fwd_start)
    // if dest - src >= 0 and
    // if dest - src >= n then memcpy else L(bwd_start)
1:  cmp         tmp1, n
    b.cs        L(memcpy)

L(bwd_start):
    add         dest_ptr, dest, n       // dest_end
    add         src_ptr, src, n         // src_end

L(bwd_unroll8): // unrolling and software pipeline
    lsl         tmp1, vector_length, 3  // vector_length * 8
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(bwd_unroll4)
    sub         src_ptr, src_ptr, tmp1
    ld1b_unroll8
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  sub         src_ptr, src_ptr, tmp1
    sub         dest_ptr, dest_ptr, tmp1
    stld1b_unroll8
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  sub         dest_ptr, dest_ptr, tmp1
    st1b_unroll8

L(bwd_unroll4):
    lsl         tmp1, vector_length, 2  // vector_length * 4
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(bwd_unroll2)
    sub         src_ptr, src_ptr, tmp1
    ld1b_unroll4
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  sub         src_ptr, src_ptr, tmp1
    sub         dest_ptr, dest_ptr, tmp1
    stld1b_unroll4a
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  sub         dest_ptr, dest_ptr, tmp1
    st1b_unroll4

L(bwd_unroll2):
    lsl         tmp1, vector_length, 1  // vector_length * 2
    .p2align 3
    cmp         rest, tmp1
    b.cc        L(bwd_unroll1)
    sub         src_ptr, src_ptr, tmp1
    ld1b_unroll2
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.cc        2f
    .p2align 3
1:  sub         src_ptr, src_ptr, tmp1
    sub         dest_ptr, dest_ptr, tmp1
    stld1b_unroll2
    sub         rest, rest, tmp1
    cmp         rest, tmp1
    b.ge        1b
2:  sub         dest_ptr, dest_ptr, tmp1
    st1b_unroll2

L(bwd_unroll1):
    .p2align 3
1:  cmp         rest, vector_length
    b.cc        L(bwd_last)
    sub         src_ptr, src_ptr, vector_length
    sub         dest_ptr, dest_ptr, vector_length
    ld1b        z0.b, p0/z, [src_ptr]
    st1b        z0.b, p0, [dest_ptr]
    sub         rest, rest, vector_length
    b           1b

    .p2align 3
L(bwd_last):
    whilelt     p2.b, xzr, rest
    sub         src_ptr, src_ptr, rest
    sub         dest_ptr, dest_ptr, rest
    ld1b        z0.b, p2/z, [src_ptr]
    st1b        z0.b, p2, [dest_ptr]
    ret

L(fwd_start):
    mov         dest_ptr, dest
    mov         src_ptr, src
    b           L(vl_agnostic)

END (MEMMOVE)
libc_hidden_builtin_def (MEMMOVE)
#endif /* IS_IN (libc) */
#endif /* HAVE_SVE_ASM_SUPPORT */
