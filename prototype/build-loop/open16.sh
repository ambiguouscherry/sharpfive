#!/bin/bash
T=/Users/margot/.claude/jobs/4c72d7fa/tmp
echo "$(date +%T) File > Open Recent > sharpfive-prototype"
$T/ui menu "File" "Open Recent" "sharpfive-prototype"
for i in $(seq 1 40); do
  sleep 3
  w=$($T/axdump windows 2>/dev/null | tr '\n' ' ')
  echo "$(date +%T) $w"
  if echo "$w" | grep -q "Tracks"; then break; fi
  f=$($T/axdump focused 2>/dev/null | head -30)
  btns=$(echo "$f" | grep -o "AXButton t='[^']*'" | sed "s/AXButton t=//" | tr '\n' ' ')
  [ -n "$btns" ] && echo "   buttons: $btns"
  if echo "$btns" | grep -q "'OK'"; then $T/axdump press "OK"; fi
done
date +%s > $T/t16_project_open
echo "$(date +%T) project open; full cycle $(( $(cat $T/t16_project_open) - $(cat $T/t16_restart_start) )) s from Save to Tracks window"
sleep 3
printf 'tap disconnect\nsleep 500\ntap connect\nsleep 1500\ntap status\npos\nlcd\nleds\n' > $T/cmd; sleep 4
grep -vE '◀ (LED|FADER|VPOT)|▶ MCU|^\s+[0-9.]+ ◀' $T/tap3.log | tail -12
