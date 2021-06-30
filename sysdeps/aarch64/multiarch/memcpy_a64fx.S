/* Optimized memcpy for Fujitsu A64FX processor.
   Copyright (C) 2021 Free Software Foundation, Inc.

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

/* Assumptions:
 *
 * ARMv8.2-a, AArch64, unaligned accesses, sve
 *
 */

#define L2_SIZE		(8*1024*1024)/2	// L2 8MB/2
#define CACHE_LINE_SIZE	256
#define ZF_DIST		(CACHE_LINE_SIZE * 21)	// Zerofill distance
#define dest		x0
#define src		x1
#define n		x2	// size
#define tmp1		x3
#define tmp2		x4
#define tmp3		x5
#define rest		x6
#define dest_ptr	x7
#define src_ptr		x8
#define vector_length	x9

#if HAVE_AARCH64_SVE_ASM
# if IS_IN (libc)
#  define MEMCPY __memcpy_a64fx
#  define MEMMOVE __memmove_a64fx

	.arch armv8.2-a+sve

	.macro ld1b_unroll8
	ld1b	z0.b, p0/z, [src_ptr, #0, mul vl]
	ld1b	z1.b, p0/z, [src_ptr, #1, mul vl]
	ld1b	z2.b, p0/z, [src_ptr, #2, mul vl]
	ld1b	z3.b, p0/z, [src_ptr, #3, mul vl]
	ld1b	z4.b, p0/z, [src_ptr, #4, mul vl]
	ld1b	z5.b, p0/z, [src_ptr, #5, mul vl]
	ld1b	z6.b, p0/z, [src_ptr, #6, mul vl]
	ld1b	z7.b, p0/z, [src_ptr, #7, mul vl]
	.endm

	.macro stld1b_unroll4a
	st1b	z0.b, p0,   [dest_ptr, #0, mul vl]
	st1b	z1.b, p0,   [dest_ptr, #1, mul vl]
	ld1b	z0.b, p0/z, [src_ptr,  #0, mul vl]
	ld1b	z1.b, p0/z, [src_ptr,  #1, mul vl]
	st1b	z2.b, p0,   [dest_ptr, #2, mul vl]
	st1b	z3.b, p0,   [dest_ptr, #3, mul vl]
	ld1b	z2.b, p0/z, [src_ptr,  #2, mul vl]
	ld1b	z3.b, p0/z, [src_ptr,  #3, mul vl]
	.endm

	.macro stld1b_unroll4b
	st1b	z4.b, p0,   [dest_ptr, #4, mul vl]
	st1b	z5.b, p0,   [dest_ptr, #5, mul vl]
	ld1b	z4.b, p0/z, [src_ptr,  #4, mul vl]
	ld1b	z5.b, p0/z, [src_ptr,  #5, mul vl]
	st1b	z6.b, p0,   [dest_ptr, #6, mul vl]
	st1b	z7.b, p0,   [dest_ptr, #7, mul vl]
	ld1b	z6.b, p0/z, [src_ptr,  #6, mul vl]
	ld1b	z7.b, p0/z, [src_ptr,  #7, mul vl]
	.endm

	.macro stld1b_unroll8
	stld1b_unroll4a
	stld1b_unroll4b
	.endm

	.macro st1b_unroll8
	st1b	z0.b, p0, [dest_ptr, #0, mul vl]
	st1b	z1.b, p0, [dest_ptr, #1, mul vl]
	st1b	z2.b, p0, [dest_ptr, #2, mul vl]
	st1b	z3.b, p0, [dest_ptr, #3, mul vl]
	st1b	z4.b, p0, [dest_ptr, #4, mul vl]
	st1b	z5.b, p0, [dest_ptr, #5, mul vl]
	st1b	z6.b, p0, [dest_ptr, #6, mul vl]
	st1b	z7.b, p0, [dest_ptr, #7, mul vl]
	.endm

	.macro shortcut_for_small_size exit
	// if rest <= vector_length * 2
	whilelo p0.b, xzr, n
	whilelo	p1.b, vector_length, n
	ld1b	z0.b, p0/z, [src, #0, mul vl]
	ld1b	z1.b, p1/z, [src, #1, mul vl]
	b.last	1f
	st1b	z0.b, p0, [dest, #0, mul vl]
	st1b	z1.b, p1, [dest, #1, mul vl]
	ret

1:	// if rest > vector_length * 8
	cmp	n, vector_length, lsl 3 // vector_length * 8
	b.hi	\exit

	// if rest <= vector_length * 4
	lsl	tmp1, vector_length, 1  // vector_length * 2
	sub	n, n, tmp1
	whilelo p2.b, xzr, n
	whilelo p3.b, vector_length, n
	ld1b	z2.b, p2/z, [src, #2, mul vl]
	ld1b	z3.b, p3/z, [src, #3, mul vl]
	b.last	1f
	st1b	z0.b, p0, [dest, #0, mul vl]
	st1b	z1.b, p0, [dest, #1, mul vl]
	st1b	z2.b, p2, [dest, #2, mul vl]
	st1b	z3.b, p3, [dest, #3, mul vl]
	ret

1:	// if rest <= vector_length * 8
	sub	n, n, tmp1
	add	tmp2, tmp1, vector_length
	whilelo p4.b, xzr, n
	whilelo p5.b, vector_length, n
	whilelo p6.b, tmp1, n
	whilelo p7.b, tmp2, n

	ld1b	z4.b, p4/z, [src, #4, mul vl]
	ld1b	z5.b, p5/z, [src, #5, mul vl]
	ld1b	z6.b, p6/z, [src, #6, mul vl]
	ld1b	z7.b, p7/z, [src, #7, mul vl]
	st1b	z0.b, p0, [dest, #0, mul vl]
	st1b	z1.b, p0, [dest, #1, mul vl]
	st1b	z2.b, p0, [dest, #2, mul vl]
	st1b	z3.b, p0, [dest, #3, mul vl]
	st1b	z4.b, p4, [dest, #4, mul vl]
	st1b	z5.b, p5, [dest, #5, mul vl]
	st1b	z6.b, p6, [dest, #6, mul vl]
	st1b	z7.b, p7, [dest, #7, mul vl]
	ret
	.endm

ENTRY (MEMCPY)

	PTR_ARG (0)
	PTR_ARG (1)
	SIZE_ARG (2)

	cntb	vector_length
L(memmove_small):
	// shortcut for less than vector_length * 8
	// gives a free ptrue to p0.b for n >= vector_length
	shortcut_for_small_size L(vl_agnostic)
	// end of shortcut

L(vl_agnostic): // VL Agnostic
	mov	rest, n
	mov	dest_ptr, dest
	mov	src_ptr, src
	// if rest >= L2_SIZE && vector_length == 64 then L(L2)
	mov	tmp1, 64
	cmp	rest, L2_SIZE
	ccmp	vector_length, tmp1, 0, cs
	b.eq	L(L2)

L(unroll8): // unrolling and software pipeline
	lsl	tmp1, vector_length, 3	// vector_length * 8
	sub	rest, rest, tmp1
	ld1b_unroll8
	add	src_ptr, src_ptr, tmp1
	subs	rest, rest, tmp1
	b.cc	2f
	.p2align 4
1:	stld1b_unroll8
	add	dest_ptr, dest_ptr, tmp1
	add	src_ptr, src_ptr, tmp1
	subs	rest, rest, tmp1
	b.hs	1b
2:	st1b_unroll8
	add	dest_ptr, dest_ptr, tmp1
	add	rest, rest, tmp1

	.p2align 3
L(last):
	whilelo p0.b, xzr, rest
	whilelo	p1.b, vector_length, rest
	ld1b	z0.b, p0/z, [src_ptr, #0, mul vl]
	ld1b	z1.b, p1/z, [src_ptr, #1, mul vl]
	b.nlast	1f

	lsl	tmp1, vector_length, 1  // vector_length * 2
	sub	rest, rest, tmp1
	whilelo p2.b, xzr, rest
	whilelo p3.b, vector_length, rest
	ld1b	z2.b, p2/z, [src_ptr, #2, mul vl]
	ld1b	z3.b, p3/z, [src_ptr, #3, mul vl]
        b.nlast  2f

	sub	rest, rest, tmp1
	add	tmp2, tmp1, vector_length // vector_length * 3
	whilelo p4.b, xzr, rest
	whilelo p5.b, vector_length, rest
	whilelo p6.b, tmp1, rest
	whilelo p7.b, tmp2, rest

	ld1b	z4.b, p4/z, [src_ptr, #4, mul vl]
	ld1b	z5.b, p5/z, [src_ptr, #5, mul vl]
	ld1b	z6.b, p6/z, [src_ptr, #6, mul vl]
	ld1b	z7.b, p7/z, [src_ptr, #7, mul vl]
	st1b	z4.b, p4, [dest_ptr, #4, mul vl]
	st1b	z5.b, p5, [dest_ptr, #5, mul vl]
	st1b	z6.b, p6, [dest_ptr, #6, mul vl]
	st1b	z7.b, p7, [dest_ptr, #7, mul vl]
2:	st1b	z2.b, p2, [dest_ptr, #2, mul vl]
	st1b	z3.b, p3, [dest_ptr, #3, mul vl]
1:	st1b	z0.b, p0, [dest_ptr, #0, mul vl]
	st1b	z1.b, p1, [dest_ptr, #1, mul vl]
	ret

L(L2):
	// align dest address at CACHE_LINE_SIZE byte boundary
	and	tmp1, dest_ptr, CACHE_LINE_SIZE - 1
	sub	tmp1, tmp1, CACHE_LINE_SIZE
	ld1b	z1.b, p0/z, [src_ptr, #0, mul vl]
	ld1b	z2.b, p0/z, [src_ptr, #1, mul vl]
	ld1b	z3.b, p0/z, [src_ptr, #2, mul vl]
	ld1b	z4.b, p0/z, [src_ptr, #3, mul vl]
	st1b	z1.b, p0, [dest_ptr, #0, mul vl]
	st1b	z2.b, p0, [dest_ptr, #1, mul vl]
	st1b	z3.b, p0, [dest_ptr, #2, mul vl]
	st1b	z4.b, p0, [dest_ptr, #3, mul vl]
	sub	dest_ptr, dest_ptr, tmp1
	sub	src_ptr, src_ptr, tmp1
	add	rest, rest, tmp1

L(L2_dc_zva):
	// check for overlap
	sub	tmp1, src_ptr, dest_ptr
	and	tmp1, tmp1, 0xffffffffffffff	// clear tag bits
	mov	tmp2, ZF_DIST
	cmp	tmp1, tmp2
	b.lo	L(unroll8)

	// zero fill loop
	mov	tmp1, dest_ptr
	mov	tmp3, ZF_DIST / CACHE_LINE_SIZE
1:	dc	zva, tmp1
	add	tmp1, tmp1, CACHE_LINE_SIZE
	subs	tmp3, tmp3, 1
	b.ne	1b

	mov	tmp3, ZF_DIST + CACHE_LINE_SIZE * 2
	// unroll
	ld1b_unroll8
	add	src_ptr, src_ptr, CACHE_LINE_SIZE * 2
	sub	rest, rest, CACHE_LINE_SIZE * 2
	.p2align 4
2:	stld1b_unroll4a
	add	tmp1, dest_ptr, tmp2	// dest_ptr + ZF_DIST
	dc	zva, tmp1
	stld1b_unroll4b
	add	tmp1, tmp1, CACHE_LINE_SIZE
	dc	zva, tmp1
	add	dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2
	add	src_ptr, src_ptr, CACHE_LINE_SIZE * 2
	sub	rest, rest, CACHE_LINE_SIZE * 2
	cmp	rest, tmp3
	b.hs	2b
	st1b_unroll8
	add	dest_ptr, dest_ptr, CACHE_LINE_SIZE * 2
	b	L(unroll8)

END (MEMCPY)
libc_hidden_builtin_def (MEMCPY)


ENTRY_ALIGN (MEMMOVE, 4)

	PTR_ARG (0)
	PTR_ARG (1)
	SIZE_ARG (2)

	cntb	vector_length
        // diff = dest - src
	sub	tmp1, dest, src
	ands	tmp1, tmp1, 0xffffffffffffff    // clear tag bits
	b.eq	L(full_overlap)

	cmp	n, vector_length, lsl 3 // vector_length * 8
	b.ls	L(memmove_small)

	ptrue	p0.b
	// if diff < 0 || diff >= n then memcpy
	cmp	tmp1, n
	b.hs	L(vl_agnostic)

	// unrolling and software pipeline
	lsl	tmp1, vector_length, 3  // vector_length * 8
	add	dest_ptr, dest, n       // dest_end
	sub	rest, n, tmp1
	add	src_ptr, src, rest	// src_end
	ld1b_unroll8
	subs	rest, rest, tmp1
	b.cc	2f
	.p2align 4
1:	sub	src_ptr, src_ptr, tmp1
	sub	dest_ptr, dest_ptr, tmp1
	stld1b_unroll8
	subs	rest, rest, tmp1
	b.hs	1b
2:	sub	dest_ptr, dest_ptr, tmp1
	st1b_unroll8
	add	rest, rest, tmp1
	mov	dest_ptr, dest
	mov	src_ptr, src
	b	L(last)

L(full_overlap):
	ret

END (MEMMOVE)
libc_hidden_builtin_def (MEMMOVE)
# endif /* IS_IN (libc) */
#endif /* HAVE_AARCH64_SVE_ASM */
