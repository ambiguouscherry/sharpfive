#!/bin/bash
# measure.sh <tag> [Label value]...  : set parameters via AX, then goto 5 / play / spectrum 3.6 s / stop
T=/Users/margot/.claude/jobs/4c72d7fa/tmp
tag=$1; shift
while [ $# -ge 2 ]; do $T/axparam set "$1" "$2"; shift 2; done
$T/axparam list
printf 'goto 5\n' > $T/cmd; sleep 5.5
printf 'pos\nplay\nsleep 300\nspectrum 3.6 %s/%s.raw\nstop\npos\n' $T $tag > $T/cmd; sleep 5.5
grep -E 'SPECTRUM \{|^POS|ONSET' $T/tap3.log | tail -11
