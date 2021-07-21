#!/bin/bash
# Copyright (C) 2021 Free Software Foundation, Inc.
# This file is part of the GNU C Library.

# The GNU C Library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.

# The GNU C Library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public
# License along with the GNU C Library; if not, see
# <https://www.gnu.org/licenses/>.

#
# Convert benchout string JSON to CSV
#
if [[ $1 == "-h" ]] || [[ $# != 0 ]]; then
  echo "Usage: ${0##*/}"
  echo "  read benchout string JSON from standard input"
  echo "  write CSV to standard output"
  echo "ex:"
  echo "  $ cat bench-memset.out | ${0##*/} > bench-memset.csv"
exit 1
fi

jq -r '
  . as $root |
  . as {$functions} |
  $functions | to_entries | .[0].value as $func_value |
  $func_value as {$_, $ifuncs, $results} |
  (["timing_type", $root.timing_type] | @csv),
  (["functions", ($functions | keys | .[0]),
    "bench-variant", $func_value."bench-variant"] | @csv),
  ($results[0] | to_entries | map([.key]) | flatten | @csv),
  ($results[0] | reduce range(1; . | length) as $_ ([]; . + [""])
    + $ifuncs | @csv),
  ($results[] | to_entries | map([.value]) | flatten | @csv)
'
