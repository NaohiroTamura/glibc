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
# Merge two benchout string files into one in terms of an ifunc
# in order to create a comparison graph
#
if [[ $1 == "-h" ]] || [[ $# != 3 ]]; then
  echo "Usage: ${0##*/} ifunc_name graph_tag1 graph_tag2"
  echo "  read two benchout string files from standard input"
  echo "  write merged benchout string file to standard output"
  echo "ex:"
  echo "  $ cat bench-memset-first.out bench-memset-second.out | \\
  > ${0##*/} __memset_generic graph_tag1 graph_tag2 | \\
  > plot_strings.py -l -p thru -v -"
exit 1
fi

jq -rs --arg ifunc_name $1 --arg graph_tag1 $2 --arg graph_tag2 $3 '
. as $root |
$root as [$first, $second] |
$first.functions |
  to_entries | . as $first_entry |
  .[0].value as $first_value |
$second.functions |
  to_entries | .[0].value as $second_value |
$first_value.ifuncs |
  length as $ifuncs_len |
  index($ifunc_name) as $ifunc_index |
[$first_value, $second_value] |
  del(.[].results[].timings[$ifunc_index+1:$ifuncs_len]) |
  del(.[].results[].timings[0:$ifunc_index]) |
  [.[].results] | transpose as $pair |
$pair |
  reduce range(0; $pair|length) as $i (
    []; . + [$pair[$i][0].timings+$pair[$i][1].timings]
  ) | . as $new_timings |
  reduce range(0; $pair|length) as $j (
    []; . + [{"length":$first_value.results[$j].length,
              "timings":$new_timings[$j]}]
  ) | . as $new_results |
$first_value |
  ."bench-variant"+="-"+$graph_tag1+"-"+$graph_tag2 |
  .ifuncs=[$ifunc_name+"-"+$graph_tag1,$ifunc_name+"-"+$graph_tag2] |
  .results=$new_results | . as $new_first_value |
$first_entry |
  .[0].value=$new_first_value | from_entries | . as $mem_func |
$first |
  .functions=$mem_func
'

