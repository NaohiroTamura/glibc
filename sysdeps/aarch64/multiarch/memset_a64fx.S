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
#define PF_DIST_L1 (CACHE_LINE_SIZE * 16)
#define PF_DIST_L2 (CACHE_LINE_SIZE * 128)
#define rest            x8
#define vector_length   x9
#define vl_remainder    x10     // vector_length remainder
#define cl_remainder    x11     // CACHE_LINE_SIZE remainder

    .arch armv8.2-a+sve

ENTRY_ALIGN (MEMSET, 6)

    PTR_ARG (0)
    SIZE_ARG (2)

    cmp         count, 0
    b.ne        L(init)
    ret
L(init):
    mov         rest, count
    mov         dst, dstin
    add         dstend, dstin, count
    cntb        vector_length
    ptrue       p0.b
    dup         z0.b, valw

    cmp         count, 96
    b.hi	L(set_long)
    cmp         count, 16
    b.hs	L(set_medium)
    mov         val, v0.D[0]

    /* Set 0..15 bytes.  */
    tbz         count, 3, 1f
    str         val, [dstin]
    str         val, [dstend, -8]
    ret
    nop
1:  tbz         count, 2, 2f
    str         valw, [dstin]
    str         valw, [dstend, -4]
    ret
2:  cbz         count, 3f
    strb        valw, [dstin]
    tbz         count, 1, 3f
    strh        valw, [dstend, -2]
3:  ret

    /* Set 17..96 bytes.  */
L(set_medium):
    str         q0, [dstin]
    tbnz        count, 6, L(set96)
    str         q0, [dstend, -16]
    tbz         count, 5, 1f
    str         q0, [dstin, 16]
    str         q0, [dstend, -32]
1:  ret

    .p2align 4
    /* Set 64..96 bytes.  Write 64 bytes from the start and
       32 bytes from the end.  */
L(set96):
    str         q0, [dstin, 16]
    stp         q0, q0, [dstin, 32]
    stp         q0, q0, [dstend, -32]
    ret

L(set_long):
    // if count > 1280 && vector_length != 16 then L(L2)
    cmp         count, 1280
    ccmp        vector_length, 16, 4, gt
    b.ne        L(L2)
    bic         dst, dstin, 15
    str         q0, [dstin]
    sub         count, dstend, dst      /* Count is 16 too large.  */
    sub         dst, dst, 16            /* Dst is biased by -32.  */
    sub         count, count, 64 + 16   /* Adjust count and bias for loop.  */
1:  stp         q0, q0, [dst, 32]
    stp         q0, q0, [dst, 64]!
    subs        count, count, 64
    b.lo        2f
    stp         q0, q0, [dst, 32]
    stp         q0, q0, [dst, 64]!
    subs        count, count, 64
    b.lo	2f
    stp         q0, q0, [dst, 32]
    stp         q0, q0, [dst, 64]!
    subs        count, count, 64
    b.lo        2f
    stp         q0, q0, [dst, 32]
    stp         q0, q0, [dst, 64]!
    subs        count, count, 64
    b.hi        1b
2:  stp         q0, q0, [dstend, -64]
    stp         q0, q0, [dstend, -32]
    ret

L(L2):
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
    whilelt     p0.b, xzr, vl_remainder
    st1b        z0.b, p0, [dst]
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
2:  whilelt     p0.b, tmp1, cl_remainder
    st1b        z0.b, p0, [dst, tmp1]
    incb        tmp1
    cmp         tmp1, cl_remainder
    b.lo        2b
    add         dst, dst, cl_remainder
    sub         rest, rest, cl_remainder

L(L2_dc_zva): // unroll zero fill
    mov         tmp1, dst
    dc          zva, tmp1               // 1
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 2
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 3
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 4
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 5
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 6
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 7
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 8
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 9
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 10
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 11
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 12
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 13
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 14
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 15
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 16
    add         tmp1, tmp1, CACHE_LINE_SIZE
    dc          zva, tmp1               // 17
    add         tmp1, tmp1, CACHE_LINE_SIZE

L(L2_vl_64): // VL64 unroll8
    cmp         vector_length, 64
    b.ne        L(L2_vl_32)
    ptrue       p0.b
    .p2align 3
1:  st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    mov         tmp2, CACHE_LINE_SIZE * 18
    add         tmp2, dst, tmp2
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 18
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 19
    add         dst, dst, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b

L(L2_vl_32): // VL32 unroll6
    cmp         vector_length, 32
    b.ne        L(L2_vl_16)
    ptrue       p0.b
    .p2align 3
1:  st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp2, CACHE_LINE_SIZE * 18
    add         tmp2, dst, tmp2
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 18
    add         dst, dst, CACHE_LINE_SIZE
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 19
    add         dst, dst, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b

L(L2_vl_16):  // VL16 unroll32
    cmp         vector_length, 16
    b.ne        L(L1_prefetch)
    ptrue       p0.b
    .p2align 3
1:  add         dst, dst, CACHE_LINE_SIZE / 2
    st1b        {z0.b}, p0, [dst, #-8, mul vl]
    st1b        {z0.b}, p0, [dst, #-7, mul vl]
    st1b        {z0.b}, p0, [dst, #-6, mul vl]
    st1b        {z0.b}, p0, [dst, #-5, mul vl]
    st1b        {z0.b}, p0, [dst, #-4, mul vl]
    st1b        {z0.b}, p0, [dst, #-3, mul vl]
    st1b        {z0.b}, p0, [dst, #-2, mul vl]
    st1b        {z0.b}, p0, [dst, #-1, mul vl]
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp2, CACHE_LINE_SIZE * 18
    add         tmp2, dst, tmp2
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 18
    add         dst, dst, CACHE_LINE_SIZE
    st1b        {z0.b}, p0, [dst, #-8, mul vl]
    st1b        {z0.b}, p0, [dst, #-7, mul vl]
    st1b        {z0.b}, p0, [dst, #-6, mul vl]
    st1b        {z0.b}, p0, [dst, #-5, mul vl]
    st1b        {z0.b}, p0, [dst, #-4, mul vl]
    st1b        {z0.b}, p0, [dst, #-3, mul vl]
    st1b        {z0.b}, p0, [dst, #-2, mul vl]
    st1b        {z0.b}, p0, [dst, #-1, mul vl]
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         tmp2, tmp2, CACHE_LINE_SIZE
    dc          zva, tmp2       // distance CACHE_LINE_SIZE * 19
    add         dst, dst, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, CACHE_LINE_SIZE * 2
    b.ge        1b

L(L1_prefetch): // if rest >= L1_SIZE
    cmp         rest, L1_SIZE
    b.cc        L(vl_agnostic)
L(L1_vl_64):
    cmp         vector_length, 64
    b.ne        L(L1_vl_32)
    ptrue       p0.b
    .p2align 3
1:  st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dst, tmp1]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE * 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b

L(L1_vl_32):
    cmp         vector_length, 32
    b.ne        L(L1_vl_16)
    ptrue       p0.b
    .p2align 3
1:  st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b

L(L1_vl_16):  // VL16 unroll32
    cmp         vector_length, 16
    b.ne        L(vl_agnostic)
    ptrue       p0.b
    .p2align 3
1:  mov         tmp1, dst
    add         dst, dst, CACHE_LINE_SIZE / 2
    st1b        {z0.b}, p0, [dst, #-8, mul vl]
    st1b        {z0.b}, p0, [dst, #-7, mul vl]
    st1b        {z0.b}, p0, [dst, #-6, mul vl]
    st1b        {z0.b}, p0, [dst, #-5, mul vl]
    st1b        {z0.b}, p0, [dst, #-4, mul vl]
    st1b        {z0.b}, p0, [dst, #-3, mul vl]
    st1b        {z0.b}, p0, [dst, #-2, mul vl]
    st1b        {z0.b}, p0, [dst, #-1, mul vl]
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp1, PF_DIST_L1
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE
    add         tmp1, tmp1, CACHE_LINE_SIZE
    st1b        {z0.b}, p0, [dst, #-8, mul vl]
    st1b        {z0.b}, p0, [dst, #-7, mul vl]
    st1b        {z0.b}, p0, [dst, #-6, mul vl]
    st1b        {z0.b}, p0, [dst, #-5, mul vl]
    st1b        {z0.b}, p0, [dst, #-4, mul vl]
    st1b        {z0.b}, p0, [dst, #-3, mul vl]
    st1b        {z0.b}, p0, [dst, #-2, mul vl]
    st1b        {z0.b}, p0, [dst, #-1, mul vl]
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    mov         tmp1, PF_DIST_L1 + CACHE_LINE_SIZE
    prfm        pstl1keep, [dst, tmp1]
    mov         tmp1, PF_DIST_L2 + CACHE_LINE_SIZE
    prfm        pstl2keep, [dst, tmp1]
    add         dst, dst, CACHE_LINE_SIZE / 2
    sub         rest, rest, CACHE_LINE_SIZE * 2
    cmp         rest, L1_SIZE
    b.ge        1b

    // VL Agnostic
L(vl_agnostic):
L(unroll32):
    ptrue       p0.b
    lsl         tmp1, vector_length, 3  // vector_length * 8
    lsl         tmp2, vector_length, 5  // vector_length * 32
    .p2align 3
1:  cmp         rest, tmp2
    b.cc        L(unroll8)
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         dst, dst, tmp1
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         dst, dst, tmp1
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         dst, dst, tmp1
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         dst, dst, tmp1
    sub         rest, rest, tmp2
    b           1b

L(unroll8):
    lsl         tmp1, vector_length, 3
    ptrue       p0.b
    .p2align 3
1:  cmp         rest, tmp1
    b.cc        L(unroll1)
    st1b        {z0.b}, p0, [dst]
    st1b        {z0.b}, p0, [dst, #1, mul vl]
    st1b        {z0.b}, p0, [dst, #2, mul vl]
    st1b        {z0.b}, p0, [dst, #3, mul vl]
    st1b        {z0.b}, p0, [dst, #4, mul vl]
    st1b        {z0.b}, p0, [dst, #5, mul vl]
    st1b        {z0.b}, p0, [dst, #6, mul vl]
    st1b        {z0.b}, p0, [dst, #7, mul vl]
    add         dst, dst, tmp1
    sub         rest, rest, tmp1
    b           1b

L(unroll1):
    ptrue       p0.b
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
    whilelt     p0.b, xzr, rest
    st1b        z0.b, p0, [dst]
1:  ret

END (MEMSET)
libc_hidden_builtin_def (MEMSET)

#endif /* IS_IN (libc) */
#endif /* HAVE_SVE_ASM_SUPPORT */
