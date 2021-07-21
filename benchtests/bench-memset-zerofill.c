/* Measure memset functions with zero fill data.
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
   License along with the GNU C Library; if not, see
   <https://www.gnu.org/licenses/>.  */

#define TEST_MAIN
#define TEST_NAME "memset"
#define START_SIZE (16 * 1024)
#define MIN_PAGE_SIZE (getpagesize () + 64 * 1024 * 1024)
#define BUF1PAGES 16
#define TIMEOUT (20 * 60)
#include "bench-string.h"

#include "json-lib.h"

void *generic_memset (void *, int, size_t);
typedef void *(*proto_t) (void *, int, size_t);

IMPL (MEMSET, 1)
IMPL (generic_memset, 0)

static void
__attribute__((noinline, noclone))
do_one_test (json_ctx_t *json_ctx, impl_t *impl, CHAR *s,
	     int c1 __attribute ((unused)), int c2 __attribute ((unused)),
	     size_t n)
{
  size_t i, j, iters = 32;
  timing_t start, stop, cur, latency = 0;

  for (i = 0; i < 2; i++)
    {
      CALL (impl, s, c1, n * 16);
      TIMING_NOW (start);
      for (j = 0; j < 16; j++)
        CALL (impl, s + n * j, c2, n);
      TIMING_NOW (stop);
      TIMING_DIFF (cur, start, stop);
      TIMING_ACCUM (latency, cur);
    }

  json_element_double (json_ctx, (double) latency / (double) iters);
}

static void
do_test (json_ctx_t *json_ctx, size_t align, int c1, int c2, size_t len)
{
  align &= getpagesize () - 1;
  if ((align + len) * sizeof (CHAR) > page_size)
    return;

  json_element_object_begin (json_ctx);
  json_attr_uint (json_ctx, "length", len);
  json_attr_uint (json_ctx, "alignment", align);
  json_attr_int (json_ctx, "char1", c1);
  json_attr_int (json_ctx, "char2", c2);
  json_array_begin (json_ctx, "timings");

  FOR_EACH_IMPL (impl, 0)
    {
      do_one_test (json_ctx, impl, (CHAR *) (buf1) + align, c1, c2, len);
      alloc_bufs ();
    }

  json_array_end (json_ctx);
  json_element_object_end (json_ctx);
}

int
test_main (void)
{
  json_ctx_t json_ctx;
  size_t i;
  int c1, c2;

  test_init ();

  json_init (&json_ctx, 0, stdout);

  json_document_begin (&json_ctx);
  json_attr_string (&json_ctx, "timing_type", TIMING_TYPE);

  json_attr_object_begin (&json_ctx, "functions");
  json_attr_object_begin (&json_ctx, TEST_NAME);
  json_attr_string (&json_ctx, "bench-variant", "zerofill");

  json_array_begin (&json_ctx, "ifuncs");
  FOR_EACH_IMPL (impl, 0)
    json_element_string (&json_ctx, impl->name);
  json_array_end (&json_ctx);

  json_array_begin (&json_ctx, "results");

  c2 = 0;
  for (c1 = 0; c1 < 2; c1++)
    for (i = START_SIZE; i <= MIN_PAGE_SIZE; i <<= 1)
      {
	do_test (&json_ctx, 0, c1, c2, i);
	do_test (&json_ctx, 3, c1, c2, i);
      }

  json_array_end (&json_ctx);
  json_attr_object_end (&json_ctx);
  json_attr_object_end (&json_ctx);
  json_document_end (&json_ctx);

  return ret;
}

#include <support/test-driver.c>

#define libc_hidden_builtin_def(X)
#define libc_hidden_def(X)
#define libc_hidden_weak(X)
#define weak_alias(X,Y)
#undef MEMSET
#define MEMSET generic_memset
#include <string/memset.c>
