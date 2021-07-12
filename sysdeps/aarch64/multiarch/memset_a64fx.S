/* Optimized memset for Fujitsu A64FX processor.
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
#include <sysdeps/aarch64/memset-reg.h>

/* Assumptions:
 *
 * ARMv8.2-a, AArch64, unaligned accesses, sve
 *
 */

#define L1_SIZE		(64*1024)	// L1 64KB
#define L2_SIZE         (8*1024*1024)	// L2 8MB - 1MB
#define CACHE_LINE_SIZE	256
#define PF_DIST_L1	(CACHE_LINE_SIZE * 16)	// Prefetch distance L1
#define vector_length	x9
#define tmp3	x10

#if HAVE_AARCH64_SVE_ASM
# if IS_IN (libc)
#  define MEMSET __memset_a64fx

	.arch armv8.2-a+sve

	.macro st1b_unroll first=0, last=7
	st1b	z0.b, p0, [dst, \first, mul vl]
	.if \last-\first
	st1b_unroll "(\first+1)", \last
	.endif
	.endm


#undef BTI_C
#define BTI_C

ENTRY (MEMSET)
	PTR_ARG (0)
	SIZE_ARG (2)

	dup	z0.b, valw
	whilelo	p0.b, xzr, count
	cntb	vector_length
	whilelo	p1.b, vector_length, count
	st1b	z0.b, p0, [dstin, 0, mul vl]
	st1b	z0.b, p1, [dstin, 1, mul vl]
	b.last	1f
	ret

	// count >= vector_length * 2
	.p2align 4
1:	add	dst, dstin, count
	cmp	count, vector_length, lsl 2
	b.hi	1f
	st1b	z0.b, p0, [dst, -2, mul vl]
	st1b	z0.b, p0, [dst, -1, mul vl]
	ret

	// count > vector_length * 4
1:	cmp	count, vector_length, lsl 3
	b.hi	L(vl_agnostic)
	st1b	z0.b, p0, [dstin, 2, mul vl]
	st1b	z0.b, p0, [dstin, 3, mul vl]
	st1b	z0.b, p0, [dst, -4, mul vl]
	st1b	z0.b, p0, [dst, -3, mul vl]
	st1b	z0.b, p0, [dst, -2, mul vl]
	st1b	z0.b, p0, [dst, -1, mul vl]
	ret

	// count >= vector_length * 8
	.p2align 4
L(vl_agnostic):
	mov	dst, dstin
	mov	tmp1, 64
	// if count >= L1_SIZE && vector_length == 64 then L(L1_prefetch)
	cmp	count, L1_SIZE
	ccmp	vector_length, tmp1, 0, cs
	b.eq	L(L1_prefetch)

L(unroll32):
	lsl	tmp1, vector_length, 3	// vector_length * 8
	lsl	tmp2, vector_length, 5	// vector_length * 32
	add	tmp3, tmp1, tmp2
	.p2align 4
1:	cmp	count, tmp3
	b.cc	L(unroll8)
	st1b_unroll
	add	dst, dst, tmp1
	st1b_unroll
	add	dst, dst, tmp1
	st1b_unroll
	add	dst, dst, tmp1
	st1b_unroll
	add	dst, dst, tmp1
	sub	count, count, tmp2
	b	1b

	// count >= 8 * vector_length
L(unroll8):
	lsl	tmp1, vector_length, 3
	sub	count, count, tmp1
	lsl	tmp2, vector_length, 1
	.p2align 4
1:	subs	count, count, tmp1
	st1b_unroll 0, 7
	add	dst, dst, tmp1
	b.hi	1b

	add	dst, dst, count
	add	count, count, tmp1
	cmp	count, tmp2
	b.ls	2f
	add	tmp2, vector_length, vector_length, lsl 2
	cmp	count, tmp2
	b.ls	5f
	st1b	z0.b, p0, [dst, 0, mul vl]
	st1b	z0.b, p0, [dst, 1, mul vl]
	st1b	z0.b, p0, [dst, 2, mul vl]
5:	st1b	z0.b, p0, [dst, 3, mul vl]
	st1b	z0.b, p0, [dst, 4, mul vl]
	st1b	z0.b, p0, [dst, 5, mul vl]
2:	st1b	z0.b, p0, [dst, 6, mul vl]
	st1b	z0.b, p0, [dst, 7, mul vl]
	ret

	// count >= L1_SIZE
	.p2align 3
L(L1_prefetch):
	cmp	count, L2_SIZE
	b.hs	L(L2)
1:	st1b_unroll 0, 3
	prfm	pstl1keep, [dst, PF_DIST_L1]
	st1b_unroll 4, 7
	prfm	pstl1keep, [dst, PF_DIST_L1 + CACHE_LINE_SIZE]
	add	dst, dst, CACHE_LINE_SIZE * 2
	sub	count, count, CACHE_LINE_SIZE * 2
	cmp	count, PF_DIST_L1
	b.hs	1b
	b	L(unroll8)

	// count >= L2_SIZE
L(L2):
	tst	valw, 255
	b.ne	L(unroll8)
	// align dst to CACHE_LINE_SIZE byte boundary
	and	tmp1, dst, CACHE_LINE_SIZE - 1
	sub	tmp1, tmp1, CACHE_LINE_SIZE
	st1b	z0.b, p0, [dst, 0, mul vl]
	st1b	z0.b, p0, [dst, 1, mul vl]
	st1b	z0.b, p0, [dst, 2, mul vl]
	st1b	z0.b, p0, [dst, 3, mul vl]
	sub	dst, dst, tmp1
	add	count, count, tmp1

	// clear cachelines using DC ZVA
	sub	count, count, CACHE_LINE_SIZE * 4
	.p2align 4
1:	dc	zva, dst
	add	dst, dst, CACHE_LINE_SIZE
	subs	count, count, CACHE_LINE_SIZE
	b.hs	1b
	add	count, count, CACHE_LINE_SIZE * 4
	b	L(unroll8)

END (MEMSET)
libc_hidden_builtin_def (MEMSET)

#endif /* IS_IN (libc) */
#endif /* HAVE_AARCH64_SVE_ASM */
