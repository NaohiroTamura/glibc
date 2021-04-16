/* Optimized memset for Fujitsu A64FX processor.
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
#include <sysdeps/aarch64/memset-reg.h>

#if HAVE_SVE_ASM_SUPPORT
#if IS_IN (libc)
# define MEMSET __memset_a64fx

/* Assumptions:
 *
 * ARMv8.2-a, AArch64, unaligned accesses, sve
 *
 */

#define L1_SIZE         (64*1024)       // L1 64KB
#define L2_SIZE         (8*1024*1024)   // L2 8MB - 1MB
#define CACHE_LINE_SIZE 256
#define PF_DIST_L1      (CACHE_LINE_SIZE * 16)  // Prefetch distance L1
#define PF_DIST_L2      (CACHE_LINE_SIZE * 128) // Prefetch distance L2
#define ZF_DIST         (CACHE_LINE_SIZE * 18)  // Zerofill distance
#define rest            x8
#define vector_length   x9
#define vl_remainder    x10     // vector_length remainder
#define cl_remainder    x11     // CACHE_LINE_SIZE remainder

    .arch armv8.2-a+sve

    .macro dc_zva times
    dc          zva, tmp1
    add         tmp1, tmp1, CACHE_LINE_SIZE
    .if \times-1
    dc_zva "(\times-1)"
    .endif
    .endm

    .macro st1b_unroll first=0, last=7
    st1b        {z0.b}, p0, [dst, #\first, mul vl]
    .if \last-\first
    st1b_unroll "(\first+1)", \last
    .endif
    .endm

// removed BTI_C from ENTRY (MEMSET)
    .globl __memset_a64fx
    .type __memset_a64fx, %function
    .p2align 6
__memset_a64fx:
    cfi_startproc
    CALL_MCOUNT

    PTR_ARG (0)
    SIZE_ARG (2)

    cbz         count, 3f
    dup         z0.b, valw
    // shortcut for less than CACHE_LINE_SIZE 512B
    cmp         count, CACHE_LINE_SIZE * 2
    b.cs        1f
    mov         tmp1, 0
2:  whilelt     p1.b, tmp1, count
    b.none      3f
    st1b        z0.b, p1, [dstin, tmp1]
    incb        tmp1
    b           2b
3:  ret
    // equal to or more than CACHE_LINE_SIZE 512B
1:  mov         rest, count
    mov         dst, dstin
    add         dstend, dstin, count
    cntb        vector_length
    ptrue       p0.b

L(L2):
    // if VL == 64
    cmp         vector_length, 64
    b.ne        L(vl_agnostic)
    // if rest >= L2_SIZE
    cmp         rest, L2_SIZE
    b.cc        L(L1_prefetch)

    // align dst address at vector_length byte boundary
    sub         tmp1, vector_length, 1
    and         tmp2, dst, tmp1
    // if vl_remainder == 0
    cmp         tmp2, 0
    b.eq        1f
    sub         vl_remainder, vector_length, tmp2
    // process remainder until the first vector_length boundary
    whilelt     p2.b, xzr, vl_remainder
    st1b        z0.b, p2, [dst]
    add         dst, dst, vl_remainder
    sub         rest, rest, vl_remainder
    // align dstin address at CACHE_LINE_SIZE byte boundary
1:  mov         tmp1, CACHE_LINE_SIZE
    and         tmp2, dst, CACHE_LINE_SIZE - 1
    // if cl_remainder == 0
    cmp         tmp2, 0
    b.eq        L(L2_dc_zva)
    sub         cl_remainder, tmp1, tmp2
    // process remainder until the first CACHE_LINE_SIZE boundary
    mov         tmp1, xzr       // index
2:  whilelt     p2.b, tmp1, cl_remainder
    st1b        z0.b, p2, [dst, tmp1]
    incb        tmp1
    cmp         tmp1, cl_remainder
    b.lo        2b
    add         dst, dst, cl_remainder
    sub         rest, rest, cl_remainder

L(L2_dc_zva):
    // zero fill
    mov         tmp1, dst
    dc_zva      (ZF_DIST / CACHE_LINE_SIZE) - 1
    // unroll
    .p2align 3
1:  st1b_unroll 0, 3
    mov         tmp2, ZF_DIST
    add         tmp2, dst, tmp2
    dc          zva, tmp2
    st1b_unroll 4, 7
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2
    add         dst, dst, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b

L(L1_prefetch): // if rest >= L1_SIZE
    cmp         rest, L1_SIZE
    b.cc        L(vl_agnostic)
    .p2align 3
1:  st1b_unroll 0, 3
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dst, tmp1]
    st1b_unroll 4, 7
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b

L(vl_agnostic): // VL Agnostic

L(unroll32):
    lsl         tmp1, vector_length, 3  // vector_length * 8
    lsl         tmp2, vector_length, 5  // vector_length * 32
    .p2align 3
1:  cmp         rest, tmp2
    b.cc        L(unroll8)
    st1b_unroll
    add         dst, dst, tmp1
    st1b_unroll
    add         dst, dst, tmp1
    st1b_unroll
    add         dst, dst, tmp1
    st1b_unroll
    add         dst, dst, tmp1
    sub         rest, rest, tmp2
    b           1b

L(unroll8):
    lsl         tmp1, vector_length, 3
    .p2align 3
1:  cmp         rest, tmp1
    b.cc        L(unroll4)
    st1b_unroll
    add         dst, dst, tmp1
    sub         rest, rest, tmp1
    b           1b

L(unroll4):
    lsl         tmp1, vector_length, 2
    .p2align 3
1:  cmp         rest, tmp1
    b.cc        L(unroll2)
    st1b_unroll 0, 3
    add         dst, dst, tmp1
    sub         rest, rest, tmp1
    b           1b

L(unroll2):
    lsl         tmp1, vector_length, 1
    .p2align 3
1:  cmp         rest, tmp1
    b.cc        L(unroll1)
    st1b_unroll 0, 1
    add         dst, dst, tmp1
    sub         rest, rest, tmp1
    b           1b

L(unroll1):
    .p2align 3
1:  cmp         rest, vector_length
    b.cc        L(last)
    st1b        {z0.b}, p0, [dst]
    sub         rest, rest, vector_length
    add         dst, dst, vector_length
    b           1b

    .p2align 3
L(last):
    cmp         rest, 0
    b.eq        1f
    whilelt     p2.b, xzr, rest
    st1b        z0.b, p2, [dst]
1:  ret

END (MEMSET)
libc_hidden_builtin_def (MEMSET)

#endif /* IS_IN (libc) */
#endif /* HAVE_SVE_ASM_SUPPORT */
